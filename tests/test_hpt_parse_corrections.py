import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from hpt_parse import load_scalar_jsonl  # noqa: E402


def _write_capture(tmp_path, rows):
    p = tmp_path / "scalars.jsonl"
    p.write_text("\n".join(json.dumps(r) for r in rows), encoding="utf-8")
    return str(p)


def _write_corrections(tmp_path):
    p = tmp_path / "corrections.json"
    p.write_text(json.dumps({"corrections": [{
        "type": "swap_values",
        "category": "Engine/Fuel/Oxygen Sensors",
        "desc": "Min MAP vs. BARO",
        "min_name": "LTM Min Limit",
        "max_name": "LTM Max Limit",
    }]}), encoding="utf-8")
    return str(p)


def _row(name, value):
    return {"id": None, "name": name, "value": value, "unit": "",
            "category": "Engine/Fuel/Oxygen Sensors", "desc": "Min MAP vs. BARO"}


def test_swap_applied_when_defect_present(tmp_path):
    cap = _write_capture(tmp_path, [_row("LTM Min Limit", 1.3), _row("LTM Max Limit", 0.7)])
    out = load_scalar_jsonl(cap, corrections_path=_write_corrections(tmp_path))
    vals = {o["name"]: o["value"] for o in out.values()}
    assert vals["LTM Min Limit"] == 0.7
    assert vals["LTM Max Limit"] == 1.3


def test_no_swap_when_capture_is_healthy(tmp_path):
    cap = _write_capture(tmp_path, [_row("LTM Min Limit", 0.7), _row("LTM Max Limit", 1.3)])
    out = load_scalar_jsonl(cap, corrections_path=_write_corrections(tmp_path))
    vals = {o["name"]: o["value"] for o in out.values()}
    assert vals["LTM Min Limit"] == 0.7
    assert vals["LTM Max Limit"] == 1.3


def test_no_swap_when_pair_incomplete(tmp_path):
    cap = _write_capture(tmp_path, [_row("LTM Min Limit", 1.3)])
    out = load_scalar_jsonl(cap, corrections_path=_write_corrections(tmp_path))
    vals = {o["name"]: o["value"] for o in out.values()}
    assert vals["LTM Min Limit"] == 1.3


def test_missing_corrections_file_is_noop(tmp_path):
    cap = _write_capture(tmp_path, [_row("LTM Min Limit", 1.3), _row("LTM Max Limit", 0.7)])
    out = load_scalar_jsonl(cap, corrections_path=str(tmp_path / "absent.json"))
    vals = {o["name"]: o["value"] for o in out.values()}
    assert vals["LTM Min Limit"] == 1.3  # untouched: no corrections available


def test_real_corrections_file_fixes_shipped_defect(tmp_path):
    # against the repo's actual data/uia_capture_corrections.json
    cap = _write_capture(tmp_path, [_row("LTM Min Limit", 1.25), _row("LTM Max Limit", 0.75)])
    out = load_scalar_jsonl(cap)
    vals = {o["name"]: o["value"] for o in out.values()}
    assert vals["LTM Min Limit"] == 0.75
    assert vals["LTM Max Limit"] == 1.25
