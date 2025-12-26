/// Autel J2534 Bluetooth Protocol Implementation
/// Based on reverse-engineered protocol from BT HCI snoop log analysis
library;

import 'dart:typed_data';

/// Protocol constants for Autel VCI communication
class AutelProtocol {
  /// Magic bytes for packet identification (TX and start of RX)
  static const List<int> magic = [0x55, 0x55, 0xAA, 0xAA];

  /// RFCOMM channel used by Autel VCI
  static const int rfcommDlci = 12;

  /// Bluetooth SPP UUID for RFCOMM connection
  static const String sppUuid = '00001101-0000-1000-8000-00805F9B34FB';

  /// Default packet flags value
  static const int defaultFlags = 0xFFFFFFFF;

  /// Packet header size (excluding magic)
  static const int headerSize = 36;

  /// Minimum packet size (header + CRC)
  static const int minPacketSize = 40;

  /// CRC32 size at end of packet
  static const int crcSize = 4;
}

/// Device command codes (Command = 0x00)
class AutelDeviceCommand {
  static const int identify = 0x00;
  static const int unknown02 = 0x02;
  static const int disconnect = 0x03;
  static const int unknown05 = 0x05;
  static const int unknown08 = 0x08;
  static const int getVersion = 0x0B;
}

/// PassThru command codes (Command = 0x01)
class AutelPassThruCommand {
  static const int command = 0x01;
  static const int readMsgs = 0x02;
  static const int close = 0x03;
  static const int unknown05 = 0x05;
  static const int unknown07 = 0x07;
  static const int unknown09 = 0x09;
  static const int unknown0A = 0x0A;
  static const int open1 = 0x10001;
  static const int open3 = 0x10003;
  static const int open4 = 0x10004;
  static const int ioctl = 0x800C;
}

/// Read command codes (Command = 0x02)
class AutelReadCommand {
  static const int command = 0x02;
  static const int readMsgs = 0x01;
  static const int writeMsgs = 0x02;
  static const int startMsgFilter = 0x03;
  static const int stopMsgFilter = 0x8003;
  static const int setProgrammingVoltage = 0x8005;
  static const int readData = 0x10005;
}

/// Connect command codes (Command = 0x05)
class AutelConnectCommand {
  static const int command = 0x05;
  static const int connect = 0x00;
  static const int disconnect = 0x80000001;
}

/// IOCTL command codes (Command = 0x08)
class AutelIoctlCommand {
  static const int command = 0x08;
  static const int ioctl = 0x01;
  static const int readVersion = 0x03;
}

/// Response status codes
class AutelStatus {
  static const int success = 0x00;

  /// J2534 error codes (from SAE J2534 spec)
  static const int errNotSupported = 0x01;
  static const int errInvalidChannelId = 0x02;
  static const int errInvalidProtocolId = 0x03;
  static const int errNullParameter = 0x04;
  static const int errInvalidIoctlValue = 0x05;
  static const int errInvalidFlags = 0x06;
  static const int errFailed = 0x07;
  static const int errDeviceNotConnected = 0x08;
  static const int errTimeout = 0x09;
  static const int errInvalidMsg = 0x0A;
  static const int errInvalidTimeInterval = 0x0B;
  static const int errExceededLimit = 0x0C;
  static const int errInvalidMsgId = 0x0D;
  static const int errDeviceInUse = 0x0E;
  static const int errInvalidIoctlId = 0x0F;
  static const int errBufferEmpty = 0x10;
  static const int errBufferFull = 0x11;
  static const int errBufferOverflow = 0x12;
  static const int errPinInvalid = 0x13;
  static const int errChannelInUse = 0x14;
  static const int errMsgProtocolId = 0x15;
  static const int errInvalidFilterId = 0x16;
  static const int errNoFlowControl = 0x17;
  static const int errNotUnique = 0x18;
  static const int errInvalidBaudrate = 0x19;
  static const int errInvalidDeviceId = 0x1A;
}

/// J2534 Protocol IDs
class J2534Protocol {
  static const int j1850Vpw = 0x01;
  static const int j1850Pwm = 0x02;
  static const int iso9141 = 0x03;
  static const int iso14230 = 0x04;
  static const int can = 0x05;
  static const int iso15765 = 0x06;
  static const int sciAEngine = 0x07;
  static const int sciATrans = 0x08;
  static const int sciBEngine = 0x09;
  static const int sciBTrans = 0x0A;
}

/// J2534 IOCTL IDs
class J2534Ioctl {
  static const int getConfig = 0x01;
  static const int setConfig = 0x02;
  static const int readVbatt = 0x03;
  static const int fiveBaudInit = 0x04;
  static const int fastInit = 0x05;
  static const int clearTxBuffer = 0x07;
  static const int clearRxBuffer = 0x08;
  static const int clearPeriodicMsgs = 0x09;
  static const int clearMsgFilters = 0x0A;
  static const int clearFunctMsgLookupTable = 0x0B;
  static const int addToFunctMsgLookupTable = 0x0C;
  static const int deleteFromFunctMsgLookupTable = 0x0D;
  static const int readProgVoltage = 0x0E;
}

/// J2534 Filter Types (from SAE J2534 spec)
class J2534FilterType {
  /// Pass filter - allows frames matching the pattern through
  static const int pass = 0x01;

  /// Block filter - blocks frames matching the pattern
  static const int block = 0x02;

  /// Flow control filter - used for ISO 15765-2 (CAN ISO-TP) flow control
  static const int flowControl = 0x03;
}

/// CRC32 calculator for Autel protocol
/// Uses IEEE 802.3 polynomial (standard CRC32)
class AutelCrc32 {
  static final Uint32List _table = _generateTable();

  static Uint32List _generateTable() {
    final table = Uint32List(256);
    const polynomial = 0xEDB88320;

    for (int i = 0; i < 256; i++) {
      int crc = i;
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ polynomial;
        } else {
          crc = crc >> 1;
        }
      }
      table[i] = crc;
    }
    return table;
  }

  /// Calculate CRC32 over the given data
  static int calculate(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }

  /// Calculate CRC32 and return as little-endian bytes
  static List<int> calculateBytes(List<int> data) {
    final crc = calculate(data);
    return [
      crc & 0xFF,
      (crc >> 8) & 0xFF,
      (crc >> 16) & 0xFF,
      (crc >> 24) & 0xFF,
    ];
  }

  /// Verify CRC32 at end of packet
  static bool verify(List<int> data) {
    if (data.length < 4) return false;

    final packetData = data.sublist(0, data.length - 4);
    final expectedCrc = (data[data.length - 4] |
        (data[data.length - 3] << 8) |
        (data[data.length - 2] << 16) |
        (data[data.length - 1] << 24));

    final calculatedCrc = calculate(packetData);
    return calculatedCrc == expectedCrc;
  }
}

/// Device identification strings
class AutelDeviceId {
  /// Device ID sent during identification
  static const String deviceId = 'J2534-1:MAXI FLASH';

  /// Expected vendor response
  static const String vendorId = 'AUTEL:SAE J2534';

  /// Known Bluetooth name prefix
  static const String btNamePrefix = 'Maxi-';

  /// Bluetooth OUI for Autel devices (first 3 bytes of MAC)
  static const String btOui = '00:0C:BF';
}
