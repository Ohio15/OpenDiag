. "C:\Users\ohio_\hpt_extract\extract.ps1"
$global:OUT="C:\Users\ohio_\hpt_extract\tune24_read"
New-Item -ItemType Directory -Force -Path "$OUT\raw" | Out-Null
$log="$OUT\progress.log"
"MASTER-SWEEP START $(Get-Date -Format o)" | Add-Content -Encoding UTF8 $log
# finish current panel first (Airflow) in case partial
try { Extract-Panel-Rects "cur0" } catch { "cur0 ERR $($_.Exception.Message)" | Add-Content -Encoding UTF8 $log }
$tops=@(69,178,288,397,508,617,728,840,948)
foreach($tx in $tops){
  $seen=@{}
  for($x=18; $x -le 885; $x+=44){
    $pan=[H]::Panel([uint32]$EDPID); if($pan -ne [IntPtr]::Zero){ [H]::Restore($pan); [H]::MoveWindow($pan,2,6,904,602,$true); Start-Sleep -Milliseconds 240 }
    [H]::SetForegroundWindow($MAIN)|Out-Null; Start-Sleep -Milliseconds 110
    [H]::LClick($tx,160); Start-Sleep -Milliseconds 300
    [H]::LClick($x,184); Start-Sleep -Milliseconds 430
    $sig=Get-PanelSig
    if($sig.Length -gt 2 -and -not $seen.ContainsKey($sig)){ $seen[$sig]=1; try { Extract-Panel-Rects "T$tx-x$x" } catch { "T$tx-x$x ERR $($_.Exception.Message)" | Add-Content -Encoding UTF8 $log } }
  }
  "TOP $tx DONE $(Get-Date -Format o)" | Add-Content -Encoding UTF8 $log
}
$total=@(Get-ChildItem "$OUT\raw" -Filter *.tsv).Count
"MASTER-SWEEP DONE total=$total $(Get-Date -Format o)" | Add-Content -Encoding UTF8 $log
