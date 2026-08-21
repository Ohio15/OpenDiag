"""Pure-model tests for the shared Live Data selection+grouping model:
persistence round-trip, graceful degradation on garbage/unknown channels,
and the grouping operations behind the lane editor. No Qt widgets needed."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from openobd.chanlayout import ChannelLayout  # noqa: E402
from openobd.stripchart import build_lanes  # noqa: E402

CHARTABLE = ["rpm", "vehicle_speed", "maf", "intake_map", "throttle_pos",
             "coolant_temp", "knock_retard", "spark_adv", "inj_duty",
             "o2_b1s1"]
SESSION = CHARTABLE + ["gear_text", "dtc_status"]   # two tile-only channels


# --- defaults --------------------------------------------------------------- #
def test_default_layout_is_default_and_follows_presets():
    lo = ChannelLayout()
    assert lo.is_default()
    assert lo.chart_lanes(CHARTABLE) == build_lanes(CHARTABLE)
    assert lo.tile_names(SESSION) == sorted(SESSION)


def test_tile_names_include_nonchartable_channels():
    lo = ChannelLayout()
    assert "gear_text" in lo.tile_names(SESSION)
    assert "dtc_status" in lo.tile_names(SESSION)


# --- selection: ONE model drives BOTH views --------------------------------- #
def test_hide_removes_from_tiles_and_lanes():
    lo = ChannelLayout()
    lo.hide("rpm")
    assert "rpm" not in lo.tile_names(SESSION)
    assert all("rpm" not in lane for lane in lo.chart_lanes(CHARTABLE))
    assert not lo.is_default()


def test_show_restores_both_views():
    lo = ChannelLayout(hidden=["rpm"])
    lo.show("rpm")
    assert "rpm" in lo.tile_names(SESSION)
    assert any("rpm" in lane for lane in lo.chart_lanes(CHARTABLE))
    assert lo.is_default()


def test_hide_applies_inside_custom_lanes_too():
    lo = ChannelLayout(lanes=[["rpm", "vehicle_speed"]])
    lo.hide("vehicle_speed")
    lanes = lo.chart_lanes(CHARTABLE)
    assert ["rpm"] in lanes
    assert all("vehicle_speed" not in lane for lane in lanes)


# --- grouping: Ron's example groups must be expressible --------------------- #
def test_rons_example_groups_resolve_exactly():
    groups = [["rpm", "vehicle_speed", "inj_duty"],
              ["maf", "intake_map", "o2_b1s1"],
              ["knock_retard", "spark_adv", "throttle_pos"]]
    lo = ChannelLayout(lanes=[list(g) for g in groups])
    lanes = lo.chart_lanes(CHARTABLE)
    assert lanes[:3] == groups
    # the one chartable channel not assigned falls back to preset grouping
    assert lanes[3:] == build_lanes(["coolant_temp"])


def test_absent_channels_skip_but_stay_saved():
    lo = ChannelLayout(lanes=[["rpm", "trans_temp_future"], ["maf"]])
    lanes = lo.chart_lanes(["rpm", "maf"])
    assert lanes[:2] == [["rpm"], ["maf"]]
    # the unknown name survives the round-trip for a session that has it
    back = ChannelLayout.from_json(lo.to_json())
    assert ["rpm", "trans_temp_future"] in back.lanes
    assert back.chart_lanes(["rpm", "maf", "trans_temp_future"])[0] == \
        ["rpm", "trans_temp_future"]


def test_new_session_channels_append_never_drop():
    lo = ChannelLayout(lanes=[["rpm"]])
    lanes = lo.chart_lanes(["rpm", "brand_new_channel"])
    flat = [n for lane in lanes for n in lane]
    assert "brand_new_channel" in flat


# --- grouping ops (the lane editor) ----------------------------------------- #
def test_move_to_lane_materializes_current_grouping_first():
    lo = ChannelLayout()
    lo.move_to_lane("maf", 0, CHARTABLE)
    # first customization edits what the user was looking at (the defaults)
    assert lo.lanes is not None
    assert "maf" in lo.lanes[0]
    # moved out of its old lane, present exactly once
    flat = [n for lane in lo.lanes for n in lane]
    assert flat.count("maf") == 1


def test_move_to_new_lane_and_prune_empties():
    lo = ChannelLayout(lanes=[["rpm"], ["maf", "intake_map"]])
    lo.move_to_lane("rpm", None, CHARTABLE)      # new lane at the bottom
    assert lo.lanes == [["maf", "intake_map"], ["rpm"]]  # old lane pruned
    lo.move_to_lane("intake_map", 1, CHARTABLE)  # join rpm's lane
    assert lo.lanes == [["maf"], ["rpm", "intake_map"]]


def test_move_out_of_range_index_makes_new_lane():
    lo = ChannelLayout(lanes=[["rpm"]])
    lo.move_to_lane("maf", 99, CHARTABLE)
    assert lo.lanes == [["rpm"], ["maf"]]


# --- persistence ------------------------------------------------------------ #
def test_json_round_trip():
    lo = ChannelLayout(hidden=["gear_text", "coolant_temp"],
                       lanes=[["rpm", "vehicle_speed"], ["maf"]])
    back = ChannelLayout.from_json(lo.to_json())
    assert back.hidden == lo.hidden
    assert back.lanes == lo.lanes
    assert back.chart_lanes(CHARTABLE) == lo.chart_lanes(CHARTABLE)


def test_from_json_garbage_degrades_to_defaults():
    for garbage in (None, "", "not json", "[]", "42", '{"lanes": "x"}',
                    '{"hidden": {"a": 1}, "lanes": [[1, 2], "x"]}',
                    b"\x00\xff"):
        lo = ChannelLayout.from_json(garbage)
        assert lo.is_default() or lo.lanes is None, garbage
        # and it must resolve without raising
        lo.chart_lanes(CHARTABLE)
        lo.tile_names(SESSION)


def test_from_json_dedupes_names_across_lanes():
    lo = ChannelLayout.from_json(
        '{"v": 1, "hidden": [], "lanes": [["rpm", "rpm"], ["rpm", "maf"]]}')
    flat = [n for lane in lo.lanes for n in lane]
    assert flat.count("rpm") == 1


def test_reset_returns_to_defaults():
    lo = ChannelLayout(hidden=["rpm"], lanes=[["maf"]])
    lo.reset()
    assert lo.is_default()
    assert lo.chart_lanes(CHARTABLE) == build_lanes(CHARTABLE)
