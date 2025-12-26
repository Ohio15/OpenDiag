# Get detailed info about VID_A5A5 device
$device = Get-PnpDevice | Where-Object { $_.InstanceId -like '*A5A5*' }
Write-Host "=== Unknown Device Details ===" -ForegroundColor Cyan
$device | Format-List *

Write-Host "`n=== Device Properties ===" -ForegroundColor Cyan
Get-PnpDeviceProperty -InstanceId $device.InstanceId | Format-Table KeyName, Data -AutoSize

Write-Host "`n=== All USB with unknown/generic names ===" -ForegroundColor Cyan
Get-PnpDevice -PresentOnly | Where-Object {
    $_.FriendlyName -like '*Unknown*' -or
    $_.FriendlyName -like '*Generic*' -or
    $_.Class -eq 'USBDevice'
} | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize
