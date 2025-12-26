# Autel J2534 Bluetooth Protocol Specification

**Version**: 1.0
**Date**: December 26, 2024
**Status**: Reverse Engineered from BT HCI Snoop Log

## Overview

The Autel VCI (Vehicle Communication Interface) communicates with the tablet/phone via Bluetooth Classic using a proprietary binary protocol that wraps SAE J2534 Passthru API calls.

## Device Information

| Property | Value |
|----------|-------|
| VID | 0xA5A5 |
| Bluetooth Name | Maxi-CFJMMAC3989 (varies by unit) |
| Bluetooth Address | 00:0C:BF:XX:XX:XX |
| BT Module | Microchip BM78 |
| Firmware | V2.09 (Mar 14 2024) |
| Device ID | J2534-1:MAXI FLASH |
| Vendor ID | AUTEL:SAE J2534 |

## Transport Layer

- **Protocol**: Bluetooth Classic SPP (Serial Port Profile)
- **RFCOMM Channel**: DLCI 12
- **Connection**: Standard RFCOMM connection establishment

## Packet Structure

### Request Packet (TX to VCI)

```
Offset  Size  Field               Description
------  ----  -----------------   -----------
0       4     Magic               0x5555AAAA (fixed)
4       4     TotalLength         Total packet length (little-endian)
8       4     SessionID           Unique session identifier
12      4     MessageCounter      Incrementing counter/timestamp
16      4     PayloadLength       Payload data length (little-endian)
20      4     SessionID2          SessionID repeated
24      4     Flags               Usually 0xFFFFFFFF
28      4     Command             Primary command code
32      4     SubCommand          Sub-command/parameter
36      N     Payload             Command-specific data
36+N    4     CRC32               CRC32 checksum
```

### Response Packet (RX from VCI)

```
Offset  Size  Field               Description
------  ----  -----------------   -----------
0       1     Prefix              0x00 (optional prefix byte)
1       4     Magic               0x5555AAAA (fixed)
5       4     TotalLength         Total packet length (little-endian)
9       4     SessionID           Matches request SessionID
13      4     MessageCounter      Response counter
17      4     PayloadLength       Payload data length (little-endian)
21      4     SessionID2          SessionID repeated
25      4     Flags               Usually 0xFFFFFFFF
29      4     Status              0x00 = Success, other = Error
33      4     Reserved            Usually 0x00000000
37      N     Payload             Response data
37+N    4     CRC32               CRC32 checksum
```

## Command Reference

### Device Commands (Command = 0x00)

| SubCommand | Name | Description |
|------------|------|-------------|
| 0x00 | IDENTIFY | Initial device identification |
| 0x02 | UNKNOWN_02 | Unknown |
| 0x03 | DISCONNECT | Close connection |
| 0x05 | UNKNOWN_05 | Unknown |
| 0x08 | UNKNOWN_08 | Unknown |
| 0x0B | GET_VERSION | Get firmware version info |

### PassThru Commands (Command = 0x01)

| SubCommand | Name | Description |
|------------|------|-------------|
| 0x02 | PT_READ_MSGS | PassThruReadMsgs |
| 0x03 | PT_CLOSE | PassThruClose |
| 0x05 | PT_UNKNOWN_05 | Unknown |
| 0x07 | PT_UNKNOWN_07 | Unknown |
| 0x09 | PT_UNKNOWN_09 | Unknown |
| 0x0A | PT_UNKNOWN_0A | Unknown |
| 0x10001 | PT_OPEN_1 | PassThruOpen variant |
| 0x10003 | PT_OPEN_3 | PassThruOpen variant |
| 0x10004 | PT_OPEN_4 | PassThruOpen variant |
| 0x800C | PT_IOCTL | PassThruIoctl |

### Read Commands (Command = 0x02)

| SubCommand | Name | Description |
|------------|------|-------------|
| 0x10005 | READ_DATA | Read diagnostic data |

## Example Messages

### Device Identification Request

```
TX: 5555AAAA 40000000 FC553100 91ABDBAA 2C000000 FC553100 FFFFFFFF 00000000 00000000
    4A323533342D313A4D41584920464C415348000099996666 5208921E [CRC32]

Payload ASCII: "J2534-1:MAXI FLASH"
```

