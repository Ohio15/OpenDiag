Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class WinUSBDevice
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
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

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_SetPipePolicy(
        IntPtr InterfaceHandle,
        byte PipeID,
        uint PolicyType,
        uint ValueLength,
        ref uint Value);

    public const uint GENERIC_READ = 0x80000000;
    public const uint GENERIC_WRITE = 0x40000000;
    public const uint FILE_SHARE_READ = 0x00000001;
    public const uint FILE_SHARE_WRITE = 0x00000002;
    public const uint OPEN_EXISTING = 3;
    public const uint FILE_FLAG_OVERLAPPED = 0x40000000;
    public const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
    public const byte PIPE_OUT = 0x02;
    public const byte PIPE_IN = 0x83;
}
"@

$devicePath = "\\?\USB#VID_A5A5&PID_2540#6&148cc033&0&1#{b289714b-1bb0-489c-8824-d5cbd154673a}"

Write-Host "Opening device: $devicePath"

$handle = [WinUSBDevice]::CreateFile(
    $devicePath,
    [WinUSBDevice]::GENERIC_READ -bor [WinUSBDevice]::GENERIC_WRITE,
    [WinUSBDevice]::FILE_SHARE_READ -bor [WinUSBDevice]::FILE_SHARE_WRITE,
    [IntPtr]::Zero,
    [WinUSBDevice]::OPEN_EXISTING,
    [WinUSBDevice]::FILE_FLAG_OVERLAPPED -bor [WinUSBDevice]::FILE_ATTRIBUTE_NORMAL,
    [IntPtr]::Zero
)

if ($handle.IsInvalid) {
    $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Host "Failed to open device. Win32 Error: $lastError"
    exit 1
}

Write-Host "Device handle opened successfully"

$winusbHandle = [IntPtr]::Zero
$result = [WinUSBDevice]::WinUsb_Initialize($handle, [ref]$winusbHandle)

if (-not $result) {
    $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Host "WinUSB Initialize failed. Win32 Error: $lastError"
    $handle.Close()
    exit 1
}

Write-Host "WinUSB initialized successfully"
Write-Host "Handle: $winusbHandle"

# Set timeout policy (PIPE_TRANSFER_TIMEOUT = 3)
$timeout = [uint32]5000
$result = [WinUSBDevice]::WinUsb_SetPipePolicy($winusbHandle, [WinUSBDevice]::PIPE_IN, 3, 4, [ref]$timeout)
Write-Host "Set IN pipe timeout: $result"

$result = [WinUSBDevice]::WinUsb_SetPipePolicy($winusbHandle, [WinUSBDevice]::PIPE_OUT, 3, 4, [ref]$timeout)
Write-Host "Set OUT pipe timeout: $result"

# Test commands
$commands = @(
    @{ Name = "ATZ"; Data = [System.Text.Encoding]::ASCII.GetBytes("ATZ`r") },
    @{ Name = "ATI"; Data = [System.Text.Encoding]::ASCII.GetBytes("ATI`r") },
    @{ Name = "ATRV"; Data = [System.Text.Encoding]::ASCII.GetBytes("ATRV`r") },
    @{ Name = "Ping 0x00"; Data = [byte[]]@(0x00) },
    @{ Name = "Header AA55"; Data = [byte[]]@(0xAA, 0x55, 0x00, 0x00) },
    @{ Name = "Header 55AA"; Data = [byte[]]@(0x55, 0xAA, 0x00, 0x00) }
)

foreach ($cmd in $commands) {
    Write-Host "`n=== Testing: $($cmd.Name) ==="
    Write-Host "TX: $([BitConverter]::ToString($cmd.Data))"

    $transferred = [uint32]0
    $result = [WinUSBDevice]::WinUsb_WritePipe($winusbHandle, [WinUSBDevice]::PIPE_OUT, $cmd.Data, $cmd.Data.Length, [ref]$transferred, [IntPtr]::Zero)
    Write-Host "Write result: $result, transferred: $transferred bytes"

    if ($result) {
        # Try to read response
        $buffer = New-Object byte[] 64
        Start-Sleep -Milliseconds 100
        $result = [WinUSBDevice]::WinUsb_ReadPipe($winusbHandle, [WinUSBDevice]::PIPE_IN, $buffer, 64, [ref]$transferred, [IntPtr]::Zero)

        if ($result -and $transferred -gt 0) {
            $hexResponse = [BitConverter]::ToString($buffer[0..($transferred-1)])
            $asciiResponse = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $transferred)
            $asciiResponse = $asciiResponse -replace '[^\x20-\x7E]', '.'
            Write-Host "RX ($transferred bytes): $hexResponse"
            Write-Host "ASCII: $asciiResponse"
        } else {
            $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-Host "Read failed or no data. Result: $result, Error: $lastError"
        }
    } else {
        $lastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Host "Write failed. Error: $lastError"
    }

    Start-Sleep -Milliseconds 500
}

# Cleanup
[WinUSBDevice]::WinUsb_Free($winusbHandle)
$handle.Close()
Write-Host "`nDevice closed"
