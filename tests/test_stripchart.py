"""Pure-function tests for the Chart vs. Time strip chart (no Qt needed for
lane grouping / ranging / decimation) plus series_after cursor reads."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from openobd.stripchart import (  # noqa: E402
    LANE_PRESETS, build_lanes, expand_range, window_points,
)


# --- lane grouping --------------------------------------------------------- #
def test_build_lanes_uses_presets_for_present_channels():
    names = ["rpm", "vehicle_speed", "coolant_temp", "throttle_pos"]
    lanes = build_lanes(names)
    assert ["rpm", "vehicle_speed"] in lanes
    assert ["throttle_pos"] in lanes          # preset lane, minus absent members
    assert ["coolant_temp"] in lanes


def test_build_lanes_appends_unknown_channels_in_chunks():
    extras = [f"probe_{i}" for i in range(6)]
    lanes = build_lanes(["rpm"] + extras)
    assert lanes[0] == ["rpm"]
    tail = [lane for lane in lanes if lane and lane[0].startswith("probe_")]
    assert [len(lane) for lane in tail] == [4, 2]
    assert sorted(n for lane in tail for n in lane) == sorted(extras)


def test_build_lanes_empty():
    assert build_lanes([]) == []


def test_lane_presets_have_no_duplicates():
    flat = [n for lane in LANE_PRESETS for n in lane]
    assert len(flat) == len(set(flat))


# --- ranging --------------------------------------------------------------- #
def test_expand_range_never_shrinks():
    lo, hi = expand_range(0.0, 100.0, 20.0, 80.0)
    assert (lo, hi) == (0.0, 100.0)


def test_expand_range_grows_to_cover():
    lo, hi = expand_range(0.0, 100.0, -12.0, 140.0)
    assert lo <= -12.0
    assert hi >= 140.0


# --- decimation ------------------------------------------------------------ #
def test_window_points_passthrough_when_small():
    ts = [0.0, 1.0, 2.0, 3.0]
    vs = [10.0, 20.0, 30.0, 40.0]
    out_t, out_v = window_points(ts, vs, 0.5, 2.5, 100)
    # includes one point either side of the window so the trace spans the frame
    assert out_t == [0.0, 1.0, 2.0, 3.0]
    assert out_v == [10.0, 20.0, 30.0, 40.0]


def test_window_points_decimation_keeps_spikes():
    n = 10_000
    ts = [float(i) for i in range(n)]
    vs = [0.0] * n
    vs[5000] = 99.0    # a single-sample spike must survive decimation
    vs[7000] = -50.0
    out_t, out_v = window_points(ts, vs, 0.0, float(n), 200)
    assert len(out_t) <= 200
    assert 99.0 in out_v
    assert -50.0 in out_v


def test_window_points_outside_window_is_near_empty():
    ts = [0.0, 1.0, 2.0]
    vs = [1.0, 2.0, 3.0]
    out_t, _ = window_points(ts, vs, 100.0, 200.0, 50)
    assert len(out_t) <= 1   # at most the edge point
