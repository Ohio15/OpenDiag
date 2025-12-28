# Bluetooth ELM327 Emulator for OpenDiag

This tool emulates an ELM327 OBD-II adapter over Bluetooth, allowing you to test OpenDiag without any physical hardware. Your phone connects to this emulator just like it would connect to a real ELM327.

## Data Flow

```
┌─────────────┐     Bluetooth SPP     ┌─────────────┐
│  OpenDiag   │◄─────────────────────►│   ELM327    │
│    App      │     (Phone to PC)     │  Emulator   │
│  (Phone)    │                       │  (Pi/PC)    │
└─────────────┘                       └─────────────┘
```

**No physical OBD-II adapter or vehicle needed!**

## Quick Start

### Option 1: Raspberry Pi / Linux (Bluetooth SPP)

This is the recommended approach for the most realistic testing.

```bash
# Install dependencies
sudo apt install bluetooth bluez python3-pip
pip3 install pybluez

# Run emulator (requires root for Bluetooth)
sudo python3 elm327_emulator.py --bluetooth
```

The emulator will advertise as "OBDII" - pair from your phone and connect using OpenDiag's **Bluetooth Classic** option.

### Option 2: TCP/Network (Any Platform)

If Bluetooth SPP is not available, use TCP mode:

```bash
python3 elm327_emulator.py --tcp 35000
```

Then in OpenDiag, use the **Network VCI** option and connect to `<your-pc-ip>:35000`.

### Option 3: Serial Port (Virtual COM)

For testing with virtual serial ports (like com0com on Windows):

```bash
# Windows
python elm327_emulator.py --serial COM5

# Linux
python3 elm327_emulator.py --serial /dev/pts/1
```

### Option 4: Interactive Mode (Testing)

Test ELM327 commands manually:

```bash
python3 elm327_emulator.py --interactive
```

## Raspberry Pi Bluetooth Setup (Detailed)

### 1. Install Dependencies

```bash
sudo apt update
sudo apt install -y bluetooth bluez python3-pip python3-dev libbluetooth-dev

# Install PyBluez
pip3 install pybluez
```

### 2. Configure Bluetooth

```bash
# Make Pi discoverable and enable SPP
sudo hciconfig hci0 piscan

# Add SPP profile to Bluetooth daemon
sudo nano /etc/systemd/system/dbus-org.bluez.service
```

Add to the `ExecStart` line: `--compat -C`

```
ExecStart=/usr/lib/bluetooth/bluetoothd --compat -C
```

Then restart Bluetooth:

```bash
sudo systemctl daemon-reload
sudo systemctl restart bluetooth

# Add SP (Serial Port) profile
sudo sdptool add SP
```

### 3. Run Emulator

```bash
sudo python3 elm327_emulator.py --bluetooth
```

### 4. Pair from Phone

1. Open phone's Bluetooth settings
2. Scan for devices - you should see "OBDII" or your Pi's name
3. Pair with PIN 1234 (or no PIN)
4. Open OpenDiag app
5. Select "Bluetooth Classic" connection
6. Select the paired device

## Windows Bluetooth Setup

### Option A: Use TCP Mode (Easiest)

The simplest approach on Windows is to use TCP mode:

```bash
python elm327_emulator.py --tcp 35000
```

Then connect from OpenDiag using Network VCI to your Windows PC's IP.

### Option B: Virtual COM Port Pair

