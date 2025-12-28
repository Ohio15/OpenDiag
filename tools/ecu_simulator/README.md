# OBD-II ECU Simulator for OpenDiag

This tool simulates a vehicle's ECU, allowing you to test OpenDiag without a real vehicle. The simulator connects to your ELM327 adapter's OBD-II port side, and your phone/device connects to the ELM327 via Bluetooth as normal.

```
┌─────────────┐     CAN Bus      ┌─────────────┐    Bluetooth    ┌─────────────┐
│    ECU      │◄────────────────►│   ELM327    │◄───────────────►│  OpenDiag   │
│  Simulator  │   (OBD-II Port)  │   Adapter   │                 │    App      │
└─────────────┘                  └─────────────┘                 └─────────────┘
```

## Hardware Options

### Option 1: Arduino with MCP2515 CAN Shield (Recommended for beginners)

**Parts needed:**
- Arduino Uno, Nano, or Mega (~$5-25)
- MCP2515 CAN Bus Module (~$5-10)
- OBD-II Male Connector or breakout (~$5)
- 12V Power Supply (to power ELM327)
- Jumper wires

**Wiring - MCP2515 to Arduino:**
```
MCP2515    Arduino
────────────────────
VCC    →   5V
GND    →   GND
CS     →   Pin 10
SO     →   Pin 12 (MISO)
SI     →   Pin 11 (MOSI)
SCK    →   Pin 13
INT    →   Pin 2 (optional)
```

**Wiring - MCP2515 to OBD-II Connector:**
```
MCP2515    OBD-II Pin
────────────────────────
CAN_H  →   Pin 6
CAN_L  →   Pin 14
```

**OBD-II Power (for ELM327):**
```
12V Power Supply   OBD-II Pin
──────────────────────────────
+12V           →   Pin 16
GND            →   Pin 4 & 5
```

**Setup:**
1. Install Arduino IDE
2. Install MCP_CAN library: Sketch → Include Library → Manage Libraries → Search "MCP_CAN"
3. Open `ecu_simulator.ino`
4. Select your board and port
5. Upload to Arduino
6. Open Serial Monitor (115200 baud) to see activity

### Option 2: USB-CAN Adapter with Python (More powerful)

**Compatible adapters:**
- CANable / CANable Pro (~$25-40)
- PCAN-USB (~$200)
- Kvaser Leaf Light (~$300)
- Any SocketCAN compatible adapter

**Parts needed:**
- USB-CAN adapter (see above)
- OBD-II Male Connector or breakout
- 12V Power Supply (to power ELM327)

**Wiring - CAN Adapter to OBD-II:**
```
CAN Adapter    OBD-II Pin
────────────────────────────
CAN_H      →   Pin 6
CAN_L      →   Pin 14
GND        →   Pin 4 & 5
```

**Setup (Linux):**
```bash
# Install python-can
pip install python-can

# Setup SocketCAN
sudo ip link set can0 type can bitrate 500000
sudo ip link set up can0

# Run simulator
python ecu_simulator.py -i socketcan -c can0
```

**Setup (Windows with PCAN):**
```bash
pip install python-can
python ecu_simulator.py -i pcan -c PCAN_USBBUS1
```

**Setup (Windows with SLCAN/CANable):**
```bash
pip install python-can
python ecu_simulator.py -i slcan -c COM3
```

### Option 3: Raspberry Pi with CAN HAT

**Parts needed:**
- Raspberry Pi (any model with GPIO)
- MCP2515 CAN HAT (~$15-25)
- OBD-II Connector
- 12V Power Supply

**Setup:**
```bash
# Enable SPI in /boot/config.txt
dtparam=spi=on
dtoverlay=mcp2515-can0,oscillator=8000000,interrupt=25

# Reboot
sudo reboot

# Setup CAN interface
sudo ip link set can0 type can bitrate 500000
sudo ip link set up can0

# Install and run
pip install python-can
python ecu_simulator.py -i socketcan -c can0
```

## OBD-II Connector Pinout

