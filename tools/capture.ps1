param([Parameter(Mandatory=$true)][string]$Cat,[string]$Unit="",[string]$XUnit="__none__",[string]$XLabel="",[string]$YLabel="")
$ErrorActionPreference="Stop"
Add-Type @"
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public class WcapT {
  private delegate bool EP(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] private static extern bool EnumWindows(EP cb, IntPtr l);
  [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr p, EP cb, IntPtr l);
  [DllImport("user32.dll")] private static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr h);
  private static Dictionary<IntPtr,string> _m;
  private static void H(IntPtr h){ if(_m.ContainsKey(h)) return; int n=GetWindowTextLength(h); if(n<=0) return; var s=new StringBuilder(n+2); GetWindowText(h,s,s.Capacity); var t=s.ToString(); if(System.Text.RegularExpressions.Regex.IsMatch(t,@"\[(ECM|TCM)\]")) _m[h]=t; }
  private static bool Ch(IntPtr h, IntPtr l){ H(h); return true; }
  private static bool Top(IntPtr h, IntPtr l){ H(h); EnumChildWindows(h, Ch, IntPtr.Zero); return true; }
  public static string[] Tables(){ _m=new Dictionary<IntPtr,string>(); EnumWindows(Top, IntPtr.Zero); var r=new List<string>(); foreach(var v in _m.Values){ if(!System.Text.RegularExpressions.Regex.IsMatch(v,@"Axis\s*$")) r.Add(v); } return r.ToArray(); }
}
"@ 2>$null
$t = @([WcapT]::Tables())
if($t.Count -eq 0){ "ERR: no table window open"; exit 1 }
if($t.Count -gt 1){ "ERR: multiple tables -> " + ($t -join " | "); exit 2 }
$m = [regex]::Match($t[0], "^\[(ECM|TCM)\]\s*(\d+)\s*-\s*(.+)$")
if(-not $m.Success){ "ERR: cannot parse: " + $t[0]; exit 1 }
$paramid=$m.Groups[2].Value; $name=$m.Groups[3].Value.Trim()
Remove-Item Env:\PYTHONHOME -ErrorAction SilentlyContinue
$ia=@("ingest.py","--name",$name,"--pid",$paramid,"--cat",$Cat)
if($Unit -ne ""){ $ia+=@("--unit",$Unit) }
if($XUnit -ne "__none__"){ $ia+=@("--xunit",$XUnit) }
if($XLabel -ne ""){ $ia+=@("--xlabel",$XLabel) }
if($YLabel -ne ""){ $ia+=@("--ylabel",$YLabel) }
Push-Location "D:\Projects\OpenOBD\tools"
Get-Clipboard -Raw | & C:\Python314\python.exe @ia
Pop-Location