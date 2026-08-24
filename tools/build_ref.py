"""Build a reference .cal.json from ONE VCM Editor sweep dir (raw/*.tsv +
manifest.tsv + optional scalars.jsonl). Used for reference calibrations that
carry no stock baseline of their own (e.g. the Compare Tunes tow references).

Usage:
  python tools/build_ref.py <read_dir> <out.cal.json> "<base_tune label>" ["<vehicle>"]
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, "tools"))
from openobd.calspec import Axis, Table, Scalar, Calibration
from hpt_parse import load_dir, load_scalar_jsonl

SEGMAP = {"Engine": "Engine", "OS": "OS", "EngDiag": "Engine Diagnostics",
          "Trans": "Transmission", "TransDiag": "Trans Diagnostics",
          "FuelSys": "Fuel System", "System": "System", "Speedo": "Speedometer"}


def load_segmap(read_dir):
    seg = {}
    lp = os.path.join(read_dir, "progress.log")
    if not os.path.exists(lp):
        return seg
    for ln in open(lp, encoding="utf-8"):
        m = re.search(r"\[S(\w+?)-[^\]]*\].*?OK id=(\d+)", ln)
        if m:
            seg[m.group(2)] = m.group(1)
    return seg


def main():
    read_dir, out_path, base_tune = sys.argv[1], sys.argv[2], sys.argv[3]
    vehicle = sys.argv[4] if len(sys.argv) > 4 else ""
    tabs, fails = load_dir(read_dir)
    idseg = load_segmap(read_dir)
    print(f"parsed {len(tabs)} tables (failed {len(fails)}: {fails})")
    cal = Calibration(metadata={
        "vehicle": vehicle, "base_tune": base_tune,
        "source": f"VCM Editor Copy-with-Axis sweep of {os.path.basename(read_dir)}",
        "role": "reference (no stock baseline of its own)",
    })
    nt = ns = 0
    for tid, t in sorted(tabs.items(), key=lambda kv: int(kv[0])):
        cat = SEGMAP.get(idseg.get(tid, ""), t["module"] or "Misc")
        x = t["x"]; grid = t["grid"]
        xa = Axis(label="", unit=t["xu"], values=x)
        note = f"[{t['module']}] id {tid}"
        if t["xcols"]:
            note += " | cols: " + ", ".join(t["xcols"])
        ya = None
        if len(grid) > 1:
            if all(v is not None for v in t["ynum"]):
                ya = Axis(label="", unit=t["yu"], values=t["ynum"])
            else:
                ya = Axis(label="", unit="",
                          values=[float(i) for i in range(len(grid))])
                note += " | rows: " + ", ".join(
                    [(t["ytext"][i] if t["ytext"][i] else str(i))
                     for i in range(len(grid))])
        if len(x) == 1 and len(grid) == 1 and len(grid[0]) == 1:
            cal.scalars.append(Scalar(
                name=t["name"], value=grid[0][0], unit=t["cu"],
                param_id=int(tid), category=cat))
            ns += 1
            continue
        cal.tables.append(Table(
            name=t["name"], x_axis=xa, y_axis=ya, values=grid, unit=t["cu"],
            param_id=int(tid), category=cat, note=note))
        nt += 1
    for sid, o in load_scalar_jsonl(
            os.path.join(read_dir, "scalars.jsonl")).items():
        cat = SEGMAP.get(o.get("category", ""), o.get("module", "") or "Misc")
        cal.scalars.append(Scalar(
            name=o.get("name", "") or f"id {sid}",
            value=float(o.get("value", 0)), unit=o.get("unit", "") or "",
            param_id=int(sid), category=cat, note=o.get("desc", "") or ""))
        ns += 1
    errs = cal.validate()
    print(f"validation errors: {len(errs)}")
    for e in errs[:20]:
        print("  ", e)
    if errs:
        return 1
    cal.save(out_path)
    print(f"wrote {out_path}: {nt} tables, {ns} scalars")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
