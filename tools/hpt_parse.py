"""Shared parser for VCM Editor Copy-with-Axis sweep dirs (raw/*.tsv + manifest.tsv)."""
import glob, json, os

def isnum(t):
    t=t.strip()
    if t=="" : return False
    try: float(t); return True
    except: return False
def num(t): return float(t.strip())

def parse_tsv(text):
    lines=[ln.rstrip("\r") for ln in text.replace("\r\n","\n").split("\n")]
    while lines and lines[-1].strip()=="" : lines.pop()
    if len(lines)<2: return None
    y_unit=""
    if "\t" not in lines[-1] and not isnum(lines[-1]) and lines[-1].strip():
        y_unit=lines[-1].strip(); lines=lines[:-1]
    if len(lines)<2: return None
    htok=lines[0].split("\t")
    cell_unit=htok[0].strip() if htok and not isnum(htok[0]) else ""
    x_unit=htok[-1].strip() if len(htok)>1 and not isnum(htok[-1]) else ""
    x=[num(t) for t in htok if isnum(t)]
    xcols=[]
    if not x:
        # named-column header: htok[0]=row-axis label, htok[1:]=column labels
        xcols=[t.strip() for t in htok[1:]] if len(htok)>1 else []
        if not xcols: return None
        x=[float(i) for i in range(len(xcols))]; cell_unit=""; x_unit=""
    nx=len(x)
    ynum=[]; ytext=[]; grid=[]
    for ln in lines[1:]:
        cells=ln.split("\t")
        if not any(c.strip() for c in cells): continue
        first=cells[0].strip()
        body=[num(c) for c in cells[1:] if isnum(c)]
        if len(body)>=nx:
            row=body[:nx]
            if isnum(first): ynum.append(num(first)); ytext.append(None)
            else: ynum.append(None); ytext.append(first)
            grid.append(row)
        else:
            alln=([num(first)] if isnum(first) else [])+body
            if len(alln)==nx: grid.append(alln); ynum.append(None); ytext.append(None)
            elif alln: grid.append(alln+[alln[-1]]*(nx-len(alln))); ynum.append(None); ytext.append(None)
    if not grid: return None
    return dict(cu=cell_unit,xu=x_unit,yu=y_unit,x=x,xcols=xcols,ynum=ynum,ytext=ytext,grid=grid)

def load_manifest(d):
    meta={}; mp=os.path.join(d,"manifest.tsv")
    if os.path.exists(mp):
        for ln in open(mp,encoding="utf-8"):
            p=ln.rstrip("\n").split("\t")
            if len(p)>=3: meta[p[0]]={"module":p[1],"name":p[2]}
    return meta
def load_dir(d):
    meta=load_manifest(d); out={}; fails=[]
    for f in glob.glob(os.path.join(d,"raw","*.tsv")):
        tid=os.path.splitext(os.path.basename(f))[0]
        try: r=parse_tsv(open(f,encoding="utf-8").read())
        except Exception: r=None
        if not r: fails.append(tid); continue
        m=meta.get(tid,{}); r["name"]=(m.get("name") or f"id {tid}"); r["module"]=(m.get("module") or "")
        out[tid]=r
    return out,fails

_CORRECTIONS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                 "..", "data", "uia_capture_corrections.json")

def _apply_corrections(records, corrections_path=None):
    """Repair known UIA-harvester capture defects (documented in
    data/uia_capture_corrections.json). Values only — join keys untouched."""
    path = corrections_path or _CORRECTIONS_PATH
    if not os.path.exists(path):
        return 0
    spec = json.load(open(path, encoding="utf-8"))
    applied = 0
    for c in spec.get("corrections", []):
        if c.get("type") != "swap_values":
            continue
        by_name = {o.get("name"): o for o in records.values()
                   if o.get("category") == c["category"] and o.get("desc") == c["desc"]}
        mn, mx = by_name.get(c["min_name"]), by_name.get(c["max_name"])
        if mn is None or mx is None:
            continue
        try:
            vmin, vmax = float(mn["value"]), float(mx["value"])
        except (TypeError, ValueError):
            continue
        # swap only when the defect is actually present (a fixed harvester or
        # already-corrected capture must not be re-swapped into the defect)
        if vmin > vmax:
            mn["value"], mx["value"] = mx["value"], mn["value"]
            applied += 1
    return applied

def load_scalar_jsonl(path, corrections_path=None):
    out = {}
    if not os.path.exists(path):
        return out
    for ln in open(path, encoding="utf-8"):
        ln = ln.strip()
        if not ln:
            continue
        try:
            o = json.loads(ln)
        except Exception:
            continue
        sid = o.get("id")
        if sid is None:
            # click-free UIA harvester records carry no HPT ParameterID;
            # key them by name + section so they survive loading and can be
            # joined by name downstream.
            sid = f"name:{o.get('name','')}|{o.get('desc','')}"
        if sid not in out:
            out[sid] = o
    n = _apply_corrections(out, corrections_path)
    if n:
        print(f"  applied {n} UIA capture correction(s) from {os.path.basename(corrections_path or _CORRECTIONS_PATH)}")
    return out
