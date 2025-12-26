/// Autel J2534 Packet Builder and Parser
/// Handles packet framing, session management, and serialization
library;

import 'dart:math';
import 'dart:typed_data';
import 'autel_protocol.dart';

/// Session ID generator for unique request/response matching
class AutelSessionManager {
  final Random _random = Random();
  int _messageCounter = 0;

  /// Generate a new unique session ID
  int generateSessionId() {
    return _random.nextInt(0xFFFFFFFF);
  }

  /// Get next message counter value
  int nextMessageCounter() {
    _messageCounter = (_messageCounter + 1) & 0xFFFFFFFF;
    return _messageCounter;
  }

  /// Reset message counter
  void reset() {
    _messageCounter = 0;
  }
}

/// Parsed Autel protocol packet
class AutelPacket {
  /// Whether packet has a leading 0x00 prefix (RX packets)
  final bool hasPrefix;

  /// Total packet length from header
  final int totalLength;

  /// Session ID for request/response matching
  final int sessionId;

  /// Message counter/sequence number
  final int messageCounter;

  /// Payload data length
  final int payloadLength;

  /// Flags field (usually 0xFFFFFFFF)
  final int flags;

  /// Command code (for TX) or Status (for RX)
  final int command;

  /// SubCommand/Parameter
  final int subCommand;

  /// Payload data
  final Uint8List payload;

  /// CRC32 checksum
  final int crc;

  /// Raw packet bytes
  final Uint8List rawBytes;

  /// Whether this is a response (RX) packet
  final bool isResponse;

  AutelPacket({
    required this.hasPrefix,
    required this.totalLength,
    required this.sessionId,
    required this.messageCounter,
    required this.payloadLength,
    required this.flags,
    required this.command,
    required this.subCommand,
    required this.payload,
    required this.crc,
    required this.rawBytes,
    required this.isResponse,
  });

  /// Check if response indicates success
  bool get isSuccess => isResponse && command == AutelStatus.success;

  /// Get payload as ASCII string (if printable)
  String? get payloadAsString {
    if (payload.isEmpty) return null;
    try {
      final chars = payload.where((b) => b >= 32 && b < 127).toList();
      if (chars.length > 3) {
        return String.fromCharCodes(chars);
      }
    } catch (_) {}
    return null;
  }

  @override
  String toString() {
    return 'AutelPacket('
        'session: 0x${sessionId.toRadixString(16).toUpperCase()}, '
        'cmd: 0x${command.toRadixString(16)}, '
        'subcmd: 0x${subCommand.toRadixString(16)}, '
        'status: ${isResponse ? (isSuccess ? "OK" : "ERR") : "TX"}, '
        'payload: ${payload.length} bytes)';
  }
}

/// Builder for constructing Autel protocol packets
class AutelPacketBuilder {
  final AutelSessionManager _sessionManager;
  int _sessionId = 0;

  AutelPacketBuilder(this._sessionManager);

  /// Start a new packet with a fresh session ID
  AutelPacketBuilder newSession() {
    _sessionId = _sessionManager.generateSessionId();
    return this;
  }

  /// Use an existing session ID (for continuing a conversation)
  AutelPacketBuilder withSession(int sessionId) {
    _sessionId = sessionId;
    return this;
  }

  /// Build a device identification request
  Uint8List buildIdentifyRequest() {
    return _buildPacket(
      command: 0x00,
      subCommand: AutelDeviceCommand.identify,
      payload: _encodeString(AutelDeviceId.deviceId),
    );
  }

  /// Build a get version request
  Uint8List buildGetVersionRequest() {
    return _buildPacket(
      command: 0x00,
      subCommand: AutelDeviceCommand.getVersion,
      payload: Uint8List(4), // 4 bytes of zeros
    );
  }

  /// Build a disconnect request
  Uint8List buildDisconnectRequest() {
    return _buildPacket(
      command: 0x00,
      subCommand: AutelDeviceCommand.disconnect,
      payload: Uint8List(4),
    );
  }

  /// Build a PassThruOpen request
  Uint8List buildPassThruOpenRequest({required int protocolId}) {
    final payload = ByteData(8);
    payload.setUint32(0, protocolId, Endian.little);
    payload.setUint32(4, 0, Endian.little); // flags

    return _buildPacket(
      command: AutelPassThruCommand.command,
      subCommand: AutelPassThruCommand.open4,
      payload: payload.buffer.asUint8List(),
    );
  }

