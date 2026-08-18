Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
. "C:\Users\ohio_\hpt_extract\extract.ps1"
$global:OUT="C:\Users\ohio_\hpt_extract\tune24_read"
$log="$OUT\scalars.log"; $jf="$OUT\scalars.jsonl"
"SCALAR-SWEEP START $(Get-Date -Format o)" | Add-Content -Encoding UTF8 $log
$vcm=Get-Process 'VCM Editor' -ErrorAction SilentlyContinue | Select-Object -First 1
$MAINH=[IntPtr]$vcm.MainWindowHandle
$AE=[System.Windows.Automation.AutomationElement]
$TS=[System.Windows.Automation.TreeScope]::Descendants
$CTe=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit)
$CTh=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Hyperlink)
$CTt=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text)
function GetVal($e){ try{ return $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ return "" } }
$seen=@{}
if(Test-Path $jf){ foreach($ln in Get-Content $jf){ try{ $o=$ln|ConvertFrom-Json; if($o.id){$seen["$($o.id)"]=1} }catch{} } }
function ReadPanel($cat){
  $root=$AE::FromHandle($MAINH)
  $edits=@($root.FindAll($TS,$CTe))
  if($edits.Count -eq 0){ return 0 }
  $sb = $edits | Where-Object { (GetVal $_) -match '^\s*\[' } | Select-Object -First 1
  if(-not $sb){ return 0 }
  $links=@()
  foreach($h in @($root.FindAll($TS,$CTh))){ $r=$h.Current.BoundingRectangle; $links += [pscustomobject]@{x=$r.X;y=$r.Y;t=$h.Current.Name} }
  foreach($h in @($root.FindAll($TS,$CTt))){ $r=$h.Current.BoundingRectangle; $t=$h.Current.Name; if($t.Length -le 5){ $links += [pscustomobject]@{x=$r.X;y=$r.Y;t=$t} } }
  $scalars=@($edits | Where-Object { $v=GetVal $_; $v -match '^-?\d' -and $v -notmatch '^\s*\[' })
  $added=0
  foreach($s in $scalars){
    $r=$s.Current.BoundingRectangle
    if($r.Y -lt 190){ continue }
    $cx=[int]($r.X+$r.Width/2); $cy=[int]($r.Y+$r.Height/2)
    [H]::SetCursorPos($cx,$cy) 1>$null; [H]::mouse_event(1,0,0,0,[IntPtr]::Zero); Start-Sleep -Milliseconds 170
    $desc=GetVal $sb
    $m=[regex]::Match($desc,'^\s*\[(?<mod>\w+)\]\s+(?<id>\d+)\s*-\s*(?<name>[^:]+?)(?::\s*(?<d>.*))?$')
    if(-not $m.Success){ continue }
    $id=$m.Groups['id'].Value
    if($seen.ContainsKey($id)){ continue }
    $val=GetVal $s
    if($val -notmatch '^-?\d'){ continue }
    # unit: nearest link/text to the right on same row
    $u=""
    $cand=$links | Where-Object { [Math]::Abs($_.y-$r.Y) -lt 12 -and $_.x -ge ($r.X+$r.Width-4) -and $_.x -lt ($r.X+$r.Width+70) } | Sort-Object x | Select-Object -First 1
    if($cand){ $u=$cand.t }
    $seen[$id]=1; $added++
    $rec=[ordered]@{id=[int]$id;module=$m.Groups['mod'].Value;name=$m.Groups['name'].Value.Trim();value=[double]$val;unit=$u;category=$cat;desc=$m.Groups['d'].Value.Trim()}
    ($rec|ConvertTo-Json -Compress) | Add-Content -Encoding UTF8 $jf
  }
  return $added
}
$segs=@(@{n='Engine';x=197},@{n='OS';x=125},@{n='EngDiag';x=294},@{n='Trans';x=386},@{n='TransDiag';x=475},@{n='FuelSys';x=570},@{n='System';x=657},@{n='Speedo';x=743})
$tops=@(69,178,288,397,508,617,728,840)
foreach($sg in $segs){
  [H]::SetForegroundWindow($MAINH)|Out-Null; Start-Sleep -Milliseconds 200
  [H]::LClick($sg.x,93); Start-Sleep -Milliseconds 800
  "== SEG $($sg.n) $(Get-Date -Format o)" | Add-Content -Encoding UTF8 $log
  $seenSig=@{}
  $a=ReadPanel $sg.n; if($a -gt 0){ "  [$($sg.n) def] +$a" | Add-Content -Encoding UTF8 $log }
  foreach($tx in $tops){
    for($x=18;$x -le 885;$x+=44){
      $pan=[H]::Panel([uint32]$EDPID); if($pan -ne [IntPtr]::Zero){ [H]::Restore($pan); [H]::MoveWindow($pan,2,6,904,602,$true); Start-Sleep -Milliseconds 200 }
      [H]::SetForegroundWindow($MAINH)|Out-Null; Start-Sleep -Milliseconds 90
      [H]::LClick($sg.x,93); Start-Sleep -Milliseconds 140
      [H]::LClick($tx,160); Start-Sleep -Milliseconds 260
      [H]::LClick($x,184); Start-Sleep -Milliseconds 360
      $pan=[H]::Panel([uint32]$EDPID); if($pan -ne [IntPtr]::Zero){ [H]::Max($pan); Start-Sleep -Milliseconds 260 }
      $sig=Get-PanelSig
      if($sig.Length -gt 2 -and -not $seenSig.ContainsKey($sig)){ $seenSig[$sig]=1; try{ $a=ReadPanel $sg.n; if($a -gt 0){ "  [$($sg.n) t$tx-x$x] +$a (total $($seen.Count))" | Add-Content -Encoding UTF8 $log } }catch{ "  [$($sg.n)] ERR $($_.Exception.Message)" | Add-Content -Encoding UTF8 $log } }
    }
  }
  "SEG $($sg.n) DONE $(Get-Date -Format o) (scalars so far $($seen.Count))" | Add-Content -Encoding UTF8 $log
}
"SCALAR-SWEEP DONE total=$($seen.Count) $(Get-Date -Format o)" | Add-Content -Encoding UTF8 $log
