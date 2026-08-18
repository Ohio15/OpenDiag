"""
logbin — log ingestion + the "log over table" overlay engine.

This is the core that makes the viewer feel like HP Tuners: load a log, and for
any table, drop every sample into the cell whose axes it falls in, then show a
histogram of where the engine actually operated and the mean measured value in
each cell.

It also computes the regime stats codified from the 8.8.26 baseline analysis
(idle/cruise/PE trims, knock-retard events, fuel-pressure sag) — the same logic
`wot_analyzer` in the GT spec is meant to expose. GUI-free and unit-tested.

Supported inputs
----------------
1. VCM Scanner CSV export:
       [Log Information] ... / [Channel Information] (id,name,unit rows) /
       [Channel Data] (samples)
2. Plain CSV with a single header row of channel names.

Channel-name mapping is fuzzy (case/space/paren-insensitive substring) so both
HP Tuners' verbose names and our own short names resolve to canonical keys.
"""
from __future__ import annotations

import csv
import io
import math
from dataclasses import dataclass, field
from typing import Iterable, Optional

from .calspec import Table


# --------------------------------------------------------------------------- #
# Canonical channel vocabulary. Each canonical key lists substrings that, if
# any appears in a log's channel name (normalized), maps that column to the key.
# Order matters: more specific keys should be tested before generic ones.
# --------------------------------------------------------------------------- #
CANONICAL = {
    "time":        ["time", "offset", "timestamp"],
    "rpm":         ["engine speed", "rpm", "enginerpm"],
    "vss":         ["vehicle speed", "vss", "vehiclespeed"],
    "map":         ["manifold absolute", "map"],
    "maf":         ["mass air flow", "maf", "airflow"],
    "load":        ["engine load", "calculated load", "absload", "load"],
    "tps":         ["throttle position", "tps"],
    "app":         ["accelerator pedal", "pedal position", "app"],
    "cmd_throttle":["commanded throttle", "throttle command"],
    "stft":        ["short term fuel", "stft", "shorttermft"],
    "ltft":        ["long term fuel", "ltft", "longtermft"],
    "eq_ratio":    ["equivalence", "eq ratio", "commanded eq"],
    "afr":         ["air fuel", "afr", "lambda"],
    "o2":          ["o2 sensor", "oxygen"],
    "spark":       ["spark advance", "ignition timing", "timing advance", "spark"],
    "knock_retard":["knock retard", "kr", "retard"],
    "iat":         ["intake air temp", "iat"],
    "ect":         ["coolant temp", "engine coolant", "ect"],
    "tft":         ["trans fluid temp", "transmission fluid", "tft"],
    "gear":        ["current gear", "gear"],
    "tcc_slip":    ["tcc slip", "converter slip", "slip"],
    "fuel_press":  ["fuel rail", "fuel pressure"],
    "fuel_level":  ["fuel level"],
    "ethanol":     ["ethanol", "flex fuel"],
    "voltage":     ["module voltage", "battery voltage", "system voltage", "voltage"],
    "baro":        ["barometric", "baro"],
    "ambient":     ["ambient air", "outside air"],
}


def _norm(s: str) -> str:
    return "".join(ch for ch in s.lower() if ch.isalnum() or ch == " ").strip()


def map_channel(name: str) -> Optional[str]:
    """Map a raw log channel name to a canonical key, or None."""
    n = _norm(name)
    for key, needles in CANONICAL.items():
        for needle in needles:
            if needle in n:
                return key
    return None


# --------------------------------------------------------------------------- #
# Parsed log
# --------------------------------------------------------------------------- #
@dataclass
class LogChannel:
    raw_name: str
    canonical: Optional[str]
    unit: str
    values: list[Optional[float]] = field(default_factory=list)


@dataclass
class Log:
    channels: list[LogChannel]
    n_samples: int
    source: str = ""

    def by_canonical(self, key: str) -> Optional[LogChannel]:
        for ch in self.channels:
            if ch.canonical == key:
                return ch
        return None

    def has(self, key: str) -> bool:
        return self.by_canonical(key) is not None

    def series(self, key: str) -> list[Optional[float]]:
        ch = self.by_canonical(key)
        return ch.values if ch else []

    def canonical_keys(self) -> list[str]:
        return [c.canonical for c in self.channels if c.canonical]


def time_axis(log: Log, fallback_dt: float = 0.1) -> list[float]:
    """Zero-based seconds for every sample: the log's time channel normalized
    to start at 0 (gaps hold the last value), or fallback_dt spacing when no
    time channel is present. Shared by the replay source and the chart view."""
    tser = log.series("time")
    if tser and any(v is not None for v in tser):
        base = next(v for v in tser if v is not None)
        out: list[float] = []
        last = 0.0
        for v in tser:
            if v is not None:
                last = v - base
            out.append(last)
        return out
    return [i * fallback_dt for i in range(log.n_samples)]