  /// Build a PassThruClose request
  Uint8List buildPassThruCloseRequest({required int channelId}) {
    final payload = ByteData(4);
    payload.setUint32(0, channelId, Endian.little);

    return _buildPacket(
      command: AutelPassThruCommand.command,
      subCommand: AutelPassThruCommand.close,
      payload: payload.buffer.asUint8List(),
    );
  }

  /// Build a PassThruConnect request
  Uint8List buildPassThruConnectRequest({
    required int protocolId,
    required int flags,
    required int baudrate,
  }) {
    final payload = ByteData(12);
    payload.setUint32(0, protocolId, Endian.little);
    payload.setUint32(4, flags, Endian.little);
    payload.setUint32(8, baudrate, Endian.little);

    return _buildPacket(
      command: AutelConnectCommand.command,
      subCommand: AutelConnectCommand.connect,
      payload: payload.buffer.asUint8List(),
    );
  }

  /// Build a PassThruDisconnect request
  Uint8List buildPassThruDisconnectRequest({required int channelId}) {
    final payload = ByteData(4);
    payload.setUint32(0, channelId, Endian.little);

    return _buildPacket(
      command: AutelConnectCommand.command,
      subCommand: AutelConnectCommand.disconnect,
      payload: payload.buffer.asUint8List(),
    );
  }

  /// Build a PassThruReadMsgs request
  Uint8List buildPassThruReadMsgsRequest({
    required int channelId,
    required int numMsgs,
    required int timeout,
  }) {
    final payload = ByteData(12);
    payload.setUint32(0, channelId, Endian.little);
    payload.setUint32(4, numMsgs, Endian.little);
    payload.setUint32(8, timeout, Endian.little);

    return _buildPacket(
      command: AutelReadCommand.command,
      subCommand: AutelReadCommand.readMsgs,
      payload: payload.buffer.asUint8List(),
    );
  }

  /// Build a PassThruWriteMsgs request
  Uint8List buildPassThruWriteMsgsRequest({
    required int channelId,
    required List<int> data,
    required int timeout,
  }) {
    // Message structure: channel (4), numMsgs (4), timeout (4), then message
    final msgData = Uint8List.fromList(data);
    final payload = ByteData(16 + msgData.length);
    payload.setUint32(0, channelId, Endian.little);
    payload.setUint32(4, 1, Endian.little); // numMsgs = 1
    payload.setUint32(8, timeout, Endian.little);
    payload.setUint32(12, msgData.length, Endian.little); // data length

    final payloadBytes = payload.buffer.asUint8List();
    for (int i = 0; i < msgData.length; i++) {
      payloadBytes[16 + i] = msgData[i];
    }

    return _buildPacket(
      command: AutelReadCommand.command,
      subCommand: AutelReadCommand.writeMsgs,
      payload: payloadBytes,
    );
  }

  /// Build a PassThruStartMsgFilter request
  Uint8List buildPassThruStartMsgFilterRequest({
    required int channelId,
    required int filterType,
    List<int>? maskMsg,
    List<int>? patternMsg,
    List<int>? flowControlMsg,
  }) {
    final mask = maskMsg ?? [];
    final pattern = patternMsg ?? [];
    final flow = flowControlMsg ?? [];

    final payload = ByteData(20 + mask.length + pattern.length + flow.length);
    int offset = 0;

    payload.setUint32(offset, channelId, Endian.little);
    offset += 4;
    payload.setUint32(offset, filterType, Endian.little);
    offset += 4;
    payload.setUint32(offset, mask.length, Endian.little);
    offset += 4;
    payload.setUint32(offset, pattern.length, Endian.little);
    offset += 4;
    payload.setUint32(offset, flow.length, Endian.little);
    offset += 4;

    final payloadBytes = payload.buffer.asUint8List();
    for (final b in mask) {
      payloadBytes[offset++] = b;
    }
    for (final b in pattern) {
      payloadBytes[offset++] = b;
    }
    for (final b in flow) {
      payloadBytes[offset++] = b;
    }

    return _buildPacket(
      command: AutelReadCommand.command,
      subCommand: AutelReadCommand.startMsgFilter,
      payload: payloadBytes,
    );
  }

  /// Build a PassThruStopMsgFilter request
  Uint8List buildPassThruStopMsgFilterRequest({
    required int channelId,
    required int filterId,
  }) {
    final payload = ByteData(8);
    payload.setUint32(0, channelId, Endian.little);
    payload.setUint32(4, filterId, Endian.little);

    return _buildPacket(
      command: AutelReadCommand.command,
      subCommand: AutelReadCommand.stopMsgFilter,
      payload: payload.buffer.asUint8List(),
    );
  }

