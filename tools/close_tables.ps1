Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class WclsT {
  private delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] private static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr p, EP cb, IntPtr l);
  [DllImport("user32.dll")] private static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  private static Dictionary<IntPtr,string> _m;
  private static void H(IntPtr h){ if(_m.ContainsKey(h)) return; int n=GetWindowTextLength(h); if(n<=0) return; var s=new StringBuilder(n+2); GetWindowText(h,s,s.Capacity); var t=s.ToString(); if(System.Text.RegularExpressions.Regex.IsMatch(t,@"\[(ECM|TCM)\]")) _m[h]=t; }
  private static bool Ch(IntPtr h, IntPtr l){ H(h); return true; }
  private static bool Top(IntPtr h, IntPtr l){ H(h); EnumChildWindows(h, Ch, IntPtr.Zero); return true; }
  public static int CloseAll(){ _m=new Dictionary<IntPtr,string>(); EnumWindows(Top, IntPtr.Zero); int k=0; foreach(var h in _m.Keys){ PostMessage(h,0x0010,IntPtr.Zero,IntPtr.Zero); k++; } return k; }
}
"@ 2>$null
"sent WM_CLOSE to " + [WclsT]::CloseAll() + " table window(s)"