1. Install [com0com](http://com0com.sourceforge.net/) or similar null-modem emulator
2. Create a COM port pair (e.g., COM5 <-> COM6)
3. Run emulator on one port:
   ```bash
   python elm327_emulator.py --serial COM5
   ```
4. Configure your Bluetooth software to use COM6 as outgoing COM port
5. This varies by Bluetooth adapter software

### Option C: WSL2 with USB Bluetooth (Advanced)

If you need real Bluetooth on Windows, use WSL2 with USB passthrough:

```bash
# In WSL2 Ubuntu
sudo apt install bluetooth bluez python3-pip
pip3 install pybluez

# Attach USB Bluetooth adapter to WSL2
# (requires usbipd-win on Windows)

sudo python3 elm327_emulator.py --bluetooth
```

## Simulated Data

The emulator provides realistic responses for:

### Mode 01 (Current Data)
| PID | Description | Default |
|-----|-------------|---------|
| 0x04 | Engine Load | 25% |
| 0x05 | Coolant Temp | 85°C |
| 0x0C | Engine RPM | 850 RPM |
| 0x0D | Vehicle Speed | 0 km/h |
| 0x0F | Intake Air Temp | 35°C |
| 0x10 | MAF Sensor | 12.0 g/s |
| 0x11 | Throttle Position | 15% |
| 0x2F | Fuel Level | 75% |
| 0x42 | Control Module Voltage | 13.8V |

### Mode 03 (Stored DTCs)
- Returns configured DTCs
- Supports MIL indicator

### Mode 04 (Clear DTCs)
- Clears stored and pending DTCs
- Turns off MIL

### Mode 09 (Vehicle Info)
- VIN: "1OPENDIAG0TEST123"
- ECU Name: "OpenDiag ECU"

## Interactive Commands

When running in interactive mode or via the control interface:

| Command | Description | Example |
|---------|-------------|---------|
| `set rpm <value>` | Set engine RPM | `set rpm 2500` |
| `set speed <value>` | Set speed (km/h) | `set speed 60` |
| `set temp <value>` | Set coolant temp (°C) | `set temp 90` |
| `set load <value>` | Set engine load (%) | `set load 45` |
| `set throttle <value>` | Set throttle (%) | `set throttle 30` |
| `set fuel <value>` | Set fuel level (%) | `set fuel 50` |
| `set dtc <code>` | Add a DTC | `set dtc P0300` |
| `clear` | Clear all DTCs | `clear` |
| `status` | Show current values | `status` |

## Simulating Drive Scenarios

### Idle
```
set rpm 850
set speed 0
set load 20
set throttle 10
```

### City Driving
```
set rpm 2000
set speed 50
set load 40
set throttle 25
```

### Highway Cruising
```
set rpm 2500
set speed 100
set load 35
set throttle 20
```

### Check Engine Light
```
set dtc P0300
set dtc P0171
```

## Troubleshooting

### "Permission denied" on Linux
```bash
# Bluetooth requires root
sudo python3 elm327_emulator.py --bluetooth
```

### Phone can't find the device
1. Make sure Pi/PC is discoverable: `sudo hciconfig hci0 piscan`
2. Check Bluetooth is enabled: `sudo hciconfig hci0 up`
3. Verify SPP profile: `sudo sdptool browse local | grep -i serial`

### Connection drops immediately
The emulator might be crashing. Run with verbose output:
```bash
sudo python3 elm327_emulator.py --bluetooth 2>&1 | tee debug.log
```

### "PyBluez not available"
```bash
# Install development headers first
sudo apt install python3-dev libbluetooth-dev
pip3 install pybluez
```

### App shows "Unable to connect"
1. Ensure you're using "Bluetooth Classic" in OpenDiag, not BLE
2. Make sure the device is paired before connecting
3. Try removing the pairing and re-pairing

## Comparison with ECU Simulator

| Feature | Bluetooth Emulator | ECU Simulator |
|---------|-------------------|---------------|
| Hardware needed | Pi/PC with Bluetooth | CAN adapter + ELM327 |
| Phone connection | Direct Bluetooth | Through real ELM327 |
| Realism | Good for app testing | Full CAN protocol |
| Cost | Just a Raspberry Pi | ~$30-50 hardware |
| Best for | App development | Protocol testing |

## Requirements

- Python 3.7+
- PyBluez (for Bluetooth mode)
- pyserial (for serial mode)

```bash
pip3 install pybluez pyserial
```
