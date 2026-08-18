Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class WmaxT {
  private delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] private static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr p, EP cb, IntPtr l);
  [DllImport("user32.dll")] private static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h, int c);
  private static Dictionary<IntPtr,string> _m;
  private static void H(IntPtr h){ if(_m.ContainsKey(h)) return; int n=GetWindowTextLength(h); if(n<=0) return; var s=new StringBuilder(n+2); GetWindowText(h,s,s.Capacity); var t=s.ToString(); if(System.Text.RegularExpressions.Regex.IsMatch(t,@"\[(ECM|TCM)\]") && !System.Text.RegularExpressions.Regex.IsMatch(t,@"Axis\s*$")) _m[h]=t; }
  private static bool Ch(IntPtr h, IntPtr l){ H(h); return true; }
  private static bool Top(IntPtr h, IntPtr l){ H(h); EnumChildWindows(h, Ch, IntPtr.Zero); return true; }
  public static string MaxTable(){ _m=new Dictionary<IntPtr,string>(); EnumWindows(Top, IntPtr.Zero); if(_m.Count==0) return "NONE"; if(_m.Count>1){ var l=new List<string>(_m.Values); return "MULTI:"+string.Join(" | ",l); } foreach(var h in _m.Keys){ ShowWindow(h,3); } var e=_m.Values.GetEnumerator(); e.MoveNext(); return e.Current; }
}
"@ 2>$null
[WmaxT]::MaxTable()