```
       ___________
      /  1  2  3  \
     |  4  5  6  7  |
     |  8  9 10 11  |
      \ 12 13 14 15 /
       \____16____/

Pin 4  = Chassis Ground
Pin 5  = Signal Ground
Pin 6  = CAN High (CAN_H)
Pin 14 = CAN Low (CAN_L)
Pin 16 = Battery Power (+12V)
```

## Usage

### Arduino Serial Commands

Once uploaded, open Serial Monitor at 115200 baud:

| Command | Description | Example |
|---------|-------------|---------|
| `r<value>` | Set RPM | `r2500` |
| `s<value>` | Set Speed (km/h) | `s60` |
| `t<value>` | Set Coolant Temp (C) | `t90` |
| `l<value>` | Set Engine Load (%) | `l45` |
| `f<value>` | Set Fuel Level (%) | `f50` |
| `d` | Add DTC P0300 | `d` |
| `c` | Clear DTCs | `c` |
| `e` | Toggle Engine On/Off | `e` |

### Python Interactive Commands

| Command | Description | Example |
|---------|-------------|---------|
| `r <value>` | Set RPM | `r 2500` |
| `s <value>` | Set Speed (km/h) | `s 60` |
| `t <value>` | Set Coolant Temp (C) | `t 90` |
| `d <code>` | Add DTC | `d P0300` |
| `c` | Clear all DTCs | `c` |
| `m` | Toggle MIL (Check Engine) | `m` |
| `e` | Toggle Engine On/Off | `e` |
| `status` | Show current values | `status` |
| `drive` | Start drive simulation | `drive` |
| `idle` | Return to idle | `idle` |

## Simulated Data

The simulator provides realistic responses for:

### Mode 01 (Current Data)
- RPM (PID 0x0C)
- Vehicle Speed (PID 0x0D)
- Coolant Temperature (PID 0x05)
- Engine Load (PID 0x04)
- Throttle Position (PID 0x11)
- Intake Air Temperature (PID 0x0F)
- MAF Sensor (PID 0x10)
- Timing Advance (PID 0x0E)
- Fuel Level (PID 0x2F)
- Runtime (PID 0x1F)
- Battery Voltage (PID 0x42)
- Fuel Trim (PIDs 0x06, 0x07)

### Mode 03 (Stored DTCs)
- Returns configured DTCs
- MIL indicator status

### Mode 04 (Clear DTCs)
- Clears stored and pending DTCs
- Turns off MIL

### Mode 09 (Vehicle Info)
- VIN: "1OPENDIAG0TEST123" (customizable)

## Troubleshooting

### ELM327 not responding
1. Check 12V power to OBD-II Pin 16
2. Verify CAN_H and CAN_L connections
3. Check ground connections
4. Ensure CAN bitrate is 500kbps

### CAN adapter not detected (Linux)
```bash
# Check if interface exists
ip link show can0

# Bring up interface
sudo ip link set can0 type can bitrate 500000
sudo ip link set up can0

# Check for errors
dmesg | grep -i can
```

### Arduino not sending
1. Check MCP2515 crystal frequency (8MHz or 16MHz)
2. Update `CAN_CLOCK` in code to match your module
3. Verify SPI wiring (MISO, MOSI, SCK, CS)

### No data in OpenDiag app
1. Ensure ELM327 is paired via Bluetooth
2. Check that simulator is running and showing "RX" messages
3. Verify ELM327 LED activity when app sends commands
4. Try resetting ELM327 (disconnect/reconnect power)

## Customization

### Change VIN (Arduino)
Edit `vehicle.vin` in the code:
```cpp
char vin[18] = "YOUR17CHARVIN1234";
```

### Change VIN (Python)
```python
simulator.vehicle.vin = "YOUR17CHARVIN1234"
```

### Add More DTCs (Python)
```python
simulator.vehicle.stored_dtcs = ['P0300', 'P0171', 'P0420']
simulator.vehicle.mil_on = True
```

## Safety Warning

This simulator is for testing purposes only. Never use simulation equipment on a real vehicle's diagnostic port. Always disconnect the simulator before connecting to a real vehicle.