  /// Build a PassThruIoctl request
  Uint8List buildPassThruIoctlRequest({
    required int channelId,
    required int ioctlId,
    Uint8List? input,
  }) {
    final inputData = input ?? Uint8List(0);
    final payload = ByteData(12 + inputData.length);
    payload.setUint32(0, channelId, Endian.little);
    payload.setUint32(4, ioctlId, Endian.little);
    payload.setUint32(8, inputData.length, Endian.little);

    final payloadBytes = payload.buffer.asUint8List();
    for (int i = 0; i < inputData.length; i++) {
      payloadBytes[12 + i] = inputData[i];
    }

    return _buildPacket(
      command: AutelIoctlCommand.command,
      subCommand: AutelIoctlCommand.ioctl,
      payload: payloadBytes,
    );
  }

  /// Build a PassThruReadVersion request
  Uint8List buildPassThruReadVersionRequest({required int deviceId}) {
    final payload = ByteData(4);
    payload.setUint32(0, deviceId, Endian.little);

    return _buildPacket(
      command: AutelIoctlCommand.command,
      subCommand: AutelIoctlCommand.readVersion,
      payload: payload.buffer.asUint8List(),
    );
  }

  /// Build a raw packet with custom command/subcommand
  Uint8List buildCustomRequest({
    required int command,
    required int subCommand,
    required Uint8List payload,
  }) {
    return _buildPacket(
      command: command,
      subCommand: subCommand,
      payload: payload,
    );
  }

  /// Internal method to build a complete packet
  Uint8List _buildPacket({
    required int command,
    required int subCommand,
    required Uint8List payload,
  }) {
    final msgCounter = _sessionManager.nextMessageCounter();

    // Calculate total packet length (excludes magic, includes everything from total_len to CRC)
    final payloadDataLen = payload.length;
    final totalLen = 32 + payloadDataLen; // header (32) + payload

    // Build packet
    final packetLen = 4 + totalLen + 4; // magic + data + CRC
    final packet = ByteData(packetLen);
    int offset = 0;

    // Magic bytes
    for (final b in AutelProtocol.magic) {
      packet.setUint8(offset++, b);
    }

    // Total length (little-endian)
    packet.setUint32(offset, totalLen, Endian.little);
    offset += 4;

    // Session ID
    packet.setUint32(offset, _sessionId, Endian.little);
    offset += 4;

    // Message counter
    packet.setUint32(offset, msgCounter, Endian.little);
    offset += 4;

    // Payload length
    packet.setUint32(offset, payloadDataLen + 8, Endian.little); // includes cmd+subcmd
    offset += 4;

    // Session ID (repeated)
    packet.setUint32(offset, _sessionId, Endian.little);
    offset += 4;

    // Flags
    packet.setUint32(offset, AutelProtocol.defaultFlags, Endian.little);
    offset += 4;

    // Command
    packet.setUint32(offset, command, Endian.little);
    offset += 4;

    // SubCommand
    packet.setUint32(offset, subCommand, Endian.little);
    offset += 4;

    // Payload data
    final packetBytes = packet.buffer.asUint8List();
    for (int i = 0; i < payload.length; i++) {
      packetBytes[offset + i] = payload[i];
    }
    offset += payload.length;

    // Calculate CRC32 over everything before CRC
    final crcData = packetBytes.sublist(0, offset);
    final crc = AutelCrc32.calculate(crcData);

    // Append CRC
    packet.setUint32(offset, crc, Endian.little);

    return packetBytes;
  }

  /// Encode a string with null terminator and padding to 4-byte boundary
  Uint8List _encodeString(String str) {
    final bytes = str.codeUnits;
    // Pad to include null terminator and align to 4 bytes
    final paddedLen = ((bytes.length + 1 + 3) ~/ 4) * 4;
    final result = Uint8List(paddedLen);
    for (int i = 0; i < bytes.length; i++) {
      result[i] = bytes[i];
    }
    // Add magic trailer bytes
    if (paddedLen >= bytes.length + 5) {
      result[paddedLen - 4] = 0x99;
      result[paddedLen - 3] = 0x99;
      result[paddedLen - 2] = 0x66;
      result[paddedLen - 1] = 0x66;
    }
    return result;
  }

  /// Get current session ID
  int get sessionId => _sessionId;
}

