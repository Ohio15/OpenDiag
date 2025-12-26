#!/usr/bin/env python3
"""
Autel J2534 Protocol Analyzer
Analyzes captured Bluetooth traffic to reverse engineer the proprietary protocol
"""

import struct
import sys
from collections import defaultdict

BTSNOOP_MAGIC = b'btsnoop\x00'
BTSNOOP_HEADER_SIZE = 16
RECORD_HEADER_SIZE = 24

# Autel protocol magic bytes
AUTEL_MAGIC = b'\x55\x55\xAA\xAA'

def parse_btsnoop(filename):
    """Parse BTSnoop file with datalink 1001 handling"""
    with open(filename, 'rb') as f:
        header = f.read(BTSNOOP_HEADER_SIZE)
        if not header.startswith(BTSNOOP_MAGIC):
            return []

        packets = []
        while True:
            rec_header = f.read(RECORD_HEADER_SIZE)
            if len(rec_header) < RECORD_HEADER_SIZE:
                break

            orig_len, incl_len, flags, drops, timestamp = struct.unpack('>IIIIQ', rec_header)
            data = f.read(incl_len)
            if len(data) < incl_len:
                break

            direction = "RX" if (flags & 1) else "TX"
            is_cmd_event = bool(flags & 2)
            pkt_type = 'EVENT' if is_cmd_event and (flags & 1) else 'COMMAND' if is_cmd_event else 'ACL'

            packets.append({
                'timestamp': timestamp,
                'direction': direction,
                'type': pkt_type,
                'data': data
            })

        return packets

def extract_rfcomm_data(packets):
    """Extract RFCOMM payload from ACL packets"""
    rfcomm_packets = []

    for pkt in packets:
        if pkt['type'] != 'ACL':
            continue

        data = pkt['data']
        if len(data) < 8:
            continue

        # ACL header
        acl_len = struct.unpack('<H', data[2:4])[0]
        if len(data) < 4 + acl_len:
            continue

        # L2CAP header
        acl_payload = data[4:4+acl_len]
        if len(acl_payload) < 4:
            continue

        l2cap_cid = struct.unpack('<H', acl_payload[2:4])[0]
        l2cap_data = acl_payload[4:]

        # Only dynamic channels (RFCOMM)
        if l2cap_cid < 0x0040:
            continue

        # RFCOMM UIH frame
        if len(l2cap_data) < 3:
            continue

        addr = l2cap_data[0]
        control = l2cap_data[1]
        dlci = addr >> 2

        # UIH frame check
        if (control & 0xEF) != 0xEF:
            continue

        length_byte = l2cap_data[2]
        if length_byte & 1:
            payload_len = length_byte >> 1
            payload_start = 3
        else:
            if len(l2cap_data) < 4:
                continue
            payload_len = (length_byte >> 1) | (l2cap_data[3] << 7)
            payload_start = 4

        if len(l2cap_data) >= payload_start + payload_len and payload_len > 0:
            payload = l2cap_data[payload_start:payload_start + payload_len]
            rfcomm_packets.append({
                'timestamp': pkt['timestamp'],
                'direction': pkt['direction'],
                'dlci': dlci,
                'data': payload
            })

    return rfcomm_packets

def analyze_autel_packet(data, direction):
    """Analyze a single Autel protocol packet"""
    result = {'valid': False}

    # Check for magic bytes
    if direction == 'TX':
        if not data.startswith(AUTEL_MAGIC):
            return result
        offset = 4
    else:  # RX packets have leading 0x00
        if len(data) < 5:
            return result
        if data[0:1] == b'\x00' and data[1:5] == AUTEL_MAGIC:
            offset = 5
        elif data.startswith(AUTEL_MAGIC):
            offset = 4
        else:
            return result

    if len(data) < offset + 36:  # Minimum packet size
        result['valid'] = True
        result['short'] = True
        result['raw'] = data.hex().upper()
        return result

    result['valid'] = True
    result['short'] = False

    # Parse packet header
    # Format appears to be:
    # - 4 bytes: Magic (5555AAAA)
    # - 4 bytes: Total length (little-endian)
    # - 8 bytes: Session/Message ID (changes per message)
    # - 4 bytes: Payload length
    # - 8 bytes: Same as bytes 8-16
    # - 4 bytes: Flags? (FFFFFFFF common)
    # - 4 bytes: Command/Status
    # - 4 bytes: Subcommand/Parameter
    # - N bytes: Data payload
    # - 4 bytes: Checksum (CRC32?)

    try:
        total_len = struct.unpack('<I', data[offset:offset+4])[0]
        msg_id1 = data[offset+4:offset+12].hex().upper()
        payload_len = struct.unpack('<I', data[offset+12:offset+16])[0]
        msg_id2 = data[offset+16:offset+24].hex().upper()
        flags = struct.unpack('<I', data[offset+24:offset+28])[0]
        cmd1 = struct.unpack('<I', data[offset+28:offset+32])[0]
        cmd2 = struct.unpack('<I', data[offset+32:offset+36])[0]

        result['total_len'] = total_len
        result['msg_id'] = msg_id1
        result['payload_len'] = payload_len
        result['flags'] = flags
        result['cmd1'] = cmd1
        result['cmd2'] = cmd2

        # Extract payload data
        if len(data) > offset + 36:
            payload_data = data[offset+36:]
            result['payload'] = payload_data

            # Try to identify payload content
            if payload_data:
                # Check for ASCII strings
                try:
                    ascii_str = payload_data.decode('ascii', errors='ignore')
                    printable = ''.join(c if 32 <= ord(c) < 127 else '' for c in ascii_str)
                    if len(printable) > 3:
                        result['ascii'] = printable.strip()
                except:
                    pass

    except Exception as e:
        result['error'] = str(e)

    return result

