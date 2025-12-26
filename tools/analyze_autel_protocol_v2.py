#!/usr/bin/env python3
"""
Autel J2534 Protocol Analyzer v2
Detailed analysis of the proprietary Autel Bluetooth OBD2 protocol
"""

import struct
import sys
from collections import defaultdict
import binascii

BTSNOOP_MAGIC = b'btsnoop\x00'
BTSNOOP_HEADER_SIZE = 16
RECORD_HEADER_SIZE = 24
AUTEL_MAGIC = b'\x55\x55\xAA\xAA'

def parse_btsnoop(filename):
    """Parse BTSnoop file"""
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
            pkt_type = 'EVENT' if (flags & 2) and (flags & 1) else 'COMMAND' if (flags & 2) else 'ACL'
            packets.append({'timestamp': timestamp, 'direction': direction, 'type': pkt_type, 'data': data})
        return packets

def extract_rfcomm_data(packets):
    """Extract RFCOMM payload"""
    rfcomm_packets = []
    for pkt in packets:
        if pkt['type'] != 'ACL':
            continue
        data = pkt['data']
        if len(data) < 8:
            continue

        acl_len = struct.unpack('<H', data[2:4])[0]
        if len(data) < 4 + acl_len:
            continue

        acl_payload = data[4:4+acl_len]
        if len(acl_payload) < 4:
            continue

        l2cap_cid = struct.unpack('<H', acl_payload[2:4])[0]
        l2cap_data = acl_payload[4:]

        if l2cap_cid < 0x0040 or len(l2cap_data) < 3:
            continue

        addr = l2cap_data[0]
        control = l2cap_data[1]
        dlci = addr >> 2

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

def parse_autel_packet(data, direction):
    """Parse Autel protocol packet structure"""
    result = {'valid': False, 'direction': direction}

    # Find magic bytes
    if direction == 'TX':
        if not data.startswith(AUTEL_MAGIC):
            return result
        offset = 0
    else:
        if data.startswith(b'\x00' + AUTEL_MAGIC):
            offset = 1
        elif data.startswith(AUTEL_MAGIC):
            offset = 0
        else:
            return result

    if len(data) < offset + 40:
        result['valid'] = True
        result['short'] = True
        return result

    result['valid'] = True
    result['short'] = False

    # Parse header structure:
    # Offset+0:  4 bytes - Magic (5555AAAA)
    # Offset+4:  4 bytes - Total packet length (LE)
    # Offset+8:  4 bytes - Session ID
    # Offset+12: 4 bytes - Message counter/timestamp
    # Offset+16: 4 bytes - Payload data length (LE)
    # Offset+20: 4 bytes - Session ID (repeated)
    # Offset+24: 4 bytes - Flags (usually FFFFFFFF)
    # Offset+28: 4 bytes - Status/Result (0 = OK)
    # Offset+32: 4 bytes - Padding/Reserved
    # Offset+36: N bytes - Payload data
    # Last 4 bytes: CRC32

    try:
        magic = data[offset:offset+4]
        total_len = struct.unpack('<I', data[offset+4:offset+8])[0]
        session_id = struct.unpack('<I', data[offset+8:offset+12])[0]
        msg_counter = struct.unpack('<I', data[offset+12:offset+16])[0]
        payload_len = struct.unpack('<I', data[offset+16:offset+20])[0]
        session_id2 = struct.unpack('<I', data[offset+20:offset+24])[0]
        flags = struct.unpack('<I', data[offset+24:offset+28])[0]
        status = struct.unpack('<I', data[offset+28:offset+32])[0]
        reserved = struct.unpack('<I', data[offset+32:offset+36])[0]

        result['total_len'] = total_len
        result['session_id'] = session_id
        result['msg_counter'] = msg_counter
        result['payload_len'] = payload_len
        result['flags'] = flags
        result['status'] = status
        result['reserved'] = reserved

        # Extract payload
        payload_start = offset + 36
        payload_end = offset + 4 + total_len - 4  # minus CRC
        if payload_end > payload_start and payload_end <= len(data):
            payload = data[payload_start:payload_end]
            result['payload'] = payload
            result['payload_hex'] = payload.hex().upper()

            # CRC at end
            if payload_end + 4 <= len(data):
                crc = struct.unpack('<I', data[payload_end:payload_end+4])[0]
                result['crc'] = crc

            # Try ASCII decode
            try:
                ascii_str = payload.decode('ascii', errors='ignore')
                printable = ''.join(c if 32 <= ord(c) < 127 else '' for c in ascii_str)
                if len(printable) > 3:
                    result['ascii'] = printable.strip()
            except:
                pass

    except Exception as e:
        result['error'] = str(e)

    return result