/// Parser for Autel protocol packets
class AutelPacketParser {
  /// Parse a received packet (RX)
  static AutelPacket? parse(Uint8List data, {bool isResponse = true}) {
    if (data.length < AutelProtocol.minPacketSize) {
      return null;
    }

    int offset = 0;
    bool hasPrefix = false;

    // Check for optional 0x00 prefix on RX packets
    if (data[0] == 0x00 && data.length > AutelProtocol.minPacketSize) {
      hasPrefix = true;
      offset = 1;
    }

    // Verify magic bytes
    for (int i = 0; i < 4; i++) {
      if (data[offset + i] != AutelProtocol.magic[i]) {
        return null;
      }
    }
    offset += 4;

    // Parse header fields
    final view = ByteData.sublistView(data);

    final totalLength = view.getUint32(offset, Endian.little);
    offset += 4;

    final sessionId = view.getUint32(offset, Endian.little);
    offset += 4;

    final messageCounter = view.getUint32(offset, Endian.little);
    offset += 4;

    final payloadLength = view.getUint32(offset, Endian.little);
    offset += 4;

    // Skip sessionId2 (repeated)
    offset += 4;

    final flags = view.getUint32(offset, Endian.little);
    offset += 4;

    final command = view.getUint32(offset, Endian.little);
    offset += 4;

    final subCommand = view.getUint32(offset, Endian.little);
    offset += 4;

    // Extract payload (excluding command and subcommand bytes already parsed)
    final payloadStart = offset;
    final payloadEnd = (hasPrefix ? 1 : 0) + 4 + totalLength - 4; // Subtract CRC size

    Uint8List payload;
    if (payloadEnd > payloadStart && payloadEnd <= data.length) {
      payload = Uint8List.sublistView(data, payloadStart, payloadEnd);
    } else {
      payload = Uint8List(0);
    }

    // Extract CRC
    int crc = 0;
    if (payloadEnd + 4 <= data.length) {
      crc = view.getUint32(payloadEnd, Endian.little);
    }

    return AutelPacket(
      hasPrefix: hasPrefix,
      totalLength: totalLength,
      sessionId: sessionId,
      messageCounter: messageCounter,
      payloadLength: payloadLength,
      flags: flags,
      command: command,
      subCommand: subCommand,
      payload: payload,
      crc: crc,
      rawBytes: data,
      isResponse: isResponse,
    );
  }

  /// Verify packet CRC
  static bool verifyCrc(Uint8List data) {
    return AutelCrc32.verify(data);
  }

  /// Check if data starts with Autel magic bytes
  static bool hasValidMagic(List<int> data) {
    if (data.isEmpty) return false;

    int offset = 0;
    if (data[0] == 0x00 && data.length > 4) {
      offset = 1;
    }

    if (data.length < offset + 4) return false;

    for (int i = 0; i < 4; i++) {
      if (data[offset + i] != AutelProtocol.magic[i]) {
        return false;
      }
    }
    return true;
  }

  /// Extract expected packet length from header
  static int? getExpectedLength(List<int> data) {
    int offset = 0;
    if (data.isNotEmpty && data[0] == 0x00) {
      offset = 1;
    }

    if (data.length < offset + 8) return null;

    // Check magic first
    for (int i = 0; i < 4; i++) {
      if (data[offset + i] != AutelProtocol.magic[i]) {
        return null;
      }
    }

    // Get total length
    final totalLen = data[offset + 4] |
        (data[offset + 5] << 8) |
        (data[offset + 6] << 16) |
        (data[offset + 7] << 24);

    return offset + 4 + totalLen + 4; // prefix + magic + data + CRC
  }
}

/// Response data from J2534 PassThru operations
class PassThruResponse {
  final int status;
  final Uint8List data;

  PassThruResponse({
    required this.status,
    required this.data,
  });

  bool get isSuccess => status == AutelStatus.success;

  String get statusMessage {
    switch (status) {
      case AutelStatus.success:
        return 'Success';
      case AutelStatus.errNotSupported:
        return 'Not Supported';
      case AutelStatus.errInvalidChannelId:
        return 'Invalid Channel ID';
      case AutelStatus.errInvalidProtocolId:
        return 'Invalid Protocol ID';
      case AutelStatus.errDeviceNotConnected:
        return 'Device Not Connected';
      case AutelStatus.errTimeout:
        return 'Timeout';
      case AutelStatus.errBufferEmpty:
        return 'Buffer Empty';
      default:
        return 'Error 0x${status.toRadixString(16)}';
    }
  }
}