### Device Identification Response

```
RX: 00 5555AAAA 3C000000 FC553100 8DABDBAA 28000000 FC553100 FFFFFFFF 00000000 00000000
    415554454C3A534145204A32353334... [CRC32]

Payload ASCII: "AUTEL:SAE J2534"
```

### Get Version Request (Command 0x00, SubCommand 0x0B)

```
TX: 5555AAAA 28000000 DC365C00 598C06AB 14000000 DC365C00 FFFFFFFF 00000000 0B000000
    [4-byte payload] [CRC32]
```

### Get Version Response

```
RX: 00 5555AAAA 78000000 DC365C00 A98C06AB 64000000 DC365C00 FFFFFFFF 00000000 00000000
    4D617220313420323032342031353A31353A343120205632...

Payload ASCII: "Mar 14 2024 15:15:41  V2.09..."
```

### PassThruClose Request (Command 0x01, SubCommand 0x03)

```
TX: 5555AAAA 28000000 A0BC0C00 1D12B7AA 14000000 A0BC0C00 FFFFFFFF 01000000 03000000
    [4-byte payload] [CRC32]
```

### Success Response

```
RX: 00 5555AAAA 2C000000 A0BC0C00 2112B7AA 18000000 A0BC0C00 FFFFFFFF 00000000 00000000
    [payload] [CRC32]

Status 0x00 = Success
```

## CRC32 Calculation

The CRC32 appears to be calculated over the packet data (excluding the CRC32 itself). The exact polynomial is not yet determined - common options:
- CRC-32 (IEEE 802.3)
- CRC-32C (Castagnoli)

## Session Management

1. Each request generates a unique SessionID
2. Response SessionID must match request SessionID
3. MessageCounter increments for each message
4. Multiple commands can be in-flight (matched by SessionID)

## Connection Sequence

1. Establish Bluetooth RFCOMM connection to DLCI 12
2. Send IDENTIFY request with "J2534-1:MAXI FLASH"
3. Receive response with "AUTEL:SAE J2534"
4. Send GET_VERSION to verify connectivity
5. Receive firmware version response
6. Begin J2534 PassThru operations

## J2534 PassThru Mapping

This protocol wraps the standard SAE J2534 API:

| J2534 API | Autel Command |
|-----------|---------------|
| PassThruOpen | 0x01, 0x10004 |
| PassThruClose | 0x01, 0x03 |
| PassThruConnect | 0x05, 0x00 |
| PassThruDisconnect | 0x05, 0x80000001 |
| PassThruReadMsgs | 0x02, 0x01 |
| PassThruWriteMsgs | 0x02, 0x02 |
| PassThruStartMsgFilter | 0x02, 0x03 |
| PassThruStopMsgFilter | 0x02, 0x8003 |
| PassThruIoctl | 0x08, 0x01 |
| PassThruReadVersion | 0x08, 0x03 |
| PassThruSetProgrammingVoltage | 0x02, 0x8005 |

## Protocol Summary Statistics (from capture)

| Message Type | TX Count | RX Count |
|--------------|----------|----------|
| GET_VERSION (0x00, 0x0B) | 1108 | - |
| SUCCESS_RESPONSE | - | 1238 |
| PT_READ_MSGS (0x01, 0x02) | 165 | - |
| PT_CLOSE (0x01, 0x03) | 71 | - |
| UNKNOWN_08 (0x00, 0x08) | 64 | - |

## Implementation Notes

1. **NOT ELM327**: This is NOT an AT-command based ELM327 protocol
2. **Binary Protocol**: All communication is binary-framed
3. **J2534 Based**: Commands map to SAE J2534 Passthru API
4. **CRC Required**: All packets must include valid CRC32
5. **Session Tracking**: Must track SessionID for request/response matching

## Files

- `parse_btsnoop_v3.py` - BTSnoop HCI log parser for datalink 1001
- `analyze_autel_protocol_v2.py` - Autel protocol analyzer
- `E:\btsnoop_hci.log` - Original capture file (436KB, 6276 HCI packets)

## Future Work

1. Determine exact CRC32 polynomial
2. Map remaining unknown commands
3. Implement protocol in OpenDiag Flutter app
4. Test with actual VCI device
