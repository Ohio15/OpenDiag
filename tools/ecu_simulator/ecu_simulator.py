#!/usr/bin/env python3
"""
OBD-II ECU Simulator for OpenDiag Testing

This script simulates an ECU responding to OBD-II queries over CAN bus.
The ELM327 connects to this simulator, then your phone connects to the
ELM327 via Bluetooth, creating a complete test path.

Hardware Requirements:
- USB CAN Adapter (CANable, PCAN-USB, Kvaser, etc.)
- OR Raspberry Pi with CAN HAT (MCP2515 based)

Connection:
- CAN_H from adapter -> OBD-II Pin 6
- CAN_L from adapter -> OBD-II Pin 14
- Provide 12V to OBD-II Pin 16 to power the ELM327

Install dependencies:
    pip install python-can

Linux setup (SocketCAN):
    sudo ip link set can0 type can bitrate 500000
    sudo ip link set up can0

Windows setup (PCAN):
    Uses PCAN hardware directly

Usage:
    python ecu_simulator.py                    # Auto-detect interface
    python ecu_simulator.py --interface pcan   # Use PCAN
    python ecu_simulator.py --interface slcan --channel COM3  # USB-CAN on Windows
    python ecu_simulator.py --interface socketcan --channel can0  # Linux SocketCAN
"""

import can
import time
import random
import argparse
import threading
from dataclasses import dataclass
from typing import Optional

# OBD-II CAN IDs
OBD_REQUEST_ID = 0x7DF   # Broadcast request
OBD_RESPONSE_ID = 0x7E8  # ECU #1 response

# OBD-II Service IDs
SERVICE_01 = 0x01  # Show current data
SERVICE_03 = 0x03  # Show stored DTCs
SERVICE_04 = 0x04  # Clear DTCs
SERVICE_07 = 0x07  # Show pending DTCs
SERVICE_09 = 0x09  # Request vehicle information


@dataclass
class VehicleState:
    """Simulated vehicle data"""
    # Engine data
    rpm: int = 850
    speed: int = 0
    coolant_temp: int = 85      # Celsius
    engine_load: int = 25       # Percent
    throttle: int = 15          # Percent
    intake_temp: int = 35       # Celsius
    maf: float = 12.0           # g/s
    timing_advance: int = 15    # degrees
    fuel_level: int = 75        # Percent
    runtime: int = 0            # seconds
    voltage: float = 13.8       # Battery voltage

    # Fuel trim
    short_term_fuel_trim: int = 0   # -100 to +99.2%
    long_term_fuel_trim: int = 2    # -100 to +99.2%

    # VIN (17 characters)
    vin: str = "1OPENDIAG0TEST123"

    # DTCs
    stored_dtcs: list = None
    pending_dtcs: list = None

    # State
    engine_running: bool = True
    mil_on: bool = False

    def __post_init__(self):
        if self.stored_dtcs is None:
            self.stored_dtcs = []
        if self.pending_dtcs is None:
            self.pending_dtcs = []


class ECUSimulator:
    """OBD-II ECU Simulator"""

    # Supported PIDs bitmap for Mode 01
    SUPPORTED_PIDS_01_20 = 0xBE1FA813  # 00-20
    SUPPORTED_PIDS_21_40 = 0x8000A000  # 21-40
    SUPPORTED_PIDS_41_60 = 0x00000001  # 41-60

    def __init__(self, interface: str = 'socketcan', channel: str = 'can0', bitrate: int = 500000):
        self.vehicle = VehicleState()
        self.running = False
        self.bus: Optional[can.Bus] = None
        self.interface = interface
        self.channel = channel
        self.bitrate = bitrate
        self.start_time = time.time()

    def start(self):
        """Start the ECU simulator"""
        print(f"Starting ECU Simulator...")
        print(f"Interface: {self.interface}")
        print(f"Channel: {self.channel}")
        print(f"Bitrate: {self.bitrate}")

        try:
            self.bus = can.Bus(
                interface=self.interface,
                channel=self.channel,
                bitrate=self.bitrate
            )
            print("CAN bus initialized successfully!")
            print()
            print("ECU Simulator is running. Press Ctrl+C to stop.")
            print("The simulator will respond to OBD-II requests from your ELM327.")
            print()
            print("Interactive commands:")
            print("  r <value>  - Set RPM (e.g., 'r 2500')")
            print("  s <value>  - Set Speed km/h (e.g., 's 60')")
            print("  t <value>  - Set Coolant Temp (e.g., 't 90')")
            print("  d <code>   - Add DTC (e.g., 'd P0300')")
            print("  c          - Clear all DTCs")
            print("  m          - Toggle MIL (check engine light)")
            print("  e          - Toggle engine on/off")
            print("  status     - Show current values")
            print("  drive      - Start drive simulation")
            print("  idle       - Return to idle")
            print()

            self.running = True

            # Start background threads
            update_thread = threading.Thread(target=self._update_loop, daemon=True)
            update_thread.start()

            input_thread = threading.Thread(target=self._input_loop, daemon=True)
            input_thread.start()

            # Main message handling loop
            self._message_loop()

        except can.CanError as e:
            print(f"CAN Error: {e}")
            print()
            print("Troubleshooting:")
            print("  - Check that your CAN adapter is connected")
            print("  - Verify the interface type and channel are correct")
            print("  - On Linux, run: sudo ip link set can0 type can bitrate 500000 && sudo ip link set up can0")
            raise

    def stop(self):
        """Stop the ECU simulator"""
        self.running = False
        if self.bus:
            self.bus.shutdown()
        print("\nECU Simulator stopped.")

    def _message_loop(self):
        """Main loop to receive and process CAN messages"""
        while self.running:
            try:
                msg = self.bus.recv(timeout=0.1)
                if msg and msg.arbitration_id in (OBD_REQUEST_ID, 0x7E0, 0x7E1):
                    self._process_request(msg)
            except can.CanError as e:
                print(f"CAN Error: {e}")

    def _update_loop(self):
        """Background loop to update simulated values"""
        while self.running:
            self._update_simulation()
            time.sleep(0.1)

    def _input_loop(self):
        """Handle user input for interactive control"""
        while self.running:
            try:
                cmd = input().strip().lower()
                self._process_command(cmd)
            except EOFError:
                break
            except Exception as e:
                print(f"Error: {e}")

    def _process_command(self, cmd: str):
        """Process interactive command"""
        parts = cmd.split()
        if not parts:
            return

        command = parts[0]

        if command == 'r' and len(parts) > 1:
            self.vehicle.rpm = max(0, min(8000, int(parts[1])))
            print(f"RPM set to: {self.vehicle.rpm}")

        elif command == 's' and len(parts) > 1:
            self.vehicle.speed = max(0, min(255, int(parts[1])))
            print(f"Speed set to: {self.vehicle.speed} km/h")

        elif command == 't' and len(parts) > 1:
            self.vehicle.coolant_temp = max(-40, min(215, int(parts[1])))
            print(f"Coolant temp set to: {self.vehicle.coolant_temp}C")

        elif command == 'd' and len(parts) > 1:
            dtc = parts[1].upper()
            if dtc not in self.vehicle.stored_dtcs:
                self.vehicle.stored_dtcs.append(dtc)
                self.vehicle.mil_on = True
            print(f"Added DTC: {dtc}")
            print(f"Stored DTCs: {self.vehicle.stored_dtcs}")

        elif command == 'c':
            self.vehicle.stored_dtcs = []
            self.vehicle.pending_dtcs = []
            self.vehicle.mil_on = False
            print("Cleared all DTCs")

        elif command == 'm':
            self.vehicle.mil_on = not self.vehicle.mil_on
            print(f"MIL: {'ON' if self.vehicle.mil_on else 'OFF'}")

        elif command == 'e':
            self.vehicle.engine_running = not self.vehicle.engine_running
            if not self.vehicle.engine_running:
                self.vehicle.rpm = 0
                self.vehicle.speed = 0
            print(f"Engine: {'RUNNING' if self.vehicle.engine_running else 'OFF'}")

        elif command == 'status':
            self._print_status()

        elif command == 'drive':
            print("Starting drive simulation...")
            self._start_drive_sim()

        elif command == 'idle':
            self.vehicle.rpm = 850
            self.vehicle.speed = 0
            self.vehicle.throttle = 15
            self.vehicle.engine_load = 25
            print("Returned to idle")

        elif command == 'help':
            print("Commands: r, s, t, d, c, m, e, status, drive, idle, help")

    def _print_status(self):
        """Print current vehicle status"""
        print("\n=== Vehicle Status ===")
        print(f"Engine: {'RUNNING' if self.vehicle.engine_running else 'OFF'}")
        print(f"MIL: {'ON' if self.vehicle.mil_on else 'OFF'}")
        print(f"RPM: {self.vehicle.rpm}")
        print(f"Speed: {self.vehicle.speed} km/h")
        print(f"Coolant: {self.vehicle.coolant_temp}C")
        print(f"Load: {self.vehicle.engine_load}%")
        print(f"Throttle: {self.vehicle.throttle}%")
        print(f"Fuel: {self.vehicle.fuel_level}%")
        print(f"Voltage: {self.vehicle.voltage:.1f}V")
        print(f"Runtime: {self.vehicle.runtime}s")
        print(f"DTCs: {self.vehicle.stored_dtcs}")
        print(f"VIN: {self.vehicle.vin}")
        print("=====================\n")

    def _start_drive_sim(self):
        """Simulate driving with increasing speed"""
        def drive():
            for speed in range(0, 80, 5):
                if not self.running:
                    break
                self.vehicle.speed = speed
                self.vehicle.rpm = 800 + speed * 30
                self.vehicle.throttle = 20 + speed // 2
                self.vehicle.engine_load = 25 + speed // 2
                time.sleep(0.5)
            print("Drive simulation complete. Use 'idle' to return to idle.")

        threading.Thread(target=drive, daemon=True).start()

    def _update_simulation(self):
        """Update simulated values realistically"""
        if self.vehicle.engine_running:
            # Idle RPM fluctuation
            if self.vehicle.speed == 0:
                self.vehicle.rpm = 800 + random.randint(-30, 30)

            # Update runtime
            self.vehicle.runtime = int(time.time() - self.start_time)

            # Temperature rises slowly
            if self.vehicle.coolant_temp < 90:
                if random.random() < 0.05:
                    self.vehicle.coolant_temp += 1

            # Voltage fluctuation
            self.vehicle.voltage = 13.5 + random.uniform(-0.3, 0.3)
        else:
            self.vehicle.rpm = 0

    def _process_request(self, msg: can.Message):
        """Process OBD-II request and send response"""
        data = msg.data
        if len(data) < 2:
            return

        num_bytes = data[0]
        service = data[1]

        print(f"RX [{hex(msg.arbitration_id)}]: {data.hex()}")

        if service == SERVICE_01:
            if len(data) >= 3:
                self._handle_service_01(data[2])

        elif service == SERVICE_03:
            self._handle_service_03()

        elif service == SERVICE_04:
            self._handle_service_04()

        elif service == SERVICE_07:
            self._handle_service_07()

        elif service == SERVICE_09:
            if len(data) >= 3:
                self._handle_service_09(data[2])

    def _send_response(self, data: bytes):
        """Send CAN response"""
        # Pad to 8 bytes
        data = data + bytes(8 - len(data))
        msg = can.Message(arbitration_id=OBD_RESPONSE_ID, data=data, is_extended_id=False)
        self.bus.send(msg)
        print(f"TX [{hex(OBD_RESPONSE_ID)}]: {data.hex()}")

    def _handle_service_01(self, pid: int):
        """Handle Mode 01 - Show current data"""

        if pid == 0x00:  # Supported PIDs 01-20
            data = bytes([
                0x06, 0x41, 0x00,
                (self.SUPPORTED_PIDS_01_20 >> 24) & 0xFF,
                (self.SUPPORTED_PIDS_01_20 >> 16) & 0xFF,
                (self.SUPPORTED_PIDS_01_20 >> 8) & 0xFF,
                self.SUPPORTED_PIDS_01_20 & 0xFF
            ])
            self._send_response(data)

        elif pid == 0x20:  # Supported PIDs 21-40
            data = bytes([
                0x06, 0x41, 0x20,
                (self.SUPPORTED_PIDS_21_40 >> 24) & 0xFF,
                (self.SUPPORTED_PIDS_21_40 >> 16) & 0xFF,
                (self.SUPPORTED_PIDS_21_40 >> 8) & 0xFF,
                self.SUPPORTED_PIDS_21_40 & 0xFF
            ])
            self._send_response(data)

        elif pid == 0x01:  # Monitor status
            mil = 0x80 if self.vehicle.mil_on else 0x00
            dtc_count = len(self.vehicle.stored_dtcs)
            data = bytes([0x06, 0x41, 0x01, mil | dtc_count, 0x07, 0xE5, 0x00])
            self._send_response(data)

        elif pid == 0x04:  # Engine load
            load = int(self.vehicle.engine_load * 255 / 100)
            data = bytes([0x03, 0x41, 0x04, load])
            self._send_response(data)

        elif pid == 0x05:  # Coolant temperature
            temp = self.vehicle.coolant_temp + 40
            data = bytes([0x03, 0x41, 0x05, temp])
            self._send_response(data)

        elif pid == 0x06:  # Short term fuel trim
            trim = int((self.vehicle.short_term_fuel_trim + 100) * 128 / 100)
            data = bytes([0x03, 0x41, 0x06, trim])
            self._send_response(data)

        elif pid == 0x07:  # Long term fuel trim
            trim = int((self.vehicle.long_term_fuel_trim + 100) * 128 / 100)
            data = bytes([0x03, 0x41, 0x07, trim])
            self._send_response(data)

        elif pid == 0x0C:  # Engine RPM
            rpm = self.vehicle.rpm * 4
            data = bytes([0x04, 0x41, 0x0C, (rpm >> 8) & 0xFF, rpm & 0xFF])
            self._send_response(data)

        elif pid == 0x0D:  # Vehicle speed
            data = bytes([0x03, 0x41, 0x0D, self.vehicle.speed])
            self._send_response(data)

        elif pid == 0x0E:  # Timing advance
            timing = int((self.vehicle.timing_advance + 64) * 2)
            data = bytes([0x03, 0x41, 0x0E, timing])
            self._send_response(data)

        elif pid == 0x0F:  # Intake air temperature
            temp = self.vehicle.intake_temp + 40
            data = bytes([0x03, 0x41, 0x0F, temp])
            self._send_response(data)

        elif pid == 0x10:  # MAF sensor
            maf = int(self.vehicle.maf * 100)
            data = bytes([0x04, 0x41, 0x10, (maf >> 8) & 0xFF, maf & 0xFF])
            self._send_response(data)

        elif pid == 0x11:  # Throttle position
            throttle = int(self.vehicle.throttle * 255 / 100)
            data = bytes([0x03, 0x41, 0x11, throttle])
            self._send_response(data)

        elif pid == 0x1F:  # Runtime since start
            runtime = self.vehicle.runtime
            data = bytes([0x04, 0x41, 0x1F, (runtime >> 8) & 0xFF, runtime & 0xFF])
            self._send_response(data)

        elif pid == 0x2F:  # Fuel level
            fuel = int(self.vehicle.fuel_level * 255 / 100)
            data = bytes([0x03, 0x41, 0x2F, fuel])
            self._send_response(data)

        elif pid == 0x42:  # Control module voltage
            mv = int(self.vehicle.voltage * 1000)
            data = bytes([0x04, 0x41, 0x42, (mv >> 8) & 0xFF, mv & 0xFF])
            self._send_response(data)

        else:
            print(f"Unsupported Mode 01 PID: {hex(pid)}")

    def _handle_service_03(self):
        """Handle Mode 03 - Show stored DTCs"""
        dtc_count = len(self.vehicle.stored_dtcs)

        if dtc_count == 0:
            data = bytes([0x02, 0x43, 0x00])
            self._send_response(data)
        else:
            # Convert DTC codes to bytes
            response = [0x02 + dtc_count * 2, 0x43, dtc_count]
            for dtc in self.vehicle.stored_dtcs[:3]:  # Max 3 DTCs per frame
                high, low = self._encode_dtc(dtc)
                response.extend([high, low])
            self._send_response(bytes(response))

    def _handle_service_04(self):
        """Handle Mode 04 - Clear DTCs"""
        self.vehicle.stored_dtcs = []
        self.vehicle.pending_dtcs = []
        self.vehicle.mil_on = False
        data = bytes([0x01, 0x44])
        self._send_response(data)
        print("DTCs cleared by scan tool")

    def _handle_service_07(self):
        """Handle Mode 07 - Show pending DTCs"""
        dtc_count = len(self.vehicle.pending_dtcs)

        if dtc_count == 0:
            data = bytes([0x02, 0x47, 0x00])
            self._send_response(data)
        else:
            response = [0x02 + dtc_count * 2, 0x47, dtc_count]
            for dtc in self.vehicle.pending_dtcs[:3]:
                high, low = self._encode_dtc(dtc)
                response.extend([high, low])
            self._send_response(bytes(response))

    def _handle_service_09(self, pid: int):
        """Handle Mode 09 - Vehicle information"""

        if pid == 0x00:  # Supported PIDs
            data = bytes([0x06, 0x49, 0x00, 0x55, 0x40, 0x00, 0x00])
            self._send_response(data)

        elif pid == 0x02:  # VIN
            self._send_vin()

    def _send_vin(self):
        """Send VIN as ISO-TP multi-frame"""
        vin = self.vehicle.vin.encode('ascii')

        # First frame
        frame1 = bytes([0x10, 0x14, 0x49, 0x02, 0x01]) + vin[:3]
        self._send_response(frame1)
        time.sleep(0.01)

        # Wait for flow control (we'll just continue)
        # Consecutive frame 1
        frame2 = bytes([0x21]) + vin[3:10]
        self._send_response(frame2)
        time.sleep(0.01)

        # Consecutive frame 2
        frame3 = bytes([0x22]) + vin[10:17]
        self._send_response(frame3)

    def _encode_dtc(self, dtc: str) -> tuple:
        """Encode DTC string to bytes"""
        if len(dtc) != 5:
            return (0, 0)

        # First character determines category
        category = {'P': 0, 'C': 1, 'B': 2, 'U': 3}.get(dtc[0].upper(), 0)

        # Get numeric portion
        try:
            code = int(dtc[1:], 16)
        except ValueError:
            code = 0

        high = (category << 6) | ((code >> 8) & 0x3F)
        low = code & 0xFF

        return (high, low)


