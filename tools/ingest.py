import sys, json, argparse, os
p = argparse.ArgumentParser()
p.add_argument("--name", required=True)
p.add_argument("--pid", type=int, default=None)
p.add_argument("--desc", default=""); p.add_argument("--unit", default=""); p.add_argument("--cat", default="")
p.add_argument("--xlabel", default=""); p.add_argument("--ylabel", default="")
p.add_argument("--xunit", default=None)
p.add_argument("--scalar", action="store_true")
p.add_argument("--value", type=float, default=None); p.add_argument("--stock", type=float, default=None)
a = p.parse_args()
HERE = os.path.dirname(os.path.abspath(__file__))
def isnum(s):
    s = s.strip().replace(",", "")
    if s == "":
        return False
    try:
        float(s); return True
    except ValueError:
        return False
def num(s):
    try:
        return float(s.strip().replace(",", ""))
    except ValueError:
        return 0.0
if a.scalar:
    rec = {"kind":"scalar","name":a.name,"value":a.value,"unit":a.unit,
           "stock_value":a.stock,"param_id":a.pid,"category":a.cat,"note":a.desc}
else:
    raw = sys.stdin.read()
    lines = [l.rstrip("\r") for l in raw.split("\n") if l.strip() != ""]
    xvals, xunit, yvals, yunit, values, vunit = [], "", [], "", [], ""
    if lines:
        body = lines[1:]
        if body and len(body[-1].split("\t")) == 1 and not isnum(body[-1]):
            yunit = body[-1].strip(); body = body[:-1]
        htok = lines[0].split("\t")
        if htok and htok[0].strip() == "":
            htok = htok[1:]
        elif htok and not isnum(htok[0]):
            vunit = htok[0].strip(); htok = htok[1:]
        if htok and not isnum(htok[-1]):
            xunit = htok[-1].strip(); htok = htok[:-1]
        xvals = [num(t) for t in htok if isnum(t)]
        for row in body:
            cells = row.split("\t")
            if cells and isnum(cells[0]):
                yvals.append(num(cells[0])); rowcells = cells[1:]
            elif cells and cells[0].strip() != "":
                rowcells = cells[1:]
            else:
                rowcells = cells
            values.append([num(c) for c in rowcells if isnum(c)])
    unit = a.unit or vunit
    xu = a.xunit if a.xunit is not None else xunit
    rec = {"name":a.name,"param_id":a.pid,"description":a.desc,"unit":unit,"category":a.cat,
           "x_label":a.xlabel,"x_unit":xu,"x_values":xvals,
           "y_label":a.ylabel,"y_unit":yunit,"y_values":yvals,"values":values}
with open(os.path.join(HERE, "harvest.jsonl"), "a", encoding="utf-8") as f:
    f.write(json.dumps(rec) + "\n")
shape = f"{len(rec.get('values',[]))}x{len(rec['values'][0]) if rec.get('values') else 0}"
print(f"appended: {a.name} | {shape} | unit={rec.get('unit','')} x_unit={rec.get('x_unit','')} y_unit={rec.get('y_unit','')} | xn={len(rec.get('x_values',[]))} yn={len(rec.get('y_values',[]))}")