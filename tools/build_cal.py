import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
from openobd.seed_2010_silverado import build_with_labels
from openobd.calspec import Axis, Table, Scalar

cal = build_with_labels()
seen = {t.name for t in cal.tables}
seen_s = {s.name for s in cal.scalars}
hp = os.path.join(HERE, "harvest.jsonl")
n_t = n_s = 0
if os.path.exists(hp):
    for line in open(hp, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        r = json.loads(line)
        if r.get("kind") == "scalar":
            if r["name"] in seen_s:
                continue
            seen_s.add(r["name"])
            cal.scalars.append(Scalar(name=r["name"], value=r.get("value", 0),
                unit=r.get("unit",""), stock_value=r.get("stock_value"),
                param_id=r.get("param_id"), category=r.get("category",""),
                note=r.get("note","")))
            n_s += 1
            continue
        if r["name"] in seen:
            continue
        seen.add(r["name"])
        xa = Axis(label=r.get("x_label",""), unit=r.get("x_unit",""), values=r["x_values"])
        ya = None
        if r.get("y_values"):
            ya = Axis(label=r.get("y_label",""), unit=r.get("y_unit",""), values=r["y_values"])
        cal.tables.append(Table(name=r["name"], x_axis=xa, y_axis=ya,
            values=r["values"], unit=r.get("unit",""), param_id=r.get("param_id"),
            category=r.get("category",""), note=r.get("description","")))
        n_t += 1
errs = cal.validate()
if errs:
    print("VALIDATION ERRORS:", *errs[:10], sep="\n  ")
out = os.path.join(ROOT, "data", "2010_silverado_full.cal.json")
cal.save(out)
print(f"wrote {out}")
print(f"  harvested +{n_t} tables +{n_s} scalars ; total {len(cal.tables)} tables / {len(cal.scalars)} scalars")