def classify_command(cmd1, cmd2, payload):
    """Classify the command type based on cmd1/cmd2 values"""
    # Known command classifications based on analysis
    if cmd1 == 0 and cmd2 == 0:
        return "STATUS/ACK"
    elif cmd1 == 1 and cmd2 == 4:
        return "CONNECT_REQUEST"
    elif cmd1 == 0x0B:
        return "GET_VERSION"
    elif cmd1 == 3:
        return "DISCONNECT"

    # Check payload for clues
    if payload:
        payload_hex = payload.hex().upper()
        if 'J2534' in str(payload):
            return "J2534_ID"
        if '4D617220' in payload_hex:  # "Mar " in hex
            return "FIRMWARE_INFO"

    return f"CMD_{cmd1:02X}_{cmd2:02X}"

def main():
    filename = sys.argv[1] if len(sys.argv) > 1 else r"E:\btsnoop_hci.log"

    print(f"Analyzing: {filename}")
    print('='*80)

    packets = parse_btsnoop(filename)
    print(f"Total HCI packets: {len(packets)}")

    rfcomm_packets = extract_rfcomm_data(packets)
    print(f"RFCOMM packets: {len(rfcomm_packets)}")

    # Filter to DLCI 12 (main data channel)
    dlci12_packets = [p for p in rfcomm_packets if p['dlci'] == 12]
    print(f"DLCI 12 packets: {len(dlci12_packets)}")

    print(f"\n{'='*80}")
    print("AUTEL PROTOCOL PACKET ANALYSIS")
    print('='*80)

    # Analyze packet structure
    cmd_stats = defaultdict(lambda: {'count': 0, 'tx': 0, 'rx': 0, 'examples': []})

    for i, pkt in enumerate(dlci12_packets):
        analysis = analyze_autel_packet(pkt['data'], pkt['direction'])

        if not analysis['valid']:
            continue

        if analysis.get('short'):
            continue

        cmd_type = classify_command(
            analysis.get('cmd1', 0),
            analysis.get('cmd2', 0),
            analysis.get('payload', b'')
        )

        key = f"{analysis.get('cmd1', 0):02X}:{analysis.get('cmd2', 0):02X}"
        cmd_stats[key]['count'] += 1
        cmd_stats[key][pkt['direction'].lower()] += 1
        cmd_stats[key]['type'] = cmd_type

        if len(cmd_stats[key]['examples']) < 3:
            cmd_stats[key]['examples'].append({
                'direction': pkt['direction'],
                'data': pkt['data'][:100].hex().upper(),
                'ascii': analysis.get('ascii', '')
            })

    print("\nCommand Type Statistics:")
    print("-"*80)
    print(f"{'CMD':8} {'Type':20} {'Count':>8} {'TX':>8} {'RX':>8}")
    print("-"*80)

    for cmd, stats in sorted(cmd_stats.items()):
        print(f"{cmd:8} {stats['type']:20} {stats['count']:8d} {stats['tx']:8d} {stats['rx']:8d}")

    # Show first few complete packets for protocol documentation
    print(f"\n{'='*80}")
    print("SAMPLE PACKETS FOR PROTOCOL DOCUMENTATION")
    print('='*80)

    sample_count = 0
    for pkt in dlci12_packets[:100]:
        if sample_count >= 20:
            break

        analysis = analyze_autel_packet(pkt['data'], pkt['direction'])
        if not analysis['valid'] or analysis.get('short'):
            continue

        sample_count += 1
        print(f"\n--- Packet {sample_count} ({pkt['direction']}) ---")
        print(f"Total Length: {analysis.get('total_len', 'N/A')}")
        print(f"Message ID:   {analysis.get('msg_id', 'N/A')}")
        print(f"Payload Len:  {analysis.get('payload_len', 'N/A')}")
        print(f"Flags:        0x{analysis.get('flags', 0):08X}")
        print(f"Command 1:    0x{analysis.get('cmd1', 0):08X}")
        print(f"Command 2:    0x{analysis.get('cmd2', 0):08X}")
        if analysis.get('ascii'):
            print(f"ASCII:        {analysis['ascii'][:60]}")
        print(f"Raw (first 80): {pkt['data'].hex().upper()[:160]}")

    # Extract unique strings from payloads
    print(f"\n{'='*80}")
    print("UNIQUE STRINGS FOUND IN PROTOCOL")
    print('='*80)

    strings_found = set()
    for pkt in dlci12_packets:
        analysis = analyze_autel_packet(pkt['data'], pkt['direction'])
        if analysis.get('ascii'):
            # Split on common delimiters and filter
            parts = analysis['ascii'].replace('\x00', ' ').split()
            for part in parts:
                if len(part) >= 4 and part.isascii():
                    strings_found.add(part)

    for s in sorted(strings_found):
        if len(s) > 3:
            print(f"  {s}")

if __name__ == '__main__':
    main()
