#!/usr/bin/env python3
"""
BTSnoop HCI Log Parser v3 - Handles Android datalink 1001 format correctly
For analyzing Bluetooth OBD2 protocol communication
"""

import struct
import sys

BTSNOOP_MAGIC = b'btsnoop\x00'
BTSNOOP_HEADER_SIZE = 16
RECORD_HEADER_SIZE = 24

def parse_btsnoop(filename):
    """Parse BTSnoop file with correct handling of datalink 1001"""
    with open(filename, 'rb') as f:
        header = f.read(BTSNOOP_HEADER_SIZE)
        if not header.startswith(BTSNOOP_MAGIC):
            print("Not a valid BTSnoop file")
            return [], 0

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

            # For datalink 1001 (Android):
            # Bit 0: direction (0=TX/sent, 1=RX/received)
            # Bit 1: type (0=ACL/SCO data, 1=HCI Command/Event)
            direction = "RX" if (flags & 1) else "TX"
            is_cmd_event = bool(flags & 2)

            # Determine packet type from flags (not from data[0] for datalink 1001)
            if is_cmd_event:
                if flags & 1:  # RX
                    pkt_type = 'EVENT'
                else:  # TX
                    pkt_type = 'COMMAND'
            else:
                # Could be ACL or SCO - check data format
                # ACL packets start with connection handle (12 bits)
                pkt_type = 'ACL'  # Assume ACL for now

            packets.append({
                'num': packet_num,
                'timestamp': timestamp,
                'direction': direction,
                'type': pkt_type,
                'flags': flags,
                'data': data
            })

        return packets, datalink

def analyze_packets(packets):
    """Analyze HCI packets"""
    stats = {'COMMAND': 0, 'EVENT': 0, 'ACL': 0}
    acl_packets = []

    for pkt in packets:
        pkt_type = pkt['type']
        if pkt_type in stats:
            stats[pkt_type] += 1

        if pkt_type == 'ACL':
            acl_packets.append(pkt)

    print(f"\nPacket Statistics:")
    print(f"  HCI Commands: {stats['COMMAND']}")
    print(f"  HCI Events:   {stats['EVENT']}")
    print(f"  ACL Data:     {stats['ACL']}")

    return acl_packets

def extract_acl_data(packets):
    """Extract and analyze ACL data packets for datalink 1001"""
    print(f"\n{'='*70}")
    print("ACL DATA PACKETS ANALYSIS")
    print('='*70)

    data_packets = []

    for pkt in packets:
        data = pkt['data']
        if len(data) < 4:
            continue

        # For datalink 1001, ACL data starts directly with handle (no H4 type byte)
        # ACL header: handle+flags (2 bytes), length (2 bytes)
        handle_flags = struct.unpack('<H', data[0:2])[0]
        handle = handle_flags & 0x0FFF
        pb_flag = (handle_flags >> 12) & 0x03
        bc_flag = (handle_flags >> 14) & 0x03

        acl_len = struct.unpack('<H', data[2:4])[0]
        acl_payload = data[4:4+acl_len]

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
                'l2cap_len': l2cap_len,
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

