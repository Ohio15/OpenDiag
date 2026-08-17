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
    Placeholder for the OBDX Pro GT live source. When gt.py exists, this wraps
    it: start() opens the transport and kicks a polling thread that fills a
    latest-sample slot; channels() reflects the DID/PID set being polled.

    Left intentionally unimplemented so the import graph is ready but no
    half-built hardware path ships. Raises a clear message if instantiated.
    """

    def __init__(self, *_, **__):
        raise NotImplementedError(
            "GtDataSource is a stub until gt.py (Phase 1) is built. "
            "Use LogReplaySource with a captured log for now."
        )
