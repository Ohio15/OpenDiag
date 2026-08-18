. "C:\Users\ohio_\hpt_extract\extract.ps1"
$global:OUT="C:\Users\ohio_\hpt_extract\tune24_read"
New-Item -ItemType Directory -Force -Path "$OUT\raw" | Out-Null
$log="$OUT\progress.log"
"SEGMENT-SWEEP START $(Get-Date -Format o)" | Add-Content -Encoding UTF8 $log
# top-level segment buttons at y=93 (from UIA). skip Favorites(47) & Engine(197 done)
$segs=@(@{n='OS';x=125},@{n='EngDiag';x=294},@{n='Trans';x=386},@{n='TransDiag';x=475},@{n='FuelSys';x=570},@{n='System';x=657},@{n='Speedo';x=743})
$tops=@(69,178,288,397,508,617,728,840)
foreach($s in $segs){
  [H]::SetForegroundWindow($MAIN)|Out-Null; Start-Sleep -Milliseconds 200
  [H]::LClick($s.x,93); Start-Sleep -Milliseconds 900
  "== SEG $($s.n) (x=$($s.x)) $(Get-Date -Format o)" | Add-Content -Encoding UTF8 $log
  $seen=@{}
  # extract the segment's default panel first
  try { Extract-Panel-Rects "S$($s.n)-def" } catch { "S$($s.n)-def ERR $($_.Exception.Message)" | Add-Content -Encoding UTF8 $log }
  foreach($tx in $tops){
    for($x=18; $x -le 885; $x+=44){
      $pan=[H]::Panel([uint32]$EDPID); if($pan -ne [IntPtr]::Zero){ [H]::Restore($pan); [H]::MoveWindow($pan,2,6,904,602,$true); Start-Sleep -Milliseconds 220 }
      [H]::SetForegroundWindow($MAIN)|Out-Null; Start-Sleep -Milliseconds 100
      [H]::LClick($s.x,93); Start-Sleep -Milliseconds 150
      [H]::LClick($tx,160); Start-Sleep -Milliseconds 280
      [H]::LClick($x,184); Start-Sleep -Milliseconds 400
      $sig=Get-PanelSig
      if($sig.Length -gt 2 -and -not $seen.ContainsKey($sig)){ $seen[$sig]=1; try { Extract-Panel-Rects "S$($s.n)-t$tx-x$x" } catch { "S$($s.n) ERR $($_.Exception.Message)" | Add-Content -Encoding UTF8 $log } }
    }
  }
  "SEG $($s.n) DONE $(Get-Date -Format o)" | Add-Content -Encoding UTF8 $log
}
$total=@(Get-ChildItem "$OUT\raw" -Filter *.tsv).Count
"SEGMENT-SWEEP DONE total=$total $(Get-Date -Format o)" | Add-Content -Encoding UTF8 $log
