"""
vehnet — the vehicle network model behind the Diagnostics module map.

Describes the modules installed on the truck, which bus each lives on, and how
the tool reaches them (PC -> OBDX GT -> DLC -> bus -> module). The localizer
turns raw scan results into a per-segment verdict so the UI can point at WHERE
the communication pipeline broke, not just report "no data".

Pure stdlib — unit-tested without Qt or hardware.

Network reference: 2010 Silverado 1500 (GMT900).
  HS-GMLAN (2-wire CAN, 500 kb/s, DLC pins 6/14): powertrain + chassis.
  SW-GMLAN (single-wire CAN, 33.3 kb/s, DLC pin 1): body/comfort.
The ELM327-compatible HS-CAN path of the OBDX GT cannot open the single-wire
bus, so SW modules are UNREACHABLE (amber), which is not the same as FAILED.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional

HS = "HS-GMLAN (500k)"
SW = "SW-GMLAN (33.3k)"


@dataclass(frozen=True)
class ModuleDef:
    key: str
    name: str
    bus: str
    req_id: Optional[str]     # 11-bit physical request CAN id (hex) or None
    resp_id: Optional[str]    # expected response id (hex) or None
    obd_responder: bool       # answers the functional OBD 0100 broadcast
    role: str                 # one-line description for the details panel


# Diagnostic addressing per GM 11-bit GMLAN convention (7E0/7E8 powertrain,
# 241/641 chassis). SW modules carry no HS ids — unreachable from this path.
MODULES: list[ModuleDef] = [
    ModuleDef("ecm",  "ECM (E38)",        HS, "7E0", "7E8", True,
              "Engine control — fueling, spark, DoD/AFM"),
    ModuleDef("tcm",  "TCM (T43)",        HS, "7E1", "7E9", True,
              "6L80 transmission — shifts, TCC, line pressure"),
    ModuleDef("ebcm", "EBCM (ABS)",       HS, "241", "641", False,
              "Brake control — ABS, traction, StabiliTrak"),
    ModuleDef("bcm",  "BCM",              SW, None, None, False,
              "Body control — power, lighting, gateway to SW bus"),
    ModuleDef("ipc",  "IPC (cluster)",    SW, None, None, False,
              "Instrument cluster — gauges, DIC, chimes"),
    ModuleDef("sdm",  "SDM (airbag)",     SW, None, None, False,
              "Inflatable restraint sensing and deployment"),
    ModuleDef("hvac", "HVAC",             SW, None, None, False,
              "Climate control head and actuators"),
    ModuleDef("radio", "Radio",           SW, None, None, False,
              "Entertainment head unit"),
    ModuleDef("tccm", "TCCM (4WD)",       SW, None, None, False,
              "Transfer case shift control"),
]


class Status(Enum):
    UNKNOWN = "unknown"          # not scanned yet
    OK = "responding"            # answered a request this scan
    SILENT = "no response"       # reachable path, expected an answer, none came
    UNREACHABLE = "unreachable"  # current tool path cannot address this bus


class SegStatus(Enum):
    UNKNOWN = "unknown"
    OK = "ok"
    FAILED = "failed"
    UNREACHABLE = "unreachable"


@dataclass
class ScanResult:
    """Raw facts from one scan pass, in pipeline order."""
    port_open: bool                      # PC -> OBDX GT serial link
    interface_alive: bool                # GT answered an AT command
    dlc_volts: Optional[float]           # ATRV reading (None = no answer)
    hs_responders: set[str]              # response CAN ids seen on 0100 bcast
    pinged: dict[str, bool]              # module key -> physical ping answered


@dataclass
class Verdict:
    segments: dict[str, SegStatus]       # pc_gt / gt_dlc / dlc_hs / dlc_sw
    modules: dict[str, Status]           # module key -> status
    failure_point: Optional[str]         # first broken segment, pipeline order
    notes: list[str]


def localize(scan: ScanResult) -> Verdict:
    """Walk the pipeline in order; the first dead stage explains everything
    downstream (downstream stages stay UNKNOWN, not FAILED)."""
    segs = {"pc_gt": SegStatus.UNKNOWN, "gt_dlc": SegStatus.UNKNOWN,
            "dlc_hs": SegStatus.UNKNOWN, "dlc_sw": SegStatus.UNREACHABLE}
    mods = {m.key: Status.UNKNOWN for m in MODULES}
    for m in MODULES:
        if m.bus == SW:
            mods[m.key] = Status.UNREACHABLE
    notes: list[str] = []
    failure: Optional[str] = None

    # Stage 1: PC -> GT (serial port + interface answering AT)
    if not scan.port_open or not scan.interface_alive:
        segs["pc_gt"] = SegStatus.FAILED
        notes.append("OBDX GT not reachable — check USB cable / COM port.")
        return Verdict(segs, mods, "pc_gt", notes)
    segs["pc_gt"] = SegStatus.OK

    # Stage 2: GT -> DLC (battery voltage present at pin 16)
    if scan.dlc_volts is None or scan.dlc_volts < 6.0:
        segs["gt_dlc"] = SegStatus.FAILED
        notes.append("No/low battery voltage at the DLC — is the GT plugged "
                     "into the truck, and is DLC pin 16 fused circuit alive?")
        return Verdict(segs, mods, "gt_dlc", notes)
    segs["gt_dlc"] = SegStatus.OK

    # Stage 3: DLC -> HS bus (anything answered the functional broadcast
    # or a physical ping)
    any_hs = bool(scan.hs_responders) or any(
        ok for k, ok in scan.pinged.items()
        if ok and _module(k) and _module(k).bus == HS)
    if not any_hs:
        segs["dlc_hs"] = SegStatus.FAILED
        notes.append("HS-GMLAN completely silent — ignition off, bus wiring "
                     "(DLC pins 6/14), or total bus fault.")
        for m in MODULES:
            if m.bus == HS:
                mods[m.key] = Status.UNKNOWN
        return Verdict(segs, mods, "dlc_hs", notes)
    segs["dlc_hs"] = SegStatus.OK

    # Stage 4: individual HS modules
    for m in MODULES:
        if m.bus != HS:
            continue
        answered = (m.resp_id and m.resp_id.upper() in
                    {r.upper() for r in scan.hs_responders}) \
            or scan.pinged.get(m.key, False)
        if answered:
            mods[m.key] = Status.OK
        elif m.key in scan.pinged or m.obd_responder:
            mods[m.key] = Status.SILENT
            if failure is None:
                failure = f"module:{m.key}"
            notes.append(f"{m.name} did not answer on {m.bus} — module, "
                         f"connector, or its bus stub.")
        else:
            mods[m.key] = Status.UNKNOWN

    notes.append("SW-GMLAN (BCM/IPC/body) is not reachable over the ELM "
                 "HS-CAN path — needs the GT's single-wire mode (future).")
    return Verdict(segs, mods, failure, notes)


def _module(key: str) -> Optional[ModuleDef]:
    for m in MODULES:
        if m.key == key:
            return m
    return None