def analyze_rfcomm_packets(data_packets):
    """Analyze RFCOMM packets on dynamic channels"""
    print(f"\n{'='*70}")
    print("RFCOMM / SPP DATA ANALYSIS")
    print('='*70)

    dynamic_packets = [p for p in data_packets if p['cid'] >= 0x0040]

    if not dynamic_packets:
        print("No dynamic channel (RFCOMM) data found")
        return []

    rfcomm_data = []

    for pkt in dynamic_packets:
        data = pkt['l2cap_data']
        if len(data) < 3:
            continue

        # RFCOMM frame format
        addr = data[0]
        control = data[1]

        # Extract DLCI (channel)
        dlci = addr >> 2
        cr = (addr >> 1) & 1
        ea = addr & 1

        # Frame types
        frame_types = {
            0x2F: 'SABM',  # Set Async Balanced Mode
            0x63: 'UA',    # Unnumbered Ack
            0x0F: 'DM',    # Disconnected Mode
            0x43: 'DISC',  # Disconnect
            0xEF: 'UIH',   # Unnumbered Info with Header check
            0x03: 'UI',    # Unnumbered Info
        }

        ctrl_type = control & 0xEF  # Mask P/F bit
        frame_type = frame_types.get(ctrl_type, f'Unknown(0x{control:02X})')

        # For UIH frames (data frames), extract payload
        if ctrl_type == 0xEF:
            length_byte = data[2]
            if length_byte & 1:  # 1 byte length
                payload_len = length_byte >> 1
                payload_start = 3
            else:  # 2 byte length
                if len(data) < 4:
                    continue
                payload_len = (length_byte >> 1) | (data[3] << 7)
                payload_start = 4

            if len(data) >= payload_start + payload_len:
                payload = data[payload_start:payload_start + payload_len]

                if payload_len > 0:
                    rfcomm_data.append({
                        'num': pkt['num'],
                        'direction': pkt['direction'],
                        'dlci': dlci,
                        'data': payload
                    })

                    print(f"\n[{pkt['num']:4d}] {pkt['direction']} DLCI={dlci:2d} Len={payload_len:3d}")
                    print(f"       HEX: {payload.hex().upper()[:80]}{'...' if len(payload.hex()) > 80 else ''}")

                    # Try ASCII decode
                    try:
                        ascii_val = payload.decode('ascii', errors='replace')
                        printable = ''.join(c if 32 <= ord(c) < 127 else '.' for c in ascii_val)
                        if printable.strip():
                            print(f"       ASCII: {printable[:80]}")
                    except:
                        pass

                    # Detect OBD2 patterns
                    detect_obd2_patterns(payload)
        else:
            print(f"\n[{pkt['num']:4d}] {pkt['direction']} RFCOMM {frame_type} DLCI={dlci}")

    return rfcomm_data

def detect_obd2_patterns(data):
    """Detect common OBD2 protocol patterns"""
    patterns_found = []

    # AT commands
    if b'AT' in data:
        patterns_found.append("AT COMMAND")

    # ELM327 responses
    if b'ELM' in data or b'elm' in data:
        patterns_found.append("ELM327 ID")
    if b'OK' in data:
        patterns_found.append("OK RESPONSE")
    if b'?' in data or b'ERROR' in data:
        patterns_found.append("ERROR/UNKNOWN")

    # OBD2 mode responses (Mode 01, 02, etc.)
    if len(data) >= 2:
        # Response to Mode 01 (current data) starts with 41
        if data[0] == 0x41:
            patterns_found.append(f"OBD2 MODE 01 RESPONSE (PID: 0x{data[1]:02X})")
        # Response to Mode 03 (DTCs) starts with 43
        elif data[0] == 0x43:
            patterns_found.append("OBD2 DTC RESPONSE")
        # Response to Mode 09 (vehicle info) starts with 49
        elif data[0] == 0x49:
            patterns_found.append(f"OBD2 MODE 09 RESPONSE (PID: 0x{data[1]:02X})")

    # ISO-TP / CAN framing
    if len(data) >= 1:
        first_nibble = (data[0] >> 4) & 0x0F
        if first_nibble == 0:  # Single frame
            pass
        elif first_nibble == 1:  # First frame
            patterns_found.append("ISO-TP FIRST FRAME")
        elif first_nibble == 2:  # Consecutive frame
            patterns_found.append("ISO-TP CONSECUTIVE FRAME")
        elif first_nibble == 3:  # Flow control
            patterns_found.append("ISO-TP FLOW CONTROL")

    # Hex-encoded OBD responses (like "41 0D 00")
    try:
        text = data.decode('ascii', errors='ignore')
        if text.startswith('41 ') or text.startswith('43 ') or text.startswith('49 '):
            patterns_found.append("HEX-ENCODED OBD2 RESPONSE")
    except:
        pass

    if patterns_found:
        print(f"       >>> {', '.join(patterns_found)}")

