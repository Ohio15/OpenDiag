#!/usr/bin/env python3
"""
BTSnoop HCI Log Parser v2 - Handles both Classic and BLE
"""

import struct
import sys

BTSNOOP_MAGIC = b'btsnoop\x00'
BTSNOOP_HEADER_SIZE = 16
RECORD_HEADER_SIZE = 24

# HCI packet types
HCI_COMMAND = 0x01
HCI_ACL_DATA = 0x02
HCI_SCO_DATA = 0x03
HCI_EVENT = 0x04

def parse_btsnoop(filename):
    """Parse BTSnoop file"""
    with open(filename, 'rb') as f:
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
            rec_header = f.read(RECORD_HEADER_SIZE)
            if len(rec_header) < RECORD_HEADER_SIZE:
                break

            orig_len, incl_len, flags, drops, timestamp = struct.unpack('>IIIIQ', rec_header)
            data = f.read(incl_len)
            if len(data) < incl_len:
                break

            packet_num += 1
            direction = "RX" if (flags & 1) else "TX"

            packets.append({
                'num': packet_num,
                'timestamp': timestamp,
                'direction': direction,
                'flags': flags,
                'data': data
            })

        return packets

def analyze_packets(packets):
    """Analyze HCI packets"""
    stats = {'commands': 0, 'events': 0, 'acl': 0, 'sco': 0, 'other': 0}
    acl_packets = []

    for pkt in packets:
        data = pkt['data']
        if len(data) < 1:
            continue

        pkt_type = data[0]

        if pkt_type == HCI_COMMAND:
            stats['commands'] += 1
        elif pkt_type == HCI_EVENT:
            stats['events'] += 1
        elif pkt_type == HCI_ACL_DATA:
            stats['acl'] += 1
            acl_packets.append(pkt)
        elif pkt_type == HCI_SCO_DATA:
            stats['sco'] += 1
        else:
            stats['other'] += 1

    print(f"\nPacket Statistics:")
    print(f"  HCI Commands: {stats['commands']}")
    print(f"  HCI Events:   {stats['events']}")
    print(f"  ACL Data:     {stats['acl']}")
    print(f"  SCO Data:     {stats['sco']}")
    print(f"  Other:        {stats['other']}")

    return acl_packets

def extract_acl_data(packets):
    """Extract and analyze ACL data packets"""
    print(f"\n{'='*70}")
    print("ACL DATA PACKETS ANALYSIS")
    print('='*70)

    data_packets = []

    for pkt in packets:
        data = pkt['data']
        if len(data) < 5:
            continue

        # ACL header after HCI type byte
        handle_flags = struct.unpack('<H', data[1:3])[0]
        handle = handle_flags & 0x0FFF
        pb_flag = (handle_flags >> 12) & 0x03
        bc_flag = (handle_flags >> 14) & 0x03

        acl_len = struct.unpack('<H', data[3:5])[0]
        acl_payload = data[5:5+acl_len]

        if len(acl_payload) >= 4:
            # L2CAP header
            l2cap_len = struct.unpack('<H', acl_payload[0:2])[0]
            l2cap_cid = struct.unpack('<H', acl_payload[2:4])[0]
            l2cap_data = acl_payload[4:]

            data_packets.append({
                'num': pkt['num'],
                'direction': pkt['direction'],
                'handle': handle,
                'cid': l2cap_cid,
                'pb_flag': pb_flag,
                'l2cap_data': l2cap_data
            })

    # Analyze L2CAP channels
    channels = {}
    for pkt in data_packets:
        cid = pkt['cid']
        if cid not in channels:
            channels[cid] = {'count': 0, 'tx': 0, 'rx': 0}
        channels[cid]['count'] += 1
        channels[cid][pkt['direction'].lower()] += 1

    print(f"\nL2CAP Channels Found:")
    for cid, info in sorted(channels.items()):
        cid_name = get_cid_name(cid)
        print(f"  CID 0x{cid:04X} ({cid_name}): {info['count']} packets (TX:{info['tx']}, RX:{info['rx']})")

    return data_packets

def get_cid_name(cid):
    """Get L2CAP channel name"""
    names = {
        0x0001: 'L2CAP Signaling',
        0x0002: 'Connectionless',
        0x0003: 'AMP Manager',
        0x0004: 'ATT (BLE)',
        0x0005: 'L2CAP LE Signaling',
        0x0006: 'SMP (BLE Security)',
    }
    if cid in names:
        return names[cid]
    elif cid >= 0x0040:
        return 'Dynamic Channel'
    else:
        return 'Reserved'