def _to_float(s: str) -> Optional[float]:
    s = s.strip()
    if s == "" or s.upper() in ("N/A", "NA", "---", "NAN"):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def parse_csv(text: str, source: str = "") -> Log:
    """
    Parse either a VCM Scanner sectioned CSV or a plain header+rows CSV.
    Returns a Log with canonical channel mapping applied.
    """
    # Detect the VCM Scanner sectioned format by its bracket headers.
    if "[Channel Data]" in text or "[Channel Information]" in text:
        return _parse_vcm_scanner(text, source)
    return _parse_plain(text, source)


def _parse_plain(text: str, source: str) -> Log:
    reader = csv.reader(io.StringIO(text))
    rows = [r for r in reader if r]
    if not rows:
        return Log(channels=[], n_samples=0, source=source)
    header = rows[0]
    channels = [
        LogChannel(raw_name=h, canonical=map_channel(h), unit="")
        for h in header
    ]
    for row in rows[1:]:
        for i, ch in enumerate(channels):
            ch.values.append(_to_float(row[i]) if i < len(row) else None)
    n = len(rows) - 1
    return Log(channels=channels, n_samples=n, source=source)


def _parse_vcm_scanner(text: str, source: str) -> Log:
    reader = csv.reader(io.StringIO(text))
    rows = [r for r in reader]
    # Find section markers.
    idx = {}
    for i, r in enumerate(rows):
        if r and r[0].strip().startswith("[") and r[0].strip().endswith("]"):
            idx[r[0].strip()] = i

    ci = idx.get("[Channel Information]")
    cd = idx.get("[Channel Data]")
    if ci is None or cd is None:
        # Fall back to plain parse of everything after the last bracket header.
        return _parse_plain(text, source)

    # Channel Information block = rows between [Channel Information] and
    # [Channel Data]. HP Tuners emits an id row, a name row, and a unit row.
    info = [r for r in rows[ci + 1:cd] if r]
    # Heuristic: the row containing recognizable channel names is the name row;
    # the last non-empty info row before data is typically units.
    name_row = None
    unit_row = None
    if len(info) >= 2:
        # pick the row with the most alphabetic content as the name row
        def alpha_score(r):
            return sum(any(c.isalpha() for c in cell) for cell in r)
        info_sorted = sorted(info, key=alpha_score, reverse=True)
        name_row = info_sorted[0]
        # unit row: the info row (other than name) with short tokens
        for r in info:
            if r is not name_row:
                unit_row = r
                break
    elif len(info) == 1:
        name_row = info[0]

    if not name_row:
        return _parse_plain(text, source)

    channels = []
    for i, nm in enumerate(name_row):
        unit = unit_row[i] if unit_row and i < len(unit_row) else ""
        channels.append(LogChannel(raw_name=nm, canonical=map_channel(nm), unit=unit))

    data_rows = [r for r in rows[cd + 1:] if r]
    for row in data_rows:
        for i, ch in enumerate(channels):
            ch.values.append(_to_float(row[i]) if i < len(row) else None)

    return Log(channels=channels, n_samples=len(data_rows), source=source)


# --------------------------------------------------------------------------- #
# The overlay: bin log samples into a table's cells
# --------------------------------------------------------------------------- #
@dataclass
class CellBin:
    count: int = 0
    _sum: float = 0.0

    def add(self, v: float) -> None:
        self.count += 1
        self._sum += v

    @property
    def mean(self) -> Optional[float]:
        return (self._sum / self.count) if self.count else None


@dataclass
class Overlay:
    """Result of binning a log against a table."""
    n_rows: int
    n_cols: int
    bins: list[list[CellBin]]
    total_binned: int
    value_channel: Optional[str]      # canonical key averaged into cells

    def count_grid(self) -> list[list[int]]:
        return [[b.count for b in row] for row in self.bins]

    def mean_grid(self) -> list[list[Optional[float]]]:
        return [[b.mean for b in row] for row in self.bins]

    def hottest_cell(self) -> Optional[tuple[int, int, int]]:
        best = None
        for r, row in enumerate(self.bins):
            for c, b in enumerate(row):
                if best is None or b.count > best[2]:
                    best = (r, c, b.count)
        return best


def bin_log_to_table(
    log: Log,
    table: Table,
    x_channel: str,
    y_channel: Optional[str] = None,
    value_channel: Optional[str] = None,
) -> Overlay:
    """
    Bin every sample into table cells using the sample's x_channel (and
    y_channel for 2-D tables) against the table's axes. If value_channel is
    given, accumulate its mean per cell; otherwise the overlay is a pure
    operation-count histogram.
    """
    xs = log.series(x_channel)
    ys = log.series(y_channel) if y_channel else None
    vs = log.series(value_channel) if value_channel else None

    n_rows = table.n_rows
    n_cols = table.n_cols
    bins = [[CellBin() for _ in range(n_cols)] for _ in range(n_rows)]

    total = 0
    n = log.n_samples
    for i in range(n):
        x = xs[i] if i < len(xs) else None
        if x is None:
            continue
        c = table.x_axis.index_of(x)
        if c is None:
            continue
        if table.y_axis:
            if ys is None:
                continue
            y = ys[i] if i < len(ys) else None
            if y is None:
                continue
            r = table.y_axis.index_of(y)
            if r is None:
                continue
        else:
            r = 0
        # accumulate
        val = None
        if vs is not None and i < len(vs):
            val = vs[i]
        bins[r][c].add(val if val is not None else 0.0)
        if val is None and value_channel is not None:
            # don't count a sample toward a value-mean if the value is missing
            bins[r][c].count -= 1
            bins[r][c]._sum -= 0.0
        else:
            total += 1

    return Overlay(
        n_rows=n_rows, n_cols=n_cols, bins=bins,
        total_binned=total, value_channel=value_channel,
    )


# --------------------------------------------------------------------------- #
# Regime analysis (the 8.8.26 baseline logic → wot_analyzer)
# --------------------------------------------------------------------------- #
@dataclass
class RegimeStats:
    name: str
    n: int
    stft_mean: Optional[float] = None
    ltft_mean: Optional[float] = None
    combined_trim_mean: Optional[float] = None


@dataclass
class LogReport:
    n_samples: int
    channels_present: list[str]
    duration_s: Optional[float]
    regimes: list[RegimeStats]
    knock_events: list[dict]
    max_knock_retard: Optional[float]
    fuel_pressure_min: Optional[float]
    fuel_pressure_sag: bool
    notes: list[str] = field(default_factory=list)


def _mean(vals: Iterable[Optional[float]]) -> Optional[float]:
    xs = [v for v in vals if v is not None]
    return sum(xs) / len(xs) if xs else None


def analyze_log(log: Log) -> LogReport:
    notes: list[str] = []
    rpm = log.series("rpm")
    app = log.series("app") or log.series("tps")
    load = log.series("load")
    stft = log.series("stft")
    ltft = log.series("ltft")
    kr = log.series("knock_retard")
    fp = log.series("fuel_press")
    spark = log.series("spark")
    t = log.series("time")

    n = log.n_samples
    duration = None
    if t:
        tv = [x for x in t if x is not None]
        if len(tv) >= 2:
            duration = max(tv) - min(tv)

    # Regime classification per sample.
    def regime_of(i: int) -> Optional[str]:
        r = rpm[i] if i < len(rpm) else None
        a = app[i] if app and i < len(app) else None
        if r is None:
            return None
        if r < 900 and (a is None or a < 5):
            return "idle"
        if a is not None and a >= 75:
            return "PE (WOT/high load)"
        if a is not None and a < 25:
            return "cruise"
        return "part-throttle"

    buckets: dict[str, list[int]] = {}
    for i in range(n):
        rg = regime_of(i)
        if rg:
            buckets.setdefault(rg, []).append(i)

    regimes: list[RegimeStats] = []
    for name, idxs in buckets.items():
        s = _mean(stft[i] for i in idxs if i < len(stft)) if stft else None
        l = _mean(ltft[i] for i in idxs if i < len(ltft)) if ltft else None
        comb = None
        if s is not None or l is not None:
            comb = (s or 0.0) + (l or 0.0)
        regimes.append(RegimeStats(name, len(idxs), s, l, comb))
    regimes.sort(key=lambda r: -r.n)

    # Knock events. Prefer a real KR channel; else detect a timing-collapse
    # signature (sharp spark drop) when KR isn't logged.
    knock_events: list[dict] = []
    max_kr = None
    if kr:
        krv = [v for v in kr if v is not None]
        max_kr = max(krv) if krv else None
        for i, v in enumerate(kr):
            if v is not None and v >= 1.0:
                knock_events.append({
                    "sample": i,
                    "time_s": t[i] if t and i < len(t) else None,
                    "retard_deg": v,
                    "rpm": rpm[i] if i < len(rpm) else None,
                })
    elif spark:
        notes.append("No knock-retard channel logged — add it before trusting "
                     "spark decisions. Timing-collapse heuristic used instead.")
        for i in range(1, len(spark)):
            a, b = spark[i - 1], spark[i]
            if a is not None and b is not None and (a - b) >= 4.0:
                knock_events.append({
                    "sample": i,
                    "time_s": t[i] if t and i < len(t) else None,
                    "spark_drop_deg": round(a - b, 1),
                    "rpm": rpm[i] if i < len(rpm) else None,
                    "inferred": True,
                })

    fp_min = None
    fp_sag = False
    if fp:
        fpv = [v for v in fp if v is not None]
        if fpv:
            fp_min = min(fpv)
            base = _mean(fpv)
            if base and fp_min < 0.85 * base:
                fp_sag = True
                notes.append(f"Fuel pressure sagged to {fp_min:.0f} "
                             f"(~{100*fp_min/base:.0f}% of mean) — watch pump/PE.")

    # Rich/lean systemic note.
    if regimes:
        cruise = next((r for r in regimes if r.name == "cruise"), None)
        if cruise and cruise.combined_trim_mean is not None:
            if cruise.combined_trim_mean <= -8:
                notes.append(f"Cruise trims average {cruise.combined_trim_mean:+.1f}%"
                             " (rich) — possible systemic MAF over-read.")
            elif cruise.combined_trim_mean >= 8:
                notes.append(f"Cruise trims average {cruise.combined_trim_mean:+.1f}%"
                             " (lean) — MAF under-read / small leak.")

    if not any(regime_of(i) == "PE (WOT/high load)" for i in range(n)):
        notes.append("No WOT/PE samples in this log — can't validate shift points "
                     "or PE fueling. Capture a full-throttle pull with KR logged.")

    return LogReport(
        n_samples=n,
        channels_present=sorted(set(log.canonical_keys())),
        duration_s=duration,
        regimes=regimes,
        knock_events=knock_events,
        max_knock_retard=max_kr,
        fuel_pressure_min=fp_min,
        fuel_pressure_sag=fp_sag,
        notes=notes,
    )


