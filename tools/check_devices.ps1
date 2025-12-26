Get-PnpDevice -PresentOnly | Where-Object {
    $_.FriendlyName -like '*Android*' -or
    $_.FriendlyName -like '*ADB*' -or
    $_.FriendlyName -like '*Autel*' -or
    $_.FriendlyName -like '*Mobile*' -or
    $_.Class -eq 'AndroidUsbDeviceClass'
} | Select-Object FriendlyName, Status, Class, InstanceId | Format-Table -AutoSize
