#!/usr/bin/env python3
"""
BTSnoop HCI Log Parser for OBD2 Protocol Analysis
Parses Android btsnoop_hci.log files to extract Bluetooth SPP/RFCOMM data
"""

import struct
import sys
from datetime import datetime, timedelta

# BTSnoop header format
BTSNOOP_MAGIC = b'btsnoop\x00'
BTSNOOP_HEADER_SIZE = 16
RECORD_HEADER_SIZE = 24

# HCI packet types
HCI_COMMAND = 0x01
HCI_ACL_DATA = 0x02
HCI_SCO_DATA = 0x03
HCI_EVENT = 0x04

# L2CAP channel IDs
L2CAP_SIGNALING_CID = 0x0001
L2CAP_CONNECTIONLESS_CID = 0x0002

def parse_btsnoop(filename):
    """Parse BTSnoop file and extract packets"""
    with open(filename, 'rb') as f:
        # Read header
        header = f.read(BTSNOOP_HEADER_SIZE)
        if not header.startswith(BTSNOOP_MAGIC):
            print("Not a valid BTSnoop file")
            return []

        version = struct.unpack('>I', header[8:12])[0]
        datalink = struct.unpack('>I', header[12:16])[0]
        print(f"BTSnoop Version: {version}, Datalink: {datalink}")

        packets = []
        packet_num = 0

        while True:
            # Read record header
            rec_header = f.read(RECORD_HEADER_SIZE)
            if len(rec_header) < RECORD_HEADER_SIZE:
                break

            orig_len, incl_len, flags, drops, timestamp = struct.unpack('>IIIIQ', rec_header)

            # Read packet data
            data = f.read(incl_len)
            if len(data) < incl_len:
                break

            packet_num += 1

            # Determine direction from flags
            # Bit 0: 0 = sent, 1 = received
            # Bit 1: 0 = data, 1 = command/event
            direction = "RX" if (flags & 1) else "TX"
            is_command = bool(flags & 2)

            packets.append({
                'num': packet_num,
                'timestamp': timestamp,
                'direction': direction,
                'is_command': is_command,
                'data': data,
                'flags': flags
            })

        return packets

def extract_l2cap_data(packets):
    """Extract L2CAP payload data from ACL packets"""
    l2cap_data = []

    for pkt in packets:
        data = pkt['data']
        if len(data) < 1:
            continue

        # First byte is HCI packet type indicator
        pkt_type = data[0]

        if pkt_type == HCI_ACL_DATA and len(data) > 5:
            # ACL header: handle (2 bytes), length (2 bytes)
            handle = struct.unpack('<H', data[1:3])[0] & 0x0FFF
            acl_len = struct.unpack('<H', data[3:5])[0]

            if len(data) >= 5 + acl_len and acl_len >= 4:
                # L2CAP header: length (2 bytes), channel ID (2 bytes)
                l2cap_payload = data[5:5+acl_len]
                l2cap_len = struct.unpack('<H', l2cap_payload[0:2])[0]
                l2cap_cid = struct.unpack('<H', l2cap_payload[2:4])[0]

                if len(l2cap_payload) >= 4 + l2cap_len:
                    payload = l2cap_payload[4:4+l2cap_len]

                    l2cap_data.append({
                        'num': pkt['num'],
                        'direction': pkt['direction'],
                        'handle': handle,
                        'cid': l2cap_cid,
                        'payload': payload
                    })

    return l2cap_data

def extract_rfcomm_data(l2cap_packets):
    """Extract RFCOMM payload from L2CAP packets"""
    rfcomm_data = []

    for pkt in l2cap_packets:
        payload = pkt['payload']
        cid = pkt['cid']

        # Skip signaling channel
        if cid <= 0x0003:
            continue

        if len(payload) < 3:
            continue

        # RFCOMM header
        addr = payload[0]
        control = payload[1]

        # Check if this is UIH frame (data frame)
        if (control & 0xEF) == 0xEF:  # UIH frame
            # Get length
            length_byte = payload[2]
            if length_byte & 1:  # 1 byte length
                data_len = length_byte >> 1
                data_start = 3
            else:  # 2 byte length
                if len(payload) < 4:
                    continue
                data_len = (length_byte >> 1) | (payload[3] << 7)
                data_start = 4

            if len(payload) >= data_start + data_len:
                rfcomm_payload = payload[data_start:data_start + data_len]

                # Extract DLCI (channel)
                dlci = addr >> 2

                if data_len > 0:
                    rfcomm_data.append({
                        'num': pkt['num'],
                        'direction': pkt['direction'],
                        'dlci': dlci,
                        'data': rfcomm_payload
                    })

    return rfcomm_data

def analyze_obd2_protocol(rfcomm_packets):
    """Analyze RFCOMM data for OBD2 protocol patterns"""
    print("\n" + "="*60)
    print("OBD2 PROTOCOL ANALYSIS")
    print("="*60)

    conversations = []
    current_tx = None

    for pkt in rfcomm_packets:
        data = pkt['data']
        direction = pkt['direction']

        # Try to decode as ASCII
        try:
            ascii_data = data.decode('ascii', errors='replace')
            ascii_printable = ''.join(c if 32 <= ord(c) < 127 else '.' for c in ascii_data)
        except:
            ascii_printable = ''

        hex_data = data.hex().upper()

        print(f"\n[{pkt['num']:4d}] {direction} DLCI={pkt['dlci']:2d} Len={len(data):3d}")
        print(f"       HEX: {hex_data[:80]}{'...' if len(hex_data) > 80 else ''}")
        if ascii_printable.strip():
            print(f"       ASCII: {ascii_printable[:80]}")

        # Look for common OBD2 patterns
        if b'AT' in data:
            print(f"       >>> AT COMMAND DETECTED")
        if any(x in data for x in [b'41 ', b'41', b'\x41']):
            print(f"       >>> POSSIBLE OBD2 RESPONSE")
        if data.startswith(b'\xaa') or data.startswith(b'\x55'):
            print(f"       >>> SYNC/HEADER BYTE DETECTED")

def main():
    if len(sys.argv) < 2:
        filename = r"E:\btsnoop_hci.log"
    else:
        filename = sys.argv[1]

    print(f"Parsing: {filename}")
    print("="*60)

    # Parse BTSnoop file
    packets = parse_btsnoop(filename)
    print(f"Total HCI packets: {len(packets)}")

    # Extract L2CAP data
    l2cap_packets = extract_l2cap_data(packets)
    print(f"L2CAP data packets: {len(l2cap_packets)}")

    # Extract RFCOMM data
    rfcomm_packets = extract_rfcomm_data(l2cap_packets)
    print(f"RFCOMM data packets: {len(rfcomm_packets)}")

    # Analyze OBD2 protocol
    if rfcomm_packets:
        analyze_obd2_protocol(rfcomm_packets)
    else:
        print("\nNo RFCOMM data found. Looking at raw L2CAP data...")
        for pkt in l2cap_packets[:50]:
            print(f"[{pkt['num']:4d}] {pkt['direction']} CID={pkt['cid']:04X} Data={pkt['payload'].hex()[:60]}")

if __name__ == '__main__':
    main()