# --------------------------------------------------------------------------- #
# Observed shift-point detection — the meaningful "log view" for the WOT shift
# setpoint tables (validates #24: confirm 1-2/2-3 land near 5,400-5,500 RPM).
# --------------------------------------------------------------------------- #
@dataclass
class ShiftEvent:
    from_gear: Optional[int]
    to_gear: Optional[int]
    time_s: Optional[float]
    rpm: Optional[float]        # engine speed just before the shift
    vss: Optional[float]        # vehicle speed at the shift
    wot: bool                   # pedal/throttle high at the time
    inferred: bool = False      # detected from RPM drop, no gear channel


def detect_shift_points(log: Log, wot_threshold: float = 70.0) -> list[ShiftEvent]:
    """
    Return upshift events. If a 'gear' channel is present, detect increments
    directly (most reliable). Otherwise infer upshifts from a sharp RPM drop
    while VSS keeps climbing (auto upshift signature).
    """
    rpm = log.series("rpm")
    vss = log.series("vss")
    gear = log.series("gear")
    app = log.series("app") or log.series("tps")
    t = log.series("time")
    n = log.n_samples
    events: list[ShiftEvent] = []

    def is_wot(i: int) -> bool:
        a = app[i] if app and i < len(app) else None
        return a is not None and a >= wot_threshold

    if gear and any(v is not None for v in gear):
        last = None
        for i in range(n):
            g = gear[i] if i < len(gear) else None
            if g is None:
                continue
            g = round(g)
            if last is not None and g > last:
                j = max(0, i - 1)
                events.append(ShiftEvent(
                    from_gear=last, to_gear=g,
                    time_s=t[j] if t and j < len(t) else None,
                    rpm=rpm[j] if j < len(rpm) else None,
                    vss=vss[j] if vss and j < len(vss) else None,
                    wot=is_wot(j),
                ))
            last = g
        return events

    # Inferred path: RPM drops >= 400 while VSS non-decreasing.
    for i in range(2, n):
        r0 = rpm[i - 1] if i - 1 < len(rpm) else None
        r1 = rpm[i] if i < len(rpm) else None
        v0 = vss[i - 1] if vss and i - 1 < len(vss) else None
        v1 = vss[i] if vss and i < len(vss) else None
        if None in (r0, r1):
            continue
        if (r0 - r1) >= 400 and (v0 is None or v1 is None or v1 >= v0 - 1):
            events.append(ShiftEvent(
                from_gear=None, to_gear=None,
                time_s=t[i] if t and i < len(t) else None,
                rpm=r0, vss=v0,
                wot=is_wot(i - 1), inferred=True,
            ))
    return events
