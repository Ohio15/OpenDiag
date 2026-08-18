"""
gt.py -- OBDX Pro GT live transport (ELM327 v2.1 compatible) + OBD-II polling.

The OBDX Pro GT enumerates as a USB CDC virtual COM port (STM32, VID 0483 /
PID 5740) and speaks the ELM327 command set. This module is the CLI/transport
seam the dashboard's GtDataSource wraps:

    open() / close() / command(cmd) / request_raw(mode_pid)

plus poll_once() which reads the supported mode-01 PIDs and decodes them into
OpenOBD canonical channel keys (see logbin.CANONICAL) with GAUGE_SPECS units
(vss in mph, temps in F, fuel pressure in psi).

Read-only: only ELM AT config + OBD mode-01 requests are issued. No ECU writes.
"""
from __future__ import annotations

import re
import time
from typing import Optional

try:
    import serial
    from serial.tools import list_ports
except ImportError:  # pyserial optional until the GT path is used
    serial = None
    list_ports = None


def _u16(b):
    return b[0] * 256 + b[1]


# pid byte (mode 01) -> (canonical_key, decode(list[int]) -> float in gauge units)
PID_TABLE = {
    "04": ("load",         lambda b: b[0] * 100.0 / 255.0),        # %
    "05": ("ect",          lambda b: (b[0] - 40) * 9 / 5 + 32),    # F
    "06": ("stft",         lambda b: (b[0] - 128) * 100.0 / 128),  # %
    "07": ("ltft",         lambda b: (b[0] - 128) * 100.0 / 128),  # %
    "0A": ("fuel_press",   lambda b: b[0] * 3 * 0.1450377),        # kPa->psi
    "0B": ("map",          lambda b: float(b[0])),                 # kPa
    "0C": ("rpm",          lambda b: _u16(b) / 4.0),               # rpm
    "0D": ("vss",          lambda b: b[0] * 0.6213712),            # km/h->mph
    "0E": ("spark",        lambda b: b[0] / 2.0 - 64.0),           # deg
    "0F": ("iat",          lambda b: (b[0] - 40) * 9 / 5 + 32),    # F
    "10": ("maf",          lambda b: _u16(b) / 100.0),             # g/s
    "11": ("tps",          lambda b: b[0] * 100.0 / 255.0),        # %
    "1F": ("run_time",     lambda b: float(_u16(b))),              # s
    "2F": ("fuel_level",   lambda b: b[0] * 100.0 / 255.0),        # %
    "33": ("baro",         lambda b: float(b[0])),                 # kPa
    "42": ("voltage",      lambda b: _u16(b) / 1000.0),            # V
    "44": ("eq_ratio",     lambda b: _u16(b) * 2.0 / 65536.0),     # lambda
    "46": ("ambient",      lambda b: (b[0] - 40) * 9 / 5 + 32),    # F
    "49": ("app",          lambda b: b[0] * 100.0 / 255.0),        # %
    "4C": ("cmd_throttle", lambda b: b[0] * 100.0 / 255.0),        # %
    "52": ("ethanol",      lambda b: b[0] * 100.0 / 255.0),        # %
}

# canonical keys this transport can ever surface (for gauge pre-build)
CANONICAL_KEYS = sorted({v[0] for v in PID_TABLE.values()})

OBDX_VID = 0x0483
OBDX_PID = 0x5740


class ObdxGt:
    def __init__(self, port: Optional[str] = None, baud: int = 115200,
                 timeout: float = 0.5):
        self.port_name = port
        self.baud = baud
        self.timeout = timeout
        self.ser = None
        self.supported: set[str] = set()
        self.device = "?"

    @staticmethod
    def autodetect() -> Optional[str]:
        if not list_ports:
            return None
        ports = list(list_ports.comports())
        for p in ports:
            if p.vid == OBDX_VID and p.pid == OBDX_PID:
                return p.device
        for p in ports:
            if "USB Serial" in (p.description or "") or p.vid:
                return p.device
        return ports[0].device if ports else None

    # -- lifecycle --------------------------------------------------------- #
    def open(self) -> None:
        if serial is None:
            raise RuntimeError("pyserial not installed (uv pip install pyserial)")
        if not self.port_name:
            self.port_name = self.autodetect()
        if not self.port_name:
            raise RuntimeError("No OBDX Pro GT serial port found")
        self.ser = serial.Serial(self.port_name, self.baud, timeout=self.timeout)
        time.sleep(0.2)
        self.command("ATZ", wait=0.9)
        for c in ("ATE0", "ATL0", "ATS0", "ATH0", "ATSP0"):
            self.command(c, wait=0.2)
        try:
            self.device = self.command("AT@1", wait=0.2) or "OBDX Pro GT"
        except Exception:
            self.device = "OBDX Pro GT"
        self._probe_supported()

    def close(self) -> None:
        if self.ser:
            try:
                self.ser.close()
            finally:
                self.ser = None

    # -- raw io ------------------------------------------------------------ #
    def command(self, cmd: str, wait: float = 0.0) -> str:
        try:
            self.ser.reset_input_buffer()
        except Exception:
            pass
        self.ser.write((cmd + "\r").encode())
        if wait:
            time.sleep(wait)
        return self._read_to_prompt()

    def request_raw(self, mode_pid: str) -> str:
        return self.command(mode_pid, wait=0.0)

    def _read_to_prompt(self, deadline_s: float = 1.2) -> str:
        buf = b""
        end = time.monotonic() + deadline_s
        while time.monotonic() < end:
            n = getattr(self.ser, "in_waiting", 0)
            if n:
                buf += self.ser.read(n)
                if b">" in buf:
                    break
            else:
                time.sleep(0.005)
        return (buf.decode(errors="ignore")
                .replace("\r", " ").replace("\n", " ").replace(">", " ").strip())

    # -- pid decode -------------------------------------------------------- #
    @staticmethod
    def _extract(resp: str, mode_pid: str) -> Optional[list]:
        s = "".join(ch for ch in resp.upper() if ch in "0123456789ABCDEF")
        rmode = "%02X" % (int(mode_pid[:2], 16) + 0x40)
        header = rmode + mode_pid[2:].upper()
        idx = s.find(header)
        if idx < 0:
            return None
        rest = s[idx + len(header):]
        rest = rest[:len(rest) - (len(rest) % 2)]
        return [int(rest[i:i + 2], 16) for i in range(0, len(rest), 2)]

    def _probe_supported(self) -> None:
        self.supported = set()
        for base in ("0100", "0120", "0140", "0160"):
            resp = self.request_raw(base)
            data = self._extract(resp, base)
            if not data or len(data) < 4:
                break
            start = int(base[2:], 16)
            mask = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3]
            for bit in range(32):
                if mask & (1 << (31 - bit)):
                    self.supported.add("%02X" % (start + 1 + bit))
            if not (mask & 1):  # bit for "next range supported"
                break

    def poll_once(self) -> dict:
        out: dict[str, float] = {}
        if not self.ser:
            return out
        for pid, (key, fn) in PID_TABLE.items():
            if self.supported and pid not in self.supported:
                continue
            data = self._extract(self.request_raw("01" + pid), "01" + pid)
            if not data:
                continue
            try:
                out[key] = float(fn(data))
            except Exception:
                pass
        if "voltage" not in out:
            m = re.search(r"([\d.]+)\s*V", self.command("ATRV", wait=0.05))
            if m:
                out["voltage"] = float(m.group(1))
        return out
