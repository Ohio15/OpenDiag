import ctypes, time, re
from ctypes import wintypes
u=ctypes.windll.user32
try: u.SetProcessDPIAware()
except: pass
EP=ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
main=[]
def cb(h,l):
    n=u.GetWindowTextLengthW(h)
    if n>0:
        b=ctypes.create_unicode_buffer(n+1); u.GetWindowTextW(h,b,n+1)
        if b.value.startswith("VCM Editor"): main.append((h,b.value))
    return True
u.EnumWindows(EP(cb),0)
print("VCM main:", main[0][1][:50] if main else "NOT FOUND")
if main:
    h=main[0][0]
    u.ShowWindow(h,3); u.SetForegroundWindow(h); u.BringWindowToTop(h); time.sleep(0.4)
fg=u.GetForegroundWindow()
b=ctypes.create_unicode_buffer(120); u.GetWindowTextW(fg,b,120)
print("foreground now:", b.value[:50])
u.SetCursorPos(280,195); time.sleep(0.2)
pt=wintypes.POINT(); u.GetCursorPos(ctypes.byref(pt))
print("cursor set to (280,195) -> actual:", pt.x, pt.y)
# double click
for _ in range(2):
    u.mouse_event(0x02,0,0,0,0); u.mouse_event(0x04,0,0,0,0); time.sleep(0.05)
time.sleep(0.8)
res={}
def cb2(h,l):
    n=u.GetWindowTextLengthW(h)
    if n>0:
        bb=ctypes.create_unicode_buffer(n+1); u.GetWindowTextW(h,bb,n+1)
        if re.search(r"\[(ECM|TCM)\]", bb.value): res[h]=bb.value
    return True
cp=EP(cb2)
def top(h,l):
    cb2(h,l); u.EnumChildWindows(h,cp,0); return True
u.EnumWindows(EP(top),0)
print("table windows after dblclick:", list(res.values()))