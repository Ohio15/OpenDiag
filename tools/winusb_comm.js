const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Device path from registry
const DEVICE_PATH = '\\\\.\\USB#VID_A5A5&PID_2540#6&148cc033&0&1#{b289714b-1bb0-489c-8824-d5cbd154673a}';

console.log('=== Autel VCI USB Communication ===\n');

// Try to use PowerShell to communicate with WinUSB device
const psScript = `
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
    public static extern bool WinUsb_QueryDeviceInformation(
        IntPtr InterfaceHandle,
        uint InformationType,
        ref uint BufferLength,
        byte[] Buffer);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_QueryInterfaceSettings(
        IntPtr InterfaceHandle,
        byte AlternateInterfaceNumber,
        byte[] UsbAltInterfaceDescriptor);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_QueryPipe(
        IntPtr InterfaceHandle,
        byte AlternateInterfaceNumber,
        byte PipeIndex,
        byte[] PipeInformation);

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

\$devicePath = "\\\\?\\USB#VID_A5A5&PID_2540#6&148cc033&0&1#{b289714b-1bb0-489c-8824-d5cbd154673a}"

Write-Host "Opening device: \$devicePath"

\$handle = [WinUSBDevice]::CreateFile(
    \$devicePath,
    [WinUSBDevice]::GENERIC_READ -bor [WinUSBDevice]::GENERIC_WRITE,
    [WinUSBDevice]::FILE_SHARE_READ -bor [WinUSBDevice]::FILE_SHARE_WRITE,
    [IntPtr]::Zero,
    [WinUSBDevice]::OPEN_EXISTING,
    [WinUSBDevice]::FILE_FLAG_OVERLAPPED -bor [WinUSBDevice]::FILE_ATTRIBUTE_NORMAL,
    [IntPtr]::Zero
)

if (\$handle.IsInvalid) {
    \$error = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Host "Failed to open device. Error: \$error"
    exit 1
}

Write-Host "Device handle opened successfully"

\$winusbHandle = [IntPtr]::Zero
\$result = [WinUSBDevice]::WinUsb_Initialize(\$handle, [ref]\$winusbHandle)

if (-not \$result) {
    \$error = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Host "WinUSB Initialize failed. Error: \$error"
    \$handle.Close()
    exit 1
}

Write-Host "WinUSB initialized successfully"

# Set timeout policy
\$timeout = [uint32]5000
\$result = [WinUSBDevice]::WinUsb_SetPipePolicy(\$winusbHandle, [WinUSBDevice]::PIPE_IN, 3, 4, [ref]\$timeout)
Write-Host "Set pipe policy result: \$result"

# Send ATZ command
\$cmd = [System.Text.Encoding]::ASCII.GetBytes("ATZ\r")
\$transferred = [uint32]0

Write-Host "Sending ATZ command..."
\$result = [WinUSBDevice]::WinUsb_WritePipe(\$winusbHandle, [WinUSBDevice]::PIPE_OUT, \$cmd, \$cmd.Length, [ref]\$transferred, [IntPtr]::Zero)
Write-Host "Write result: \$result, transferred: \$transferred"

# Read response
\$buffer = New-Object byte[] 64
\$result = [WinUSBDevice]::WinUsb_ReadPipe(\$winusbHandle, [WinUSBDevice]::PIPE_IN, \$buffer, 64, [ref]\$transferred, [IntPtr]::Zero)
Write-Host "Read result: \$result, transferred: \$transferred"
if (\$result -and \$transferred -gt 0) {
    \$response = [System.Text.Encoding]::ASCII.GetString(\$buffer, 0, \$transferred)
    Write-Host "Response: \$response"
    Write-Host "Hex: \$([BitConverter]::ToString(\$buffer[0..(\$transferred-1)]))"
}

# Cleanup
[WinUSBDevice]::WinUsb_Free(\$winusbHandle)
\$handle.Close()
Write-Host "Device closed"
`;

// Write the script to a temp file and execute
const tempScript = path.join(process.env.TEMP || 'C:\\Temp', 'winusb_test.ps1');
fs.writeFileSync(tempScript, psScript);

try {
  const result = execSync(`powershell -ExecutionPolicy Bypass -File "${tempScript}"`, {
    encoding: 'utf8',
    timeout: 30000
  });
  console.log(result);
} catch (err) {
  console.log('Output:', err.stdout);
  console.error('Error:', err.stderr);
}
