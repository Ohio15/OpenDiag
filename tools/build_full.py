import json, os, sys, glob, re
HERE = r"C:\Users\ohio_\hpt_extract"
ROOT = r"D:\Projects\OpenOBD"
sys.path.insert(0, ROOT)
from openobd.calspec import Axis, Table, Scalar, Calibration
TUNE = os.path.join(HERE, "tune24_read"); STOCK = os.path.join(HERE, "stock_read")

# friendly segment names for the T-tag / S-tag prefixes in progress.log
SEGMAP = {"Airflow":"Engine",
  "OS":"OS","EngDiag":"Engine Diagnostics","Trans":"Transmission",
  "TransDiag":"Trans Diagnostics","FuelSys":"Fuel System","System":"System","Speedo":"Speedometer"}

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
def load_segmap():
    seg={}; lp=os.path.join(TUNE,"progress.log")
    if not os.path.exists(lp): return seg
    for ln in open(lp,encoding="utf-8"):
        m=re.search(r"\[(?:T\d+-x\d+|cur\d*|S(\w+?)-[^\]]*)\].*?OK id=(\d+)", ln)
        if m:
            if m.group(1): seg[m.group(2)]=m.group(1)
            else:
                mm=re.search(r"OK id=(\d+)", ln); 
                if mm: seg.setdefault(mm.group(1),"Airflow")
    return seg

tune,failt=load_dir(TUNE); stock,_=load_dir(STOCK); idseg=load_segmap()
print(f"parsed tune24={len(tune)} (failed {len(failt)}: {failt}) stock={len(stock)}")
cal=Calibration(metadata={"vehicle":"2010 Chevrolet Silverado 1500 5.3L","engine":"5.3L LMG V8 (E38 ECM / T43 TCM)",
  "trans":"6L80","vin":"3GCRKTE35AG150432","axle":"4.11","tires":'35"',
  "base_tune":"#24 - Claudes Edit 8.7.26","source":"VCM Editor Copy-with-Axis full sweep"})
n2=nstk=ns=0
for tid,t in sorted(tune.items(),key=lambda kv:int(kv[0])):
    cat=SEGMAP.get(idseg.get(tid,""), t["module"] or "Misc")
    x=t["x"]; grid=t["grid"]; nx=len(x)
    xa=Axis(label="",unit=t["xu"],values=x)
    note=f"[{t['module']}] id {tid}"
    if t["xcols"]: note+=" | cols: "+", ".join(t["xcols"])
    ya=None
    if len(grid)>1:
        if all(v is not None for v in t["ynum"]): ya=Axis(label="",unit=t["yu"],values=t["ynum"])
        else:
            ya=Axis(label="",unit="",values=[float(i) for i in range(len(grid))])
            note+=" | rows: "+", ".join([(t["ytext"][i] if t["ytext"][i] else str(i)) for i in range(len(grid))])
    if nx==1 and len(grid)==1 and len(grid[0])==1:
        s=stock.get(tid); stkv=(s["grid"][0][0] if s and s["grid"] and s["grid"][0] else None)
        cal.scalars.append(Scalar(name=t["name"],value=grid[0][0],unit=t["cu"],stock_value=stkv,param_id=int(tid),category=cat)); ns+=1; continue
    sv=None; s=stock.get(tid)
    if s and s["grid"] and len(s["grid"])==len(grid) and all(len(a)==len(b) for a,b in zip(s["grid"],grid)): sv=s["grid"]; nstk+=1
    cal.tables.append(Table(name=t["name"],x_axis=xa,y_axis=ya,values=grid,unit=t["cu"],stock_values=sv,param_id=int(tid),category=cat,note=note)); n2+=1
# ---- inline scalars from UIA hover sweep ----
SCSEG={"Engine":"Engine","OS":"OS","EngDiag":"Engine Diagnostics","Trans":"Transmission",
  "TransDiag":"Trans Diagnostics","FuelSys":"Fuel System","System":"System","Speedo":"Speedometer"}
scf=os.path.join(TUNE,"scalars.jsonl"); nsc=0; seen_sid=set()
if os.path.exists(scf):
    for ln in open(scf,encoding="utf-8"):
        ln=ln.strip()
        if not ln: continue
        try: o=json.loads(ln)
        except: continue
        sid=o.get("id")
        if sid in seen_sid: continue
        seen_sid.add(sid)
        cat=SCSEG.get(o.get("category",""), o.get("module","") or "Misc")
        cal.scalars.append(Scalar(name=o.get("name","") or f"id {sid}", value=float(o.get("value",0)),
            unit=o.get("unit","") or "", stock_value=None, param_id=int(sid), category=cat,
            note=o.get("desc","") or ""))
        nsc+=1
print(f"  inline scalars added: {nsc}")
# ---- end inline scalars ----
errs=cal.validate(); print(f"validation errors: {len(errs)}")
for e in errs[:20]: print("  ",e)
out=os.path.join(ROOT,"data","2010_silverado_full.cal.json"); cal.save(out)
print(f"wrote {out}"); print(f"  tables={n2} (stock baseline={nstk}) scalars={ns}")
cats={}
for t in cal.tables: cats[t.category]=cats.get(t.category,0)+1
for s in cal.scalars: cats[s.category]=cats.get(s.category,0)+1
print("  categories:",cats)