def detect_can_interface():
    """Try to auto-detect CAN interface"""
    interfaces = [
        ('socketcan', 'can0'),      # Linux SocketCAN
        ('socketcan', 'vcan0'),     # Virtual CAN (Linux)
        ('pcan', 'PCAN_USBBUS1'),   # PCAN Windows
        ('slcan', 'COM3'),          # SLCAN Windows
        ('slcan', '/dev/ttyUSB0'),  # SLCAN Linux
    ]

    for interface, channel in interfaces:
        try:
            bus = can.Bus(interface=interface, channel=channel, bitrate=500000)
            bus.shutdown()
            print(f"Detected: {interface} on {channel}")
            return interface, channel
        except:
            continue

    return None, None


def main():
    parser = argparse.ArgumentParser(description='OBD-II ECU Simulator for OpenDiag')
    parser.add_argument('--interface', '-i', help='CAN interface type (socketcan, pcan, slcan, etc.)')
    parser.add_argument('--channel', '-c', help='CAN channel (can0, PCAN_USBBUS1, COM3, etc.)')
    parser.add_argument('--bitrate', '-b', type=int, default=500000, help='CAN bitrate (default: 500000)')
    args = parser.parse_args()

    interface = args.interface
    channel = args.channel

    if not interface or not channel:
        print("Auto-detecting CAN interface...")
        detected_if, detected_ch = detect_can_interface()
        interface = interface or detected_if
        channel = channel or detected_ch

    if not interface or not channel:
        print("Error: Could not detect CAN interface.")
        print()
        print("Please specify interface and channel:")
        print("  Linux:   python ecu_simulator.py -i socketcan -c can0")
        print("  Windows: python ecu_simulator.py -i pcan -c PCAN_USBBUS1")
        print("  SLCAN:   python ecu_simulator.py -i slcan -c COM3")
        return

    simulator = ECUSimulator(interface=interface, channel=channel, bitrate=args.bitrate)

    try:
        simulator.start()
    except KeyboardInterrupt:
        pass
    finally:
        simulator.stop()


if __name__ == '__main__':
    main()
