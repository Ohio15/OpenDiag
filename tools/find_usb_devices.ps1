# Find all USB devices with VID/PID
Write-Host "=== USB Devices ===" -ForegroundColor Cyan
Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'USB\VID*' } |
    Select-Object Status, Class, FriendlyName, InstanceId |
    Format-Table -AutoSize

Write-Host "`n=== COM/Serial Ports ===" -ForegroundColor Cyan
Get-PnpDevice -Class Ports -PresentOnly |
    Select-Object Status, FriendlyName, InstanceId |
    Format-Table -AutoSize

Write-Host "`n=== Bluetooth Devices ===" -ForegroundColor Cyan
Get-PnpDevice -Class Bluetooth -PresentOnly -ErrorAction SilentlyContinue |
    Select-Object Status, FriendlyName, InstanceId |
    Format-Table -AutoSize

Write-Host "`n=== Android/ADB Devices ===" -ForegroundColor Cyan
Get-PnpDevice -PresentOnly | Where-Object {
    $_.FriendlyName -like '*Android*' -or
    $_.FriendlyName -like '*ADB*' -or
    $_.Class -eq 'AndroidUsbDeviceClass' -or
    $_.FriendlyName -like '*Autel*'
} | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize

Write-Host "`n=== USB Composite Devices (potential OBD2/Tablet) ===" -ForegroundColor Cyan
Get-PnpDevice -PresentOnly | Where-Object {
    $_.FriendlyName -like '*Composite*' -or
    $_.FriendlyName -like '*OBD*' -or
    $_.FriendlyName -like '*ELM*' -or
    $_.FriendlyName -like '*OBDII*'
} | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize
