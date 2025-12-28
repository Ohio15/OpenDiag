#!/usr/bin/env python3
"""
Bluetooth ELM327 Emulator for OpenDiag Testing

This script emulates an ELM327 OBD-II adapter over Bluetooth SPP.
Your phone connects to this emulator thinking it's a real ELM327,
and receives simulated vehicle data.

Requirements:
- Raspberry Pi or Linux PC with Bluetooth
- OR Windows PC with Bluetooth (uses different backend)

Data Flow:
    OpenDiag App (Phone) <--Bluetooth SPP--> This Emulator (Pi/PC)

The app connects via Bluetooth just like with a real ELM327,
but this software returns simulated vehicle data.

Linux/Raspberry Pi Setup:
    sudo apt install bluetooth bluez python3-pip
    pip3 install pybluez
    sudo python3 elm327_emulator.py

Windows Setup:
    pip install pyserial
    # Create virtual COM port pair (com0com) or use real Bluetooth
    python elm327_emulator.py --serial COM5

Usage:
    sudo python3 elm327_emulator.py              # Bluetooth SPP (Linux)
    python3 elm327_emulator.py --serial /dev/pts/1  # Serial port
    python3 elm327_emulator.py --tcp 35000       # TCP socket (for Network VCI)
"""

import sys
import time
import random
import argparse
import threading
import socket
from dataclasses import dataclass, field
from typing import Optional, List

# Try to import Bluetooth library
try:
    import bluetooth
    BLUETOOTH_AVAILABLE = True
except ImportError:
    BLUETOOTH_AVAILABLE = False
    print("Note: PyBluez not available. Use --serial or --tcp mode.")

# Try to import serial library
try:
    import serial
    SERIAL_AVAILABLE = True
except ImportError:
    SERIAL_AVAILABLE = False


@dataclass
class VehicleState:
    """Simulated vehicle data"""
    rpm: int = 850
    speed: int = 0
    coolant_temp: int = 85
    engine_load: int = 25
    throttle: int = 15
    intake_temp: int = 35
    maf: float = 12.0
    timing_advance: int = 15
    fuel_level: int = 75
    runtime: int = 0
    voltage: float = 13.8
    short_term_fuel_trim: int = 0
    long_term_fuel_trim: int = 2
    fuel_pressure: int = 45
    intake_pressure: int = 101

    vin: str = "1OPENDIAG0TEST123"
    ecu_name: str = "OpenDiag ECU"

    stored_dtcs: List[str] = field(default_factory=list)
    pending_dtcs: List[str] = field(default_factory=list)
    mil_on: bool = False
    engine_running: bool = True

    # Supported PIDs bitmaps
    supported_01_20: int = 0xBE1FA813
    supported_21_40: int = 0x8016A003
    supported_41_60: int = 0xFED00001


class ELM327Emulator:
    """Emulates ELM327 OBD-II adapter"""

    def __init__(self):
        self.vehicle = VehicleState()
        self.running = False
        self.start_time = time.time()

        # ELM327 state
        self.echo = True
        self.linefeed = True
        self.spaces = True
        self.headers = False
        self.protocol = "AUTO"
        self.timeout = 50  # x4ms = 200ms

    def process_command(self, cmd: str) -> str:
        """Process ELM327 command and return response"""
        cmd = cmd.strip().upper()

        if not cmd:
            return ">"

        # Echo command if enabled
        response = ""
        if self.echo:
            response = cmd + "\r"

        # AT Commands
        if cmd.startswith("AT"):
            result = self._handle_at_command(cmd[2:])
        # OBD-II Commands
        elif cmd and all(c in '0123456789ABCDEF' for c in cmd):
            result = self._handle_obd_command(cmd)
        else:
            result = "?"

        # Format response
        if self.linefeed:
            response += result + "\r\n>"
        else:
            response += result + "\r>"

        return response

    def _handle_at_command(self, cmd: str) -> str:
        """Handle AT commands"""
        cmd = cmd.strip()

        # Reset
        if cmd in ("Z", "WS"):
            self.echo = True
            self.linefeed = True
            self.spaces = True
            self.headers = False
            return "\r\rELM327 v1.5\r"

        # Warm start
        if cmd == "WS":
            return "ELM327 v1.5"

        # Identify
        if cmd == "I":
            return "ELM327 v1.5"

        # Device description
        if cmd == "@1":
            return "OpenDiag ELM327 Emulator"

        # Echo control
        if cmd == "E0":
            self.echo = False
            return "OK"
        if cmd == "E1":
            self.echo = True
            return "OK"

        # Linefeed control
        if cmd == "L0":
            self.linefeed = False
            return "OK"
        if cmd == "L1":
            self.linefeed = True
            return "OK"

        # Spaces control
        if cmd == "S0":
            self.spaces = False
            return "OK"
        if cmd == "S1":
            self.spaces = True
            return "OK"

        # Headers control
        if cmd == "H0":
            self.headers = False
            return "OK"
        if cmd == "H1":
            self.headers = True
            return "OK"

        # Protocol
        if cmd.startswith("SP"):
            self.protocol = cmd[2:] or "AUTO"
            return "OK"
        if cmd == "DP":
            return "AUTO, ISO 15765-4 (CAN 11/500)"
        if cmd == "DPN":
            return "6"

        # Timeout
        if cmd.startswith("ST"):
            try:
                self.timeout = int(cmd[2:], 16)
            except:
                pass
            return "OK"

        # Adaptive timing
        if cmd.startswith("AT"):
            return "OK"

        # Memory off
        if cmd == "M0":
            return "OK"

        # CAN settings
        if cmd.startswith("SH") or cmd.startswith("FC") or cmd.startswith("CF") or cmd.startswith("CM"):
            return "OK"
        if cmd.startswith("CRA"):
            return "OK"
        if cmd == "CAF0" or cmd == "CAF1":
            return "OK"

        # Voltage
        if cmd == "RV":
            return f"{self.vehicle.voltage:.1f}V"

        # Ignition status
        if cmd == "IGN":
            return "ON" if self.vehicle.engine_running else "OFF"

        # Protocol close
        if cmd == "PC":
            return "OK"

        # Low power mode
        if cmd == "LP":
            return "OK"

        # Programmable parameters
        if cmd.startswith("PP"):
            return "OK"

        return "OK"

    def _handle_obd_command(self, cmd: str) -> str:
        """Handle OBD-II commands"""
        if len(cmd) < 2:
            return "?"

        service = int(cmd[:2], 16)

        if service == 0x01:  # Mode 01 - Current data
            if len(cmd) >= 4:
                pid = int(cmd[2:4], 16)
                return self._mode_01(pid)
            return "?"

        elif service == 0x03:  # Mode 03 - Stored DTCs
            return self._mode_03()

        elif service == 0x04:  # Mode 04 - Clear DTCs
            return self._mode_04()

        elif service == 0x07:  # Mode 07 - Pending DTCs
            return self._mode_07()

        elif service == 0x09:  # Mode 09 - Vehicle info
            if len(cmd) >= 4:
                pid = int(cmd[2:4], 16)
                return self._mode_09(pid)
            return "?"

        return "NO DATA"

    def _format_response(self, service: int, pid: int, data: List[int]) -> str:
        """Format OBD-II response"""
        response_service = service + 0x40

        if self.headers:
            header = "7E8 "
        else:
            header = ""

        data_hex = [response_service, pid] + data

        if self.spaces:
            return header + " ".join(f"{b:02X}" for b in data_hex)
        else:
            return header + "".join(f"{b:02X}" for b in data_hex)

    def _mode_01(self, pid: int) -> str:
        """Handle Mode 01 - Current data"""

        # Update runtime
        self.vehicle.runtime = int(time.time() - self.start_time)

        # Supported PIDs
        if pid == 0x00:
            return self._format_response(0x01, 0x00, [
                (self.vehicle.supported_01_20 >> 24) & 0xFF,
                (self.vehicle.supported_01_20 >> 16) & 0xFF,
                (self.vehicle.supported_01_20 >> 8) & 0xFF,
                self.vehicle.supported_01_20 & 0xFF
            ])

        if pid == 0x20:
            return self._format_response(0x01, 0x20, [
                (self.vehicle.supported_21_40 >> 24) & 0xFF,
                (self.vehicle.supported_21_40 >> 16) & 0xFF,
                (self.vehicle.supported_21_40 >> 8) & 0xFF,
                self.vehicle.supported_21_40 & 0xFF
            ])

        if pid == 0x40:
            return self._format_response(0x01, 0x40, [
                (self.vehicle.supported_41_60 >> 24) & 0xFF,
                (self.vehicle.supported_41_60 >> 16) & 0xFF,
                (self.vehicle.supported_41_60 >> 8) & 0xFF,
                self.vehicle.supported_41_60 & 0xFF
            ])

        # Monitor status
        if pid == 0x01:
            mil = 0x80 if self.vehicle.mil_on else 0x00
            dtc_count = len(self.vehicle.stored_dtcs)
            return self._format_response(0x01, 0x01, [mil | dtc_count, 0x07, 0xE5, 0x00])

        # Fuel system status
        if pid == 0x03:
            return self._format_response(0x01, 0x03, [0x02, 0x00])

        # Engine load
        if pid == 0x04:
            load = int(self.vehicle.engine_load * 255 / 100)
            return self._format_response(0x01, 0x04, [load])

        # Coolant temperature
        if pid == 0x05:
            temp = self.vehicle.coolant_temp + 40
            return self._format_response(0x01, 0x05, [temp])

        # Short term fuel trim
        if pid == 0x06:
            trim = int((self.vehicle.short_term_fuel_trim + 100) * 128 / 100)
            return self._format_response(0x01, 0x06, [trim])

        # Long term fuel trim
        if pid == 0x07:
            trim = int((self.vehicle.long_term_fuel_trim + 100) * 128 / 100)
            return self._format_response(0x01, 0x07, [trim])

        # Fuel pressure
        if pid == 0x0A:
            return self._format_response(0x01, 0x0A, [self.vehicle.fuel_pressure * 3])

        # Intake manifold pressure
        if pid == 0x0B:
            return self._format_response(0x01, 0x0B, [self.vehicle.intake_pressure])

        # Engine RPM
        if pid == 0x0C:
            rpm = self.vehicle.rpm * 4
            return self._format_response(0x01, 0x0C, [(rpm >> 8) & 0xFF, rpm & 0xFF])

        # Vehicle speed
        if pid == 0x0D:
            return self._format_response(0x01, 0x0D, [self.vehicle.speed])

        # Timing advance
        if pid == 0x0E:
            timing = int((self.vehicle.timing_advance + 64) * 2)
            return self._format_response(0x01, 0x0E, [timing])

        # Intake air temperature
        if pid == 0x0F:
            temp = self.vehicle.intake_temp + 40
            return self._format_response(0x01, 0x0F, [temp])

        # MAF sensor
        if pid == 0x10:
            maf = int(self.vehicle.maf * 100)
            return self._format_response(0x01, 0x10, [(maf >> 8) & 0xFF, maf & 0xFF])

        # Throttle position
        if pid == 0x11:
            throttle = int(self.vehicle.throttle * 255 / 100)
            return self._format_response(0x01, 0x11, [throttle])

        # OBD standard
        if pid == 0x1C:
            return self._format_response(0x01, 0x1C, [0x06])  # ISO 15765-4

        # Runtime since start
        if pid == 0x1F:
            runtime = self.vehicle.runtime
            return self._format_response(0x01, 0x1F, [(runtime >> 8) & 0xFF, runtime & 0xFF])

        # Distance with MIL on
        if pid == 0x21:
            dist = 100 if self.vehicle.mil_on else 0
            return self._format_response(0x01, 0x21, [(dist >> 8) & 0xFF, dist & 0xFF])

        # Fuel level
        if pid == 0x2F:
            fuel = int(self.vehicle.fuel_level * 255 / 100)
            return self._format_response(0x01, 0x2F, [fuel])

        # Distance since codes cleared
        if pid == 0x31:
            return self._format_response(0x01, 0x31, [0x00, 0x64])  # 100 km

        # Control module voltage
        if pid == 0x42:
            mv = int(self.vehicle.voltage * 1000)
            return self._format_response(0x01, 0x42, [(mv >> 8) & 0xFF, mv & 0xFF])

        # Absolute load
        if pid == 0x43:
            load = int(self.vehicle.engine_load * 255 / 100)
            return self._format_response(0x01, 0x43, [0x00, load])

        # Ambient air temperature
        if pid == 0x46:
            return self._format_response(0x01, 0x46, [self.vehicle.intake_temp + 40])

        # Accelerator pedal position
        if pid == 0x49:
            return self._format_response(0x01, 0x49, [int(self.vehicle.throttle * 255 / 100)])

        return "NO DATA"

    def _mode_03(self) -> str:
        """Handle Mode 03 - Stored DTCs"""
        dtcs = self.vehicle.stored_dtcs

        if not dtcs:
            if self.spaces:
                return "43 00"
            return "4300"

        # Build response
        response = [0x43, len(dtcs)]
        for dtc in dtcs[:6]:  # Max 6 DTCs per response
            high, low = self._encode_dtc(dtc)
            response.extend([high, low])

        if self.spaces:
            return " ".join(f"{b:02X}" for b in response)
        return "".join(f"{b:02X}" for b in response)

    def _mode_04(self) -> str:
        """Handle Mode 04 - Clear DTCs"""
        self.vehicle.stored_dtcs = []
        self.vehicle.pending_dtcs = []
        self.vehicle.mil_on = False
        print("[Emulator] DTCs cleared")
        return "44"

    def _mode_07(self) -> str:
        """Handle Mode 07 - Pending DTCs"""
        dtcs = self.vehicle.pending_dtcs

        if not dtcs:
            if self.spaces:
                return "47 00"
            return "4700"

        response = [0x47, len(dtcs)]
        for dtc in dtcs[:6]:
            high, low = self._encode_dtc(dtc)
            response.extend([high, low])

        if self.spaces:
            return " ".join(f"{b:02X}" for b in response)
        return "".join(f"{b:02X}" for b in response)

    def _mode_09(self, pid: int) -> str:
        """Handle Mode 09 - Vehicle information"""

        # Supported PIDs
        if pid == 0x00:
            return self._format_response(0x09, 0x00, [0x55, 0x40, 0x00, 0x00])

        # VIN message count
        if pid == 0x01:
            return self._format_response(0x09, 0x01, [0x05])

        # VIN
        if pid == 0x02:
            vin = self.vehicle.vin.encode('ascii')
            # ELM327 format: multiple lines
            lines = []
            lines.append("49 02 01 " + " ".join(f"{b:02X}" for b in vin[:5]))
            lines.append("49 02 02 " + " ".join(f"{b:02X}" for b in vin[5:10]))
            lines.append("49 02 03 " + " ".join(f"{b:02X}" for b in vin[10:15]))
            lines.append("49 02 04 " + " ".join(f"{b:02X}" for b in vin[15:17]) + " 00 00 00")
            if not self.spaces:
                lines = [l.replace(" ", "") for l in lines]
            return "\r".join(lines)

        # Calibration ID count
        if pid == 0x03:
            return self._format_response(0x09, 0x03, [0x01])

        # ECU name
        if pid == 0x0A:
            name = self.vehicle.ecu_name[:20].ljust(20).encode('ascii')
            lines = []
            lines.append("49 0A 01 " + " ".join(f"{b:02X}" for b in name[:5]))
            lines.append("49 0A 02 " + " ".join(f"{b:02X}" for b in name[5:10]))
            lines.append("49 0A 03 " + " ".join(f"{b:02X}" for b in name[10:15]))
            lines.append("49 0A 04 " + " ".join(f"{b:02X}" for b in name[15:20]))
            if not self.spaces:
                lines = [l.replace(" ", "") for l in lines]
            return "\r".join(lines)

        return "NO DATA"

    def _encode_dtc(self, dtc: str) -> tuple:
        """Encode DTC string (e.g., 'P0300') to bytes"""
        if len(dtc) != 5:
            return (0, 0)

        category = {'P': 0, 'C': 1, 'B': 2, 'U': 3}.get(dtc[0].upper(), 0)

        try:
            code = int(dtc[1:], 16)
        except ValueError:
            code = 0

        high = (category << 6) | ((code >> 8) & 0x3F)
        low = code & 0xFF

        return (high, low)

    def update_simulation(self):
        """Update simulated values"""
        if self.vehicle.engine_running:
            # RPM fluctuation at idle
            if self.vehicle.speed == 0:
                self.vehicle.rpm = 800 + random.randint(-30, 30)

            # Voltage fluctuation
            self.vehicle.voltage = 13.5 + random.uniform(-0.3, 0.3)

            # Temperature slowly rises
            if self.vehicle.coolant_temp < 90:
                if random.random() < 0.02:
                    self.vehicle.coolant_temp += 1
        else:
            self.vehicle.rpm = 0


def run_bluetooth_server(emulator: ELM327Emulator):
    """Run Bluetooth SPP server (Linux/Raspberry Pi)"""
    if not BLUETOOTH_AVAILABLE:
        print("Error: PyBluez not available. Install with: pip install pybluez")
        sys.exit(1)

    # SPP UUID
    uuid = "00001101-0000-1000-8000-00805F9B34FB"

    server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
    server_sock.bind(("", bluetooth.PORT_ANY))
    server_sock.listen(1)

    port = server_sock.getsockname()[1]

    bluetooth.advertise_service(
        server_sock,
        "OBDII",
        service_id=uuid,
        service_classes=[uuid, bluetooth.SERIAL_PORT_CLASS],
        profiles=[bluetooth.SERIAL_PORT_PROFILE]
    )

    print(f"Bluetooth ELM327 Emulator")
    print(f"========================")
    print(f"Advertising as 'OBDII' on RFCOMM channel {port}")
    print(f"Waiting for connection from OpenDiag app...")
    print()
    print("Pair this device from your phone's Bluetooth settings,")
    print("then connect using OpenDiag's Bluetooth Classic option.")
    print()

    emulator.running = True

    # Start update thread
    def update_loop():
        while emulator.running:
            emulator.update_simulation()
            time.sleep(0.1)

    update_thread = threading.Thread(target=update_loop, daemon=True)
    update_thread.start()

    try:
        while emulator.running:
            print("Waiting for connection...")
            client_sock, client_info = server_sock.accept()
            print(f"Connected: {client_info}")

            try:
                handle_client(emulator, client_sock)
            except Exception as e:
                print(f"Client error: {e}")
            finally:
                client_sock.close()
                print("Client disconnected")

    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        server_sock.close()


def run_tcp_server(emulator: ELM327Emulator, port: int):
    """Run TCP server (for Network VCI testing)"""
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind(('0.0.0.0', port))
    server_sock.listen(1)

    print(f"TCP ELM327 Emulator")
    print(f"===================")
    print(f"Listening on port {port}")
    print(f"Connect using OpenDiag's Network VCI option")
    print(f"Address: <this-machine-ip>:{port}")
    print()

    emulator.running = True

    # Start update thread
    def update_loop():
        while emulator.running:
            emulator.update_simulation()
            time.sleep(0.1)

    update_thread = threading.Thread(target=update_loop, daemon=True)
    update_thread.start()

    try:
        while emulator.running:
            print("Waiting for connection...")
            client_sock, client_addr = server_sock.accept()
            print(f"Connected: {client_addr}")

            try:
                handle_client(emulator, client_sock)
            except Exception as e:
                print(f"Client error: {e}")
            finally:
                client_sock.close()
                print("Client disconnected")

    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        server_sock.close()


def run_serial_server(emulator: ELM327Emulator, port: str):
    """Run on serial port (for virtual COM ports or direct serial)"""
    if not SERIAL_AVAILABLE:
        print("Error: pyserial not available. Install with: pip install pyserial")
        sys.exit(1)

    ser = serial.Serial(port, 38400, timeout=0.1)

    print(f"Serial ELM327 Emulator")
    print(f"======================")
    print(f"Running on {port}")
    print()

    emulator.running = True

    # Start update thread
    def update_loop():
        while emulator.running:
            emulator.update_simulation()
            time.sleep(0.1)

    update_thread = threading.Thread(target=update_loop, daemon=True)
    update_thread.start()

    buffer = ""

    try:
        while emulator.running:
            if ser.in_waiting:
                data = ser.read(ser.in_waiting).decode('ascii', errors='ignore')
                buffer += data

                # Process complete commands (ending with \r)
                while '\r' in buffer:
                    cmd, buffer = buffer.split('\r', 1)
                    if cmd:
                        print(f"RX: {repr(cmd)}")
                        response = emulator.process_command(cmd)
                        print(f"TX: {repr(response)}")
                        ser.write(response.encode('ascii'))
            else:
                time.sleep(0.01)

    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        ser.close()


def handle_client(emulator: ELM327Emulator, sock):
    """Handle client connection"""
    buffer = ""

    # Send initial prompt
    sock.send(b">")

    while emulator.running:
        try:
            data = sock.recv(1024)
            if not data:
                break

            buffer += data.decode('ascii', errors='ignore')

            # Process complete commands
            while '\r' in buffer:
                cmd, buffer = buffer.split('\r', 1)
                if cmd:
                    print(f"RX: {repr(cmd)}")
                    response = emulator.process_command(cmd)
                    print(f"TX: {repr(response)}")
                    sock.send(response.encode('ascii'))

        except socket.timeout:
            continue
        except Exception as e:
            print(f"Error: {e}")
            break


def interactive_mode(emulator: ELM327Emulator):
    """Run interactive command line for testing"""
    print("Interactive ELM327 Emulator")
    print("===========================")
    print("Type ELM327 commands (AT, OBD-II) and see responses.")
    print("Type 'set rpm 2500' to change vehicle values.")
    print("Type 'status' to see current values.")
    print("Type 'quit' to exit.")
    print()

    while True:
        try:
            cmd = input("ELM> ").strip()

            if not cmd:
                continue

            if cmd.lower() == 'quit':
                break

            if cmd.lower() == 'status':
                print(f"RPM: {emulator.vehicle.rpm}")
                print(f"Speed: {emulator.vehicle.speed} km/h")
                print(f"Coolant: {emulator.vehicle.coolant_temp}C")
                print(f"Load: {emulator.vehicle.engine_load}%")
                print(f"Throttle: {emulator.vehicle.throttle}%")
                print(f"Fuel: {emulator.vehicle.fuel_level}%")
                print(f"Voltage: {emulator.vehicle.voltage:.1f}V")
                print(f"DTCs: {emulator.vehicle.stored_dtcs}")
                print(f"MIL: {'ON' if emulator.vehicle.mil_on else 'OFF'}")
                continue

            if cmd.lower().startswith('set '):
                parts = cmd.split()
                if len(parts) >= 3:
                    param = parts[1].lower()
                    value = parts[2]

                    if param == 'rpm':
                        emulator.vehicle.rpm = int(value)
                    elif param == 'speed':
                        emulator.vehicle.speed = int(value)
                    elif param == 'temp':
                        emulator.vehicle.coolant_temp = int(value)
                    elif param == 'load':
                        emulator.vehicle.engine_load = int(value)
                    elif param == 'throttle':
                        emulator.vehicle.throttle = int(value)
                    elif param == 'fuel':
                        emulator.vehicle.fuel_level = int(value)
                    elif param == 'dtc':
                        emulator.vehicle.stored_dtcs.append(value.upper())
                        emulator.vehicle.mil_on = True

                    print(f"Set {param} = {value}")
                continue

            if cmd.lower() == 'clear':
                emulator.vehicle.stored_dtcs = []
                emulator.vehicle.mil_on = False
                print("DTCs cleared")
                continue

            # Process as ELM327 command
            response = emulator.process_command(cmd)
            print(response)

        except EOFError:
            break
        except KeyboardInterrupt:
            break