def identify_message_type(pkt_data, direction):
    """Identify the message type based on content"""
    if pkt_data.get('ascii'):
        ascii_content = pkt_data['ascii']
        if 'J2534' in ascii_content:
            return 'DEVICE_ID_RESPONSE' if direction == 'RX' else 'DEVICE_ID_REQUEST'
        if 'AUTEL' in ascii_content:
            return 'VENDOR_ID_RESPONSE'
        if 'Mar ' in ascii_content or 'V2.' in ascii_content:
            return 'FIRMWARE_VERSION_RESPONSE'
        if 'MAXI' in ascii_content:
            return 'DEVICE_NAME'

    status = pkt_data.get('status', 0)
    reserved = pkt_data.get('reserved', 0)

    # Check payload patterns
    payload = pkt_data.get('payload', b'')
    if payload:
        # Check for specific patterns
        if payload.startswith(b'\x5E\x01\x00\x00'):
            return 'PASSTHRU_OPEN_RESPONSE'
        if len(payload) >= 4:
            first_word = struct.unpack('<I', payload[:4])[0]
            if first_word == 0x0000015E:
                return 'PASSTHRU_RESPONSE'

    # Based on status/command patterns
    if direction == 'TX':
        if status == 0 and reserved == 0:
            return 'CONNECT_REQUEST'
        if status == 1 and reserved == 4:
            return 'PASSTHRU_OPEN'
        if status == 1 and reserved == 3:
            return 'PASSTHRU_CLOSE'
        if status == 0x0B:
            return 'GET_VERSION'
        if status == 0x02:
            return 'READ_DATA'
        if status == 0x05:
            return 'WRITE_DATA'
        if status == 0x08:
            return 'START_MSG_FILTER'
        if status == 0x03:
            return 'DISCONNECT'
    else:
        if status == 0:
            return 'SUCCESS_RESPONSE'

    return f"CMD_{status:02X}_{reserved:02X}"