def analyze_att_packets(data_packets):
    """Analyze BLE ATT (Attribute Protocol) packets"""
    print(f"\n{'='*70}")
    print("BLE ATT PROTOCOL ANALYSIS")
    print('='*70)

    att_packets = [p for p in data_packets if p['cid'] == 0x0004]

    if not att_packets:
        print("No ATT packets found")
        return []

    att_opcodes = {
        0x01: 'Error Response',
        0x02: 'Exchange MTU Request',
        0x03: 'Exchange MTU Response',
        0x04: 'Find Information Request',
        0x05: 'Find Information Response',
        0x06: 'Find By Type Value Request',
        0x07: 'Find By Type Value Response',
        0x08: 'Read By Type Request',
        0x09: 'Read By Type Response',
        0x0A: 'Read Request',
        0x0B: 'Read Response',
        0x0C: 'Read Blob Request',
        0x0D: 'Read Blob Response',
        0x10: 'Read By Group Type Request',
        0x11: 'Read By Group Type Response',
        0x12: 'Write Request',
        0x13: 'Write Response',
        0x16: 'Prepare Write Request',
        0x17: 'Prepare Write Response',
        0x18: 'Execute Write Request',
        0x19: 'Execute Write Response',
        0x1B: 'Handle Value Notification',
        0x1D: 'Handle Value Indication',
        0x1E: 'Handle Value Confirmation',
        0x52: 'Write Command',
        0xD2: 'Signed Write Command',
    }

    gatt_data = []

    for pkt in att_packets:
        data = pkt['l2cap_data']
        if len(data) < 1:
            continue

        opcode = data[0]
        opcode_name = att_opcodes.get(opcode, f'Unknown (0x{opcode:02X})')

        print(f"\n[{pkt['num']:4d}] {pkt['direction']} ATT: {opcode_name}")
        print(f"       Data: {data.hex().upper()}")

        # Extract handle and value for write/read operations
        if opcode in [0x12, 0x52] and len(data) >= 3:  # Write Request/Command
            handle = struct.unpack('<H', data[1:3])[0]
            value = data[3:]
            print(f"       Handle: 0x{handle:04X}, Value: {value.hex().upper()}")

            # Try ASCII decode
            try:
                ascii_val = value.decode('ascii', errors='replace')
                printable = ''.join(c if 32 <= ord(c) < 127 else '.' for c in ascii_val)
                if printable.strip():
                    print(f"       ASCII: {printable}")
            except:
                pass

            gatt_data.append({
                'num': pkt['num'],
                'direction': pkt['direction'],
                'opcode': 'WRITE',
                'handle': handle,
                'value': value
            })

        elif opcode == 0x1B and len(data) >= 3:  # Handle Value Notification
            handle = struct.unpack('<H', data[1:3])[0]
            value = data[3:]
            print(f"       Handle: 0x{handle:04X}, Value: {value.hex().upper()}")

            try:
                ascii_val = value.decode('ascii', errors='replace')
                printable = ''.join(c if 32 <= ord(c) < 127 else '.' for c in ascii_val)
                if printable.strip():
                    print(f"       ASCII: {printable}")
            except:
                pass

            gatt_data.append({
                'num': pkt['num'],
                'direction': pkt['direction'],
                'opcode': 'NOTIFY',
                'handle': handle,
                'value': value
            })

        elif opcode == 0x0B and len(data) >= 1:  # Read Response
            value = data[1:]
            print(f"       Value: {value.hex().upper()}")

            try:
                ascii_val = value.decode('ascii', errors='replace')
                printable = ''.join(c if 32 <= ord(c) < 127 else '.' for c in ascii_val)
                if printable.strip():
                    print(f"       ASCII: {printable}")
            except:
                pass

    return gatt_data

def analyze_dynamic_channels(data_packets):
    """Analyze dynamic L2CAP channels (RFCOMM, etc)"""
    print(f"\n{'='*70}")
    print("DYNAMIC CHANNEL DATA ANALYSIS")
    print('='*70)

    dynamic_packets = [p for p in data_packets if p['cid'] >= 0x0040]

    if not dynamic_packets:
        print("No dynamic channel data found")
        return

    for pkt in dynamic_packets[:100]:  # Limit output
        data = pkt['l2cap_data']
        print(f"\n[{pkt['num']:4d}] {pkt['direction']} CID=0x{pkt['cid']:04X} Len={len(data)}")
        print(f"       HEX: {data.hex().upper()[:100]}")

        try:
            ascii_val = data.decode('ascii', errors='replace')
            printable = ''.join(c if 32 <= ord(c) < 127 else '.' for c in ascii_val)
            if printable.strip():
                print(f"       ASCII: {printable[:100]}")
        except:
            pass

def main():
    filename = sys.argv[1] if len(sys.argv) > 1 else r"E:\btsnoop_hci.log"

    print(f"Parsing: {filename}")
    print('='*70)

    packets = parse_btsnoop(filename)
    print(f"Total HCI packets: {len(packets)}")

    acl_packets = analyze_packets(packets)

    if acl_packets:
        data_packets = extract_acl_data(acl_packets)

        # Check for BLE ATT
        att_count = sum(1 for p in data_packets if p['cid'] == 0x0004)
        if att_count > 0:
            analyze_att_packets(data_packets)

        # Check dynamic channels
        dynamic_count = sum(1 for p in data_packets if p['cid'] >= 0x0040)
        if dynamic_count > 0:
            analyze_dynamic_channels(data_packets)

if __name__ == '__main__':
    main()
