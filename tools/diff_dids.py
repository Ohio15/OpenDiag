import sys
def load(p):
    d={}
    for l in open(p):
        l=l.rstrip("\n")
        if l.startswith("#") or not l.strip(): continue
        k,_,v=l.partition("\t"); d[k]=v
    return d
a=load(sys.argv[1]); b=load(sys.argv[2])
print(f"comparing {sys.argv[1]} -> {sys.argv[2]}")
ch=[k for k in a if k in b and a[k]!=b[k]]
print(f"{len(ch)} DIDs changed:")
for k in sorted(ch):
    def bytes_(h): return [int(h[i:i+2],16) for i in range(0,len(h),2)]
    print(f"  {k}: {a[k]} -> {b[k]}   ({bytes_(a[k])} -> {bytes_(b[k])})")
