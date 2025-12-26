# PowerShell script to communicate with USB device using Windows API
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class WinUSB
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern SafeFileHandle CreateFile(
        string lpFileName,
        uint dwDesiredAccess,
        uint dwShareMode,
        IntPtr lpSecurityAttributes,
        uint dwCreationDisposition,
        uint dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_Initialize(
        SafeFileHandle DeviceHandle,
        out IntPtr InterfaceHandle);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_Free(IntPtr InterfaceHandle);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_WritePipe(
        IntPtr InterfaceHandle,
        byte PipeID,
        byte[] Buffer,
        uint BufferLength,
        out uint LengthTransferred,
        IntPtr Overlapped);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_ReadPipe(
        IntPtr InterfaceHandle,
        byte PipeID,
        byte[] Buffer,
        uint BufferLength,
        out uint LengthTransferred,
        IntPtr Overlapped);

    public const uint GENERIC_READ = 0x80000000;
    public const uint GENERIC_WRITE = 0x40000000;
    public const uint FILE_SHARE_READ = 0x00000001;
    public const uint FILE_SHARE_WRITE = 0x00000002;
    public const uint OPEN_EXISTING = 3;
    public const uint FILE_FLAG_OVERLAPPED = 0x40000000;
}
"@

# Find the device path for VID_A5A5
$devicePath = $null
$devices = Get-PnpDevice | Where-Object { $_.InstanceId -like '*A5A5*' }

foreach ($device in $devices) {
    Write-Host "Found device: $($device.InstanceId)"

    # Get device interface path
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($device.InstanceId)\Device Parameters"
    if (Test-Path $regPath) {
        $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        Write-Host "Device Parameters: $($props | Out-String)"
    }
}

# Try to find WinUSB device interface
$setupApiPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\{a5dcbf10-6530-11d2-901f-00c04fb951ed}"
if (Test-Path $setupApiPath) {
    Get-ChildItem $setupApiPath | ForEach-Object {
        $name = $_.Name
        if ($name -like "*A5A5*") {
            Write-Host "Found WinUSB interface: $name"
            $symlink = (Get-ItemProperty "$($_.PSPath)\#\Device Parameters" -ErrorAction SilentlyContinue).SymbolicLink
            if ($symlink) {
                $devicePath = $symlink
                Write-Host "Device path: $devicePath"
            }
        }
    }
}

Write-Host "`nSearching device interfaces..."
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses" | ForEach-Object {
    Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -like "*A5A5*") {
            Write-Host "Found: $($_.Name)"
        }
    }
}
