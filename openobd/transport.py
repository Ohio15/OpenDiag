"""
transport — the seam the live dashboard reads from.

The dashboard never talks to hardware directly. It reads canonical channel
samples from a DataSource. Today we ship a LogReplaySource (plays a loaded log
back in time order) so the dashboard is fully usable before the GT is wired.
When gt.py lands, a GtDataSource implementing the same three methods drops in
with zero dashboard changes — the same seam `gt.py` implements for the CLI
(open/close/command/request_raw) surfaces canonical samples here.
"""
from __future__ import annotations

import time
import threading
from dataclasses import dataclass
from typing import Optional

from .logbin import Log


@dataclass
class Sample:
    """A single timestamped snapshot: canonical_key -> value."""
    t: float
    values: dict[str, float]


class DataSource:
    """Abstract live/replay source of canonical channel samples."""

    def channels(self) -> list[str]:
        raise NotImplementedError

    def latest(self) -> Optional[Sample]:
        """Non-blocking: the most recent sample, or None if not started."""
        raise NotImplementedError

    def start(self) -> None:
        pass

    def stop(self) -> None:
        pass


class LogReplaySource(DataSource):
    """
    Replays a parsed Log as if it were live. Advances an internal cursor by
    wall-clock time scaled by `speed`. If the log has no time channel, samples
    are spaced at `fallback_dt` seconds.
    """

    def __init__(self, log: Log, speed: float = 1.0, fallback_dt: float = 0.1):
        self.log = log
        self.speed = speed
        self.fallback_dt = fallback_dt
        self._keys = [c.canonical for c in log.channels if c.canonical]
        self._t0_wall: Optional[float] = None
        self._times = self._build_times()
        self._cursor = 0

    def _build_times(self) -> list[float]:
        tser = self.log.series("time")
        if tser and any(v is not None for v in tser):
            base = next(v for v in tser if v is not None)
            out = []
            last = 0.0
            for v in tser:
                if v is not None:
                    last = v - base
                out.append(last)
            return out
        return [i * self.fallback_dt for i in range(self.log.n_samples)]

    def channels(self) -> list[str]:
        return list(self._keys)

    def start(self) -> None:
        self._t0_wall = time.monotonic()
        self._cursor = 0

    def _sample_at(self, i: int) -> Sample:
        vals: dict[str, float] = {}
        for ch in self.log.channels:
            if ch.canonical and i < len(ch.values):
                v = ch.values[i]
                if v is not None:
                    vals[ch.canonical] = v
        return Sample(t=self._times[i] if i < len(self._times) else 0.0, values=vals)

    def latest(self) -> Optional[Sample]:
        if self._t0_wall is None or self.log.n_samples == 0:
            return None
        elapsed = (time.monotonic() - self._t0_wall) * self.speed
        # advance cursor to the last sample whose log-time <= elapsed
        i = self._cursor
        while i + 1 < len(self._times) and self._times[i + 1] <= elapsed:
            i += 1
        # loop the replay
        if i >= len(self._times) - 1 and elapsed > self._times[-1]:
            self.start()
            i = 0
        self._cursor = i
        return self._sample_at(i)


class GtDataSource(DataSource):
    """
    Live source backed by the OBDX Pro GT (openobd.gt.ObdxGt), an ELM327 v2.1
    interface over USB serial. start() opens the transport and spawns a daemon
    polling thread that fills a latest-sample slot; latest() is non-blocking so
    the dashboard's 100ms timer never stalls on serial IO. channels() reflects
    the canonical keys the PID table can surface (gauges pre-build), and after
    the first poll narrows to what the ECU actually answered.
    """

    def __init__(self, port=None, poll_interval=0.05):
        from . import gt as _gt  # local import: pyserial only needed on this path
        self._gt = _gt.ObdxGt(port=port)
        self._keys = list(_gt.CANONICAL_KEYS)
        self._interval = poll_interval
        self._latest = None
        self._thread = None
        self._stop = threading.Event()
        self._t0 = None
        self.device = "OBDX Pro GT"
        self.port_name = port

    def channels(self):
        return list(self._keys)

    def latest(self):
        return self._latest

    def start(self):
        self._gt.open()
        self.device = getattr(self._gt, "device", "OBDX Pro GT")
        self.port_name = getattr(self._gt, "port_name", None)
        self._t0 = time.monotonic()
        vals = self._gt.poll_once()
        if vals:
            self._keys = sorted(vals.keys())
            self._latest = Sample(t=0.0, values=vals)
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, name="gt-poll", daemon=True)
        self._thread.start()

    def _run(self):
        while not self._stop.is_set():
            try:
                vals = self._gt.poll_once()
                if vals:
                    self._latest = Sample(t=time.monotonic() - self._t0, values=vals)
            except Exception:
                pass
            self._stop.wait(self._interval)

    def stop(self):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=1.5)
            self._thread = None
        self._gt.close()
