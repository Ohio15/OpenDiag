"""
Seed the 2010 Silverado calibration (.cal.json) from the #24 change sheet.

Every value here is transcribed from `24-claudes-edit-change-sheet.md`, which
was itself verified in VCM Editor via Compare -> Comparison Log against the
Oct-2024 stock read. Stock and new values are both carried so the editor shows
a live diff and can revert-to-stock per cell.

Run:  python -m openobd.seed_2010_silverado  ->  data/2010_silverado_24.cal.json
"""
from __future__ import annotations

import os

from .calspec import Axis, Calibration, Scalar, Table

# Order of gear-change events used for every WOT shift table.
# Upshifts first (1-2..5-6), then downshifts (2-1..6-5).
SHIFT_EVENTS = ["1-2", "2-3", "3-4", "4-5", "5-6", "2-1", "3-2", "4-3", "5-4", "6-5"]

# For each pattern: {event: (stock_mph, new_mph)}.  From change sheet §2.
_SHIFT = {
    "Normal": {
        "1-2": (33, 35), "2-3": (65, 57), "3-4": (105, 89),
        "4-5": (140, 116), "5-6": (190, 158),
        "2-1": (30, 31), "3-2": (61, 53), "4-3": (101, 85),
        "5-4": (133, 110), "6-5": (188, 156),
    },
    "Pattern A": {
        "1-2": (37, 31), "2-3": (63, 52), "3-4": (105, 87),
        "4-5": (140, 116), "5-6": (190, 158),
        "2-1": (35, 29), "3-2": (61, 51), "4-3": (101, 84),
        "5-4": (133, 110), "6-5": (188, 156),
    },
    "Pattern B": {
        "1-2": (37, 31), "2-3": (65, 54), "3-4": (105, 87),
        "4-5": (140, 116), "5-6": (190, 158),
        "2-1": (35, 29), "3-2": (61, 51), "4-3": (101, 84),
        "5-4": (133, 110), "6-5": (188, 156),
    },
    "Hot Trans": {
        "1-2": (37, 31), "2-3": (63, 52), "3-4": (98, 81),
        "4-5": (143, 119), "5-6": (238, 198),
        "2-1": (29, 24), "3-2": (55, 46), "4-3": (92, 76),
        "5-4": (121, 100), "6-5": (226, 188),
    },
    "TUTD": {
        "1-2": (26, 22), "2-3": (63, 52), "3-4": (100, 83),
        "4-5": (111, 92), "5-6": (188, 156),
        "2-1": (21, 17), "3-2": (61, 51), "4-3": (96, 80),
        "5-4": (91, 76), "6-5": (91, 76),
    },
    "Hot Engine": {
        "1-2": (32, 27), "2-3": (63, 52), "3-4": (98, 81),
        "4-5": (126, 105), "5-6": (190, 158),
        "2-1": (30, 25), "3-2": (55, 46), "4-3": (92, 76),
        "5-4": (118, 98), "6-5": (170, 141),
    },
}

# HPT ParameterID breadcrumbs (GT spec).  base / 5th / 6th segment IDs; we
# store the base id on the combined table for XDF cross-reference later.
_SHIFT_PARAM = {
    "Normal": 15010,
    "Pattern A": 15323,
    "Pattern B": 15326,
    "Hot Trans": 15012,
    "TUTD": 15015,
    "Hot Engine": 15017,
}

_SHIFT_NOTE = {
    "Normal": "Daily upshift schedule; new values ~0.83x stock so 1-2/2-3 land "
              "~5,350-5,500 RPM on 4.11/35s instead of past the limiter.",
    "Pattern A": "Performance/tip-in pattern.",
    "Pattern B": "Alternate performance pattern.",
    "Hot Trans": "High trans-temp protection schedule.",
    "TUTD": "Tap-up/tap-down (paddle/manual) schedule.",
    "Hot Engine": "High-ECT protection schedule.",
}


def build() -> Calibration:
    cal = Calibration(
        metadata={
            "vehicle": "2010 Chevrolet Silverado 1500 LTZ 5.3L (LC9 flex)",
            "vin": "3GCRKTE35AG150432",
            "controllers": "E38 ECM (OS 12636005) + T43 TCM (OS 24254909, 6L80)",
            "hardware": "4.11 gears, 35\" tires (2,742 mm loaded circ), AFM disabled, E10 fuel",
            "base_tune": "DO NOT CHANGE - 2010 Silverado Stock - 10.13.24.hpt",
            "derived_from": "#24 - Claudes Edit 8.7.26 - 4.11 Gears, DOD Delete, Shift Points",
            "units_note": "Shift speeds in mph; tire circumference in mm; ratios unitless.",
            "safety": "This is truck-mcp's own calibration format. It is NOT a "
                      "flashable .hpt. Writing a real .hpt stays behind the gated "
                      "Phase 3/4 flash path.",
        }
    )

    # -- Drivetrain scalars (change sheet §1) ------------------------------ #
    cal.scalars.extend([
        Scalar("Final Drive Ratio", 4.11, "", 3.08, param_id=None,
               category="Speedometer/Calibration",
               note="Axle ratio truth-up: 3.08 stock cal -> 4.11 installed."),
        Scalar("Final Drive Ratio - VSS Error", 4.11, "", 3.08,
               category="Speedometer/Calibration"),
        Scalar("Final Drive Ratio - Trans", 4.11, "", 3.08, param_id=5004,
               category="Transmission"),
        Scalar("Driven Tire Circumference", 2742, "mm", 2475, param_id=None,
               category="Speedometer/Calibration",
               note="35\" tire w/ GM ~2% loaded-radius factor."),
        Scalar("Non-Driven Tire Circumference", 2742, "mm", 2475, param_id=9056,
               category="Speedometer/Calibration"),
        Scalar("DoD (AFM) Enable", 0, "bool", 0, param_id=246,
               category="Engine/AFM",
               note="Already Disabled in Oct-2024 stock read; left as-is."),
    ])

    # -- WOT shift tables (change sheet §2) -------------------------------- #
    axis = Axis(label="Gear change", unit="", values=list(range(len(SHIFT_EVENTS))))
    # Use the event labels as the display axis; store index values numerically.
    for pattern, cells in _SHIFT.items():
        new_row = [float(cells[e][1]) for e in SHIFT_EVENTS]
        stk_row = [float(cells[e][0]) for e in SHIFT_EVENTS]
        cal.tables.append(Table(
            name=f"WOT Shift Speed — {pattern}",
            x_axis=Axis(label="Gear change", unit="",
                        values=[float(i) for i in range(len(SHIFT_EVENTS))]),
            values=[new_row],
            stock_values=[stk_row],
            unit="mph",
            param_id=_SHIFT_PARAM[pattern],
            category="Transmission/Shift Scheduling/Full Throttle Shift Speed",
            note=_SHIFT_NOTE[pattern],
        ))

    return cal


# The event labels aren't numeric axis breakpoints — attach them as metadata so
# the GUI can render "1-2","2-3",... as column headers.
def build_with_labels() -> Calibration:
    cal = build()
    cal.metadata["shift_events"] = SHIFT_EVENTS
    return cal


def main() -> None:
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(here, "data")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "2010_silverado_24.cal.json")
    cal = build_with_labels()
    errs = cal.validate()
    if errs:
        raise SystemExit("Seed validation failed:\n  " + "\n  ".join(errs))
    cal.save(out)
    print(f"wrote {out}")
    print(f"  {len(cal.scalars)} scalars, {len(cal.tables)} tables")


if __name__ == "__main__":
    main()