def main():
    filename = sys.argv[1] if len(sys.argv) > 1 else r"E:\btsnoop_hci.log"

    print("="*80)
    print("AUTEL J2534 BLUETOOTH PROTOCOL ANALYSIS")
    print("="*80)
    print(f"\nFile: {filename}\n")

    packets = parse_btsnoop(filename)
    rfcomm_packets = extract_rfcomm_data(packets)
    dlci12_packets = [p for p in rfcomm_packets if p['dlci'] == 12]

    print(f"Total DLCI 12 packets: {len(dlci12_packets)}")

    # Group into request/response pairs by session ID
    sessions = defaultdict(list)
    parsed_packets = []

    for pkt in dlci12_packets:
        parsed = parse_autel_packet(pkt['data'], pkt['direction'])
        if parsed['valid'] and not parsed.get('short'):
            parsed['timestamp'] = pkt['timestamp']
            parsed['raw'] = pkt['data']
            parsed_packets.append(parsed)
            session_id = parsed.get('session_id', 0)
            sessions[session_id].append(parsed)

    print(f"Parsed Autel packets: {len(parsed_packets)}")
    print(f"Unique sessions: {len(sessions)}")

    # Show first 30 packets in detail
    print("\n" + "="*80)
    print("FIRST 30 PACKETS (REQUEST/RESPONSE PAIRS)")
    print("="*80)

    shown = 0
    for pkt in parsed_packets[:60]:
        if shown >= 30:
            break
        shown += 1

        msg_type = identify_message_type(pkt, pkt['direction'])

        print(f"\n--- Packet {shown} ({pkt['direction']}) ---")
        print(f"  Type:         {msg_type}")
        print(f"  Session ID:   0x{pkt.get('session_id', 0):08X}")
        print(f"  Msg Counter:  0x{pkt.get('msg_counter', 0):08X}")
        print(f"  Total Len:    {pkt.get('total_len', 0)}")
        print(f"  Payload Len:  {pkt.get('payload_len', 0)}")
        print(f"  Status:       0x{pkt.get('status', 0):08X}")
        print(f"  Reserved:     0x{pkt.get('reserved', 0):08X}")
        if pkt.get('ascii'):
            print(f"  ASCII:        {pkt['ascii'][:70]}")
        if pkt.get('payload'):
            print(f"  Payload HEX:  {pkt['payload'][:40].hex().upper()}")

    # Analyze message type distribution
    print("\n" + "="*80)
    print("MESSAGE TYPE DISTRIBUTION")
    print("="*80)

    msg_types = defaultdict(lambda: {'count': 0, 'tx': 0, 'rx': 0})
    for pkt in parsed_packets:
        msg_type = identify_message_type(pkt, pkt['direction'])
        msg_types[msg_type]['count'] += 1
        msg_types[msg_type][pkt['direction'].lower()] += 1

    print(f"\n{'Message Type':<30} {'Count':>8} {'TX':>8} {'RX':>8}")
    print("-"*60)
    for msg_type, stats in sorted(msg_types.items(), key=lambda x: -x[1]['count']):
        print(f"{msg_type:<30} {stats['count']:8d} {stats['tx']:8d} {stats['rx']:8d}")

    # Protocol documentation
    print("\n" + "="*80)
    print("PROTOCOL SPECIFICATION SUMMARY")
    print("="*80)

    print("""
AUTEL J2534 BLUETOOTH PROTOCOL
==============================

PACKET STRUCTURE:
-----------------
Offset  Size  Field
------  ----  -----
0       4     Magic: 0x5555AAAA (TX) or 0x005555AAAA (RX)
4       4     Total Length (little-endian)
8       4     Session ID (matches in request/response pair)
12      4     Message Counter/Timestamp
16      4     Payload Data Length (little-endian)
20      4     Session ID (repeated)
24      4     Flags (usually 0xFFFFFFFF)
28      4     Command/Status Code
32      4     Subcommand/Parameter
36      N     Payload Data
36+N    4     CRC32 Checksum

KNOWN COMMANDS (TX):
--------------------
0x00, 0x00  - Connect/Identify request
0x01, 0x04  - PassThruOpen (open J2534 channel)
0x01, 0x03  - PassThruClose (close channel)
0x02, 0x01  - PassThruReadMsgs
0x02, 0x02  - PassThruWriteMsgs
0x02, 0x03  - PassThruStartMsgFilter
0x02, 0x8003- PassThruStopMsgFilter
0x02, 0x8005- PassThruSetProgrammingVoltage
0x05, 0x00  - PassThruConnect
0x05, 0x80000001 - PassThruDisconnect
0x08, 0x01  - PassThruIoctl
0x08, 0x03  - PassThruReadVersion
0x0B, *     - GetFirmwareVersion

RESPONSE STRUCTURE:
-------------------
- Status 0x00 = Success
- Payload contains response data
- For firmware: "Mar DD YYYY HH:MM:SS  V2.XX"

TRANSPORT:
----------
- Bluetooth Classic SPP over RFCOMM
- DLCI channel 12
- Device name: "Maxi-CFJMMAC3989" (varies by unit)
- BT module: Microchip BM78
""")

    # Export unique payloads for further analysis
    print("\n" + "="*80)
    print("SAMPLE PAYLOAD DATA FOR PROTOCOL IMPLEMENTATION")
    print("="*80)

    # Show example of each message type
    seen_types = set()
    for pkt in parsed_packets:
        msg_type = identify_message_type(pkt, pkt['direction'])
        if msg_type not in seen_types and pkt.get('payload'):
            seen_types.add(msg_type)
            print(f"\n{msg_type} ({pkt['direction']}):")
            print(f"  Full packet: {pkt['raw'][:60].hex().upper()}...")
            if pkt.get('ascii'):
                print(f"  ASCII: {pkt['ascii']}")

if __name__ == '__main__':
    main()