def analyze_hci_events(packets):
    """Analyze HCI events for connection info"""
    print(f"\n{'='*70}")
    print("HCI CONNECTION EVENTS")
    print('='*70)

    events = [p for p in packets if p['type'] == 'EVENT']

    # Event codes of interest
    interesting_events = {
        0x03: 'Connection Complete',
        0x04: 'Disconnect Complete',
        0x05: 'Authentication Complete',
        0x06: 'Remote Name Request Complete',
        0x07: 'Encryption Change',
        0x0B: 'Read Remote Supported Features Complete',
        0x0E: 'Command Complete',
        0x0F: 'Command Status',
        0x13: 'Number of Completed Packets',
        0x17: 'Link Key Notification',
        0x18: 'Loopback Command',
        0x2F: 'Extended Inquiry Result',
    }

    for pkt in events[:50]:  # First 50 events
        data = pkt['data']
        if len(data) < 2:
            continue

        event_code = data[0]
        param_len = data[1]
        params = data[2:2+param_len] if len(data) > 2 else b''

        if event_code in interesting_events:
            event_name = interesting_events[event_code]
            print(f"\n[{pkt['num']:4d}] {event_name}")

            if event_code == 0x03:  # Connection Complete
                if len(params) >= 11:
                    status = params[0]
                    conn_handle = struct.unpack('<H', params[1:3])[0]
                    bd_addr = ':'.join(f'{b:02X}' for b in reversed(params[3:9]))
                    link_type = params[9]
                    encryption = params[10]
                    print(f"       Status: {status}, Handle: 0x{conn_handle:04X}")
                    print(f"       BD_ADDR: {bd_addr}")
                    print(f"       Link Type: {link_type}, Encryption: {encryption}")

            elif event_code == 0x06:  # Remote Name Request Complete
                if len(params) >= 7:
                    status = params[0]
                    bd_addr = ':'.join(f'{b:02X}' for b in reversed(params[1:7]))
                    name = params[7:].rstrip(b'\x00').decode('utf-8', errors='replace')
                    print(f"       BD_ADDR: {bd_addr}")
                    print(f"       Name: {name}")

def main():
    filename = sys.argv[1] if len(sys.argv) > 1 else r"E:\btsnoop_hci.log"

    print(f"Parsing: {filename}")
    print('='*70)

    packets, datalink = parse_btsnoop(filename)
    print(f"Total HCI packets: {len(packets)}")

    if datalink != 1001:
        print(f"WARNING: This parser is optimized for datalink 1001 (Android)")
        print(f"         Found datalink {datalink}")

    # Analyze packet types
    acl_packets = analyze_packets(packets)

    # Analyze HCI events for connection info
    analyze_hci_events(packets)

    if acl_packets:
        # Extract L2CAP data
        data_packets = extract_acl_data(acl_packets)

        # Analyze RFCOMM/SPP data
        if data_packets:
            rfcomm_data = analyze_rfcomm_packets(data_packets)

            if rfcomm_data:
                print(f"\n{'='*70}")
                print("PROTOCOL SUMMARY")
                print('='*70)
                print(f"Total RFCOMM data packets: {len(rfcomm_data)}")

                # Group by DLCI
                dlci_data = {}
                for pkt in rfcomm_data:
                    dlci = pkt['dlci']
                    if dlci not in dlci_data:
                        dlci_data[dlci] = {'tx': [], 'rx': []}
                    dlci_data[dlci][pkt['direction'].lower()].append(pkt['data'])

                for dlci, data in sorted(dlci_data.items()):
                    print(f"\nDLCI {dlci}:")
                    print(f"  TX packets: {len(data['tx'])}")
                    print(f"  RX packets: {len(data['rx'])}")
    else:
        print("\nNo ACL data packets found")

if __name__ == '__main__':
    main()
