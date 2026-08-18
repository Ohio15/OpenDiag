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


def test_pause_freezes_position():
    src = LogReplaySource(make_log(50), speed=1000.0)
    src.start()
    time.sleep(0.01)
    src.pause()
    p1 = src.position()
    time.sleep(0.02)
    assert src.position() == p1, "position advanced while paused"
    src.resume()
    time.sleep(0.01)
    assert src.position() >= p1, "position went backwards after resume"


def test_seek_moves_cursor_and_limits_drain():
    log = make_log(50, dt=0.1)   # duration 4.9s
    src = LogReplaySource(log, speed=1.0)
    src.start()
    src.pause()
    src.seek(2.0)
    assert abs(src.position() - 2.0) < 1e-9
    s = src.latest()
    assert s is not None and abs(s.t - 2.0) < 0.11
    # the recorder must not receive the skipped-over samples
    assert src.drain() == []


def test_set_speed_composes_without_jump():
    src = LogReplaySource(make_log(50), speed=1.0)
    src.start()
    src.pause()
    src.seek(1.0)
    src.set_speed(8.0)
    assert abs(src.position() - 1.0) < 1e-9, "speed change moved the position"
    assert src.duration() == 4.9


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