def main():
    parser = argparse.ArgumentParser(description='Bluetooth ELM327 Emulator for OpenDiag')
    parser.add_argument('--bluetooth', '-b', action='store_true', help='Run Bluetooth SPP server (requires root on Linux)')
    parser.add_argument('--tcp', '-t', type=int, metavar='PORT', help='Run TCP server on specified port')
    parser.add_argument('--serial', '-s', metavar='PORT', help='Run on serial port (COM3, /dev/ttyUSB0, etc.)')
    parser.add_argument('--interactive', '-i', action='store_true', help='Interactive command-line mode')

    args = parser.parse_args()

    emulator = ELM327Emulator()

    if args.bluetooth:
        run_bluetooth_server(emulator)
    elif args.tcp:
        run_tcp_server(emulator, args.tcp)
    elif args.serial:
        run_serial_server(emulator, args.serial)
    elif args.interactive:
        interactive_mode(emulator)
    else:
        # Default: try Bluetooth, fall back to TCP
        if BLUETOOTH_AVAILABLE:
            print("No mode specified. Use --bluetooth, --tcp, --serial, or --interactive")
            print()
            print("Examples:")
            print("  sudo python elm327_emulator.py --bluetooth    # Bluetooth SPP")
            print("  python elm327_emulator.py --tcp 35000         # TCP server")
            print("  python elm327_emulator.py --serial COM3       # Serial port")
            print("  python elm327_emulator.py --interactive       # Command line test")
        else:
            print("PyBluez not available. Running TCP server on port 35000...")
            print("Connect using OpenDiag Network VCI option.")
            run_tcp_server(emulator, 35000)


if __name__ == '__main__':
    main()
