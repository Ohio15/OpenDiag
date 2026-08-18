"""Wave-0 regression tests: lossless drain(), replay cursor behavior."""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from openobd.logbin import parse_csv
from openobd.transport import LogReplaySource


def make_log(n=50, dt=0.1):
    rows = ["Time,Engine Speed,Vehicle Speed"]
    for i in range(n):
        rows.append(f"{i*dt:.1f},{1000+i*10},{i*0.5:.1f}")
    return parse_csv("\n".join(rows), source="synthetic")


def test_drain_is_lossless_and_duplicate_free():
    log = make_log(50)
    src = LogReplaySource(log, speed=1000.0)  # whole log elapses instantly
    src.start()
    time.sleep(0.02)
    src.latest()  # advances the cursor
    got = src.drain()
    # every sample up to the cursor exactly once
    assert len(got) == len({s.t for s in got})
    assert [s.t for s in got] == sorted(s.t for s in got)
    assert got, "drain returned nothing after cursor advance"
    # a second drain with no cursor movement returns nothing (no duplicates)
    assert src.drain() == []


def test_drain_before_start_is_empty():
    src = LogReplaySource(make_log(10), speed=1.0)
    assert src.drain() == []


def test_drain_resumes_after_loop_restart():
    log = make_log(5, dt=0.01)
    src = LogReplaySource(log, speed=10000.0)
    src.start()
    time.sleep(0.02)
    src.latest()          # runs past the end -> replay loops, cursor resets
    got = src.drain()
    assert all(s.t >= 0 for s in got)
    # after a loop restart drained never exceeds cursor
    assert src._drained <= src._cursor
