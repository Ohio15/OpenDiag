import 'dart:async';
import 'dart:typed_data';
import 'package:bluetooth_classic/bluetooth_classic.dart';
import 'package:bluetooth_classic/models/device.dart';
import 'vci_interface.dart';
import 'autel/autel_protocol.dart';
import 'autel/autel_packet.dart';

/// Autel VCI implementation using Bluetooth Classic (SPP)
/// Implements the proprietary J2534-over-Bluetooth protocol
class VciAutelImpl implements VciInterface {
  final BluetoothClassic _bluetooth = BluetoothClassic();
  Device? _connectedDevice;

  final StreamController<List<int>> _responseController =
      StreamController<List<int>>.broadcast();
  final StreamController<VciConnectionState> _stateController =
      StreamController<VciConnectionState>.broadcast();

  VciConnectionState _state = VciConnectionState.disconnected;
  StreamSubscription<Uint8List>? _inputSubscription;

  /// Session manager for packet building
  final AutelSessionManager _sessionManager = AutelSessionManager();

  /// Packet builder
  late final AutelPacketBuilder _packetBuilder;

  /// Buffer for accumulating incoming data
  final List<int> _receiveBuffer = [];

  /// Pending response completer (matched by session ID)
  final Map<int, Completer<AutelPacket>> _pendingResponses = {};

  /// Current J2534 channel ID (if open)
  int? _channelId;
  /// Active UDS channel for module communication
  int? _udsChannelId;
  int? _udsFilterId;
  int? _currentModuleAddress;
  int _udsBaudRate = 500000;


  /// Device firmware version
  String? _firmwareVersion;

  /// Device vendor ID
  String? _vendorId;

  VciAutelImpl() {
    _packetBuilder = AutelPacketBuilder(_sessionManager);
  }

  @override
  Stream<List<int>> get responseStream => _responseController.stream;

  @override
  Stream<VciConnectionState> get connectionStateStream =>
      _stateController.stream;

  @override
  VciConnectionState get state => _state;

  @override
  bool get isConnected => _state == VciConnectionState.connected;

  /// Get the firmware version (after connection)
  String? get firmwareVersion => _firmwareVersion;

  /// Get the vendor ID (after connection)
  String? get vendorId => _vendorId;

  /// Get the current J2534 channel ID
  int? get channelId => _channelId;

  void _updateState(VciConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  @override
  Future<List<VciDeviceInfo>> scanForDevices({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final devices = <VciDeviceInfo>[];
    _updateState(VciConnectionState.scanning);

    try {
      // Get paired devices
      final pairedDevices = await _bluetooth.getPairedDevices();

      for (final device in pairedDevices) {
        final name = device.name ?? '';
        final address = device.address;

        // Check for Autel VCI characteristics
        final isAutelVci = _isAutelDevice(name, address);

        if (isAutelVci) {
          devices.add(VciDeviceInfo(
            id: address,
            name: name,
            type: VciDeviceType.autelVci,
            signalStrength: -40, // Prioritize Autel devices
            platformDevice: device,
            description: 'Autel VCI ($address)',
          ));
        }
      }

      // Sort by signal strength (Autel devices first)
      devices.sort((a, b) => a.signalStrength.compareTo(b.signalStrength));
    } catch (e) {
      print('Error scanning for Autel VCI devices: $e');
    }

    _updateState(VciConnectionState.disconnected);
    return devices;
  }

  /// Check if a device is likely an Autel VCI
  bool _isAutelDevice(String name, String address) {
    final lowerName = name.toLowerCase();

    // Check name patterns
    if (lowerName.startsWith('maxi-') ||
        lowerName.contains('autel') ||
        lowerName.contains('maxisys') ||
        lowerName.contains('maxiim') ||
        lowerName.contains('maxicheck') ||
        lowerName.contains('maxidiag')) {
      return true;
    }

    // Check OUI (Autel's Bluetooth module manufacturer)
    if (address.toUpperCase().startsWith(AutelDeviceId.btOui)) {
      return true;
    }

    return false;
  }

  @override
  Future<void> connect(VciDeviceInfo device) async {
    if (_state == VciConnectionState.connected) {
      await disconnect();
    }

    _updateState(VciConnectionState.connecting);

    try {
      final address = device.id;
      print('Connecting to Autel VCI: $address');

      // Connect using Bluetooth Classic SPP
      final connected =
          await _bluetooth.connect(address, AutelProtocol.sppUuid);

      if (!connected) {
        throw VciException('Failed to establish Bluetooth connection');
      }

      _connectedDevice = device.platformDevice as Device?;
      _connectedDevice ??= Device(name: device.name, address: address);

      // Listen for incoming data
      _inputSubscription = _bluetooth.onDeviceDataReceived().listen(
        _handleIncomingData,
        onError: (error) {
          print('Bluetooth error: $error');
          _handleDisconnection();
        },
      );

      // Listen for connection status changes
      _bluetooth.onDeviceStatusChanged().listen((status) {
        if (status == Device.disconnected) {
          _handleDisconnection();
        }
      });

      _updateState(VciConnectionState.connected);

      // Initialize Autel VCI
      await _initializeAutelVci();
    } catch (e) {
      print('Autel VCI connection error: $e');
      _updateState(VciConnectionState.error);
      await disconnect();
      throw VciException('Connection failed: $e');
    }
  }

  /// Handle incoming data from Bluetooth
  void _handleIncomingData(Uint8List data) {
    // Add to receive buffer
    _receiveBuffer.addAll(data);
    _responseController.add(data.toList());

    // Try to parse complete packets
    _processReceiveBuffer();
  }

  /// Process buffered data looking for complete packets
  void _processReceiveBuffer() {
    while (_receiveBuffer.isNotEmpty) {
      // Check if we have a valid packet header
      if (!AutelPacketParser.hasValidMagic(_receiveBuffer)) {
        // Look for magic bytes
        int magicStart = -1;
        for (int i = 0; i < _receiveBuffer.length - 4; i++) {
          if ((_receiveBuffer[i] == 0x00 || _receiveBuffer[i] == 0x55) &&
              AutelPacketParser.hasValidMagic(_receiveBuffer.sublist(i))) {
            magicStart = i;
            break;
          }
        }

        if (magicStart > 0) {
          // Discard bytes before magic
          _receiveBuffer.removeRange(0, magicStart);
        } else if (magicStart < 0) {
          // No magic found, keep last few bytes
          if (_receiveBuffer.length > 8) {
            _receiveBuffer.removeRange(0, _receiveBuffer.length - 8);
          }
          break;
        }
      }

      // Check expected packet length
      final expectedLen = AutelPacketParser.getExpectedLength(_receiveBuffer);
      if (expectedLen == null) {
        break; // Not enough data for header
      }

      if (_receiveBuffer.length < expectedLen) {
        break; // Wait for more data
      }

      // Extract complete packet
      final packetData = Uint8List.fromList(_receiveBuffer.sublist(0, expectedLen));
      _receiveBuffer.removeRange(0, expectedLen);

      // Parse packet
      final packet = AutelPacketParser.parse(packetData);
      if (packet != null) {
        _handlePacket(packet);
      }
    }
  }

  /// Handle a parsed packet
  void _handlePacket(AutelPacket packet) {
    print('Received: $packet');

    // Complete pending response if session ID matches
    final completer = _pendingResponses.remove(packet.sessionId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(packet);
    }
  }

  /// Initialize Autel VCI connection
  Future<void> _initializeAutelVci() async {
    try {
      // Send identification request
      _packetBuilder.newSession();
      final identifyReq = _packetBuilder.buildIdentifyRequest();
      final identifyResp = await _sendAndWaitForResponse(
        identifyReq,
        _packetBuilder.sessionId,
      );

      if (identifyResp.isSuccess) {
        _vendorId = identifyResp.payloadAsString;
        print('Autel VCI identified: $_vendorId');
      }

      // Get firmware version
      _packetBuilder.newSession();
      final versionReq = _packetBuilder.buildGetVersionRequest();
      final versionResp = await _sendAndWaitForResponse(
        versionReq,
        _packetBuilder.sessionId,
      );

      if (versionResp.isSuccess) {
        _firmwareVersion = versionResp.payloadAsString;
        print('Firmware version: $_firmwareVersion');
      }

      print('Autel VCI initialized successfully');
    } catch (e) {
      print('Autel VCI initialization warning: $e');
      // Don't throw - partial initialization is OK
    }
  }

  void _handleDisconnection() {
    _inputSubscription?.cancel();
    _inputSubscription = null;
    _connectedDevice = null;
    _receiveBuffer.clear();

    // Complete all pending responses with error
    for (final completer in _pendingResponses.values) {
      if (!completer.isCompleted) {
        completer.completeError(VciException('Connection lost'));
      }
    }
    _pendingResponses.clear();

    _channelId = null;
    _updateState(VciConnectionState.disconnected);
  }

  @override
  Future<void> disconnect() async {
    try {
      // Send disconnect command if connected
      if (_state == VciConnectionState.connected) {
        try {
          _packetBuilder.newSession();
          final disconnectReq = _packetBuilder.buildDisconnectRequest();
          await _bluetooth.write(String.fromCharCodes(disconnectReq));
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (_) {}
      }

      _inputSubscription?.cancel();
      _inputSubscription = null;

      await _bluetooth.disconnect();

      _connectedDevice = null;
      _receiveBuffer.clear();
      _pendingResponses.clear();
      _channelId = null;
      _sessionManager.reset();
      _updateState(VciConnectionState.disconnected);
    } catch (e) {
      print('Error disconnecting: $e');
      _updateState(VciConnectionState.disconnected);
    }
  }

  /// Send packet and wait for response with matching session ID
  Future<AutelPacket> _sendAndWaitForResponse(
    Uint8List packet,
    int sessionId, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final completer = Completer<AutelPacket>();
    _pendingResponses[sessionId] = completer;

    try {
      // Send packet
      await _bluetooth.write(String.fromCharCodes(packet));

      // Wait for response
      return await completer.future.timeout(timeout);
    } catch (e) {
      _pendingResponses.remove(sessionId);
      if (e is TimeoutException) {
        throw VciException('Response timeout');
      }
      rethrow;
    }
  }

  @override
  Future<List<int>> sendCommand(
    List<int> command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isConnected) {
      throw VciException('Not connected');
    }

    // Build custom packet
    _packetBuilder.newSession();
    final packet = _packetBuilder.buildCustomRequest(
      command: command.isNotEmpty ? command[0] : 0,
      subCommand: command.length > 1 ? command[1] : 0,
      payload: Uint8List.fromList(command.length > 2 ? command.sublist(2) : []),
    );

    final response = await _sendAndWaitForResponse(
      packet,
      _packetBuilder.sessionId,
      timeout: timeout,
    );

    return response.payload.toList();
  }

  @override
  Future<String> sendATCommand(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Autel VCI doesn't use AT commands
    // Convert common AT commands to J2534 equivalents
    throw VciException('AT commands not supported on Autel VCI. Use J2534 API.');
  }

  // ==================== J2534 PassThru API ====================

  /// Open a J2534 channel for a specific protocol
  Future<int> passThruOpen({required int protocolId}) async {
    if (!isConnected) {
      throw VciException('Not connected');
    }

    _packetBuilder.newSession();
    final req = _packetBuilder.buildPassThruOpenRequest(protocolId: protocolId);
    final resp = await _sendAndWaitForResponse(req, _packetBuilder.sessionId);

    if (!resp.isSuccess) {
      throw VciException('PassThruOpen failed: ${resp.command}');
    }

    // Extract channel ID from response
    if (resp.payload.length >= 4) {
      _channelId = resp.payload[0] |
          (resp.payload[1] << 8) |
          (resp.payload[2] << 16) |
          (resp.payload[3] << 24);
      return _channelId!;
    }

    throw VciException('Invalid PassThruOpen response');
  }

  /// Close a J2534 channel
  Future<void> passThruClose({int? channelId}) async {
    final cid = channelId ?? _channelId;
    if (cid == null) {
      throw VciException('No channel open');
    }

    _packetBuilder.newSession();
    final req = _packetBuilder.buildPassThruCloseRequest(channelId: cid);
    final resp = await _sendAndWaitForResponse(req, _packetBuilder.sessionId);

    if (!resp.isSuccess) {
      throw VciException('PassThruClose failed');
    }

    if (cid == _channelId) {
      _channelId = null;
    }
  }

  /// Connect to vehicle with specific protocol settings
  Future<void> passThruConnect({
    required int protocolId,
    int flags = 0,
    int baudrate = 500000,
  }) async {
    if (!isConnected) {
      throw VciException('Not connected');
    }

    _packetBuilder.newSession();
    final req = _packetBuilder.buildPassThruConnectRequest(
      protocolId: protocolId,
      flags: flags,
      baudrate: baudrate,
    );
    final resp = await _sendAndWaitForResponse(req, _packetBuilder.sessionId);

    if (!resp.isSuccess) {
      throw VciException('PassThruConnect failed');
    }
  }

  /// Disconnect from vehicle
  Future<void> passThruDisconnect({int? channelId}) async {
    final cid = channelId ?? _channelId;
    if (cid == null) return;

    _packetBuilder.newSession();
    final req = _packetBuilder.buildPassThruDisconnectRequest(channelId: cid);
    await _sendAndWaitForResponse(req, _packetBuilder.sessionId);
  }

  /// Read messages from vehicle
  Future<List<Uint8List>> passThruReadMsgs({
    int? channelId,
    int numMsgs = 1,
    int timeout = 1000,
  }) async {
    final cid = channelId ?? _channelId;
    if (cid == null) {
      throw VciException('No channel open');
    }

    _packetBuilder.newSession();
    final req = _packetBuilder.buildPassThruReadMsgsRequest(
      channelId: cid,
      numMsgs: numMsgs,
      timeout: timeout,
    );
    final resp = await _sendAndWaitForResponse(
      req,
      _packetBuilder.sessionId,
      timeout: Duration(milliseconds: timeout + 1000),
    );

    if (!resp.isSuccess) {
      if (resp.command == AutelStatus.errBufferEmpty) {
        return []; // No messages available
      }
      throw VciException('PassThruReadMsgs failed');
    }

    // Parse messages from response
    return _parseMessages(resp.payload);
  }

  /// Write messages to vehicle
  Future<void> passThruWriteMsgs({
    int? channelId,
    required List<int> data,
    int timeout = 1000,
  }) async {
    final cid = channelId ?? _channelId;
    if (cid == null) {
      throw VciException('No channel open');
    }

    _packetBuilder.newSession();
    final req = _packetBuilder.buildPassThruWriteMsgsRequest(
      channelId: cid,
      data: data,
      timeout: timeout,
    );
    final resp = await _sendAndWaitForResponse(
      req,
      _packetBuilder.sessionId,
      timeout: Duration(milliseconds: timeout + 1000),
    );

    if (!resp.isSuccess) {
      throw VciException('PassThruWriteMsgs failed');
    }
  }

  /// Start a message filter
  Future<int> passThruStartMsgFilter({
    int? channelId,
    required int filterType,
    List<int>? maskMsg,
    List<int>? patternMsg,
    List<int>? flowControlMsg,
  }) async {
    final cid = channelId ?? _channelId;
    if (cid == null) {
      throw VciException('No channel open');
    }

    _packetBuilder.newSession();
    final req = _packetBuilder.buildPassThruStartMsgFilterRequest(
      channelId: cid,
      filterType: filterType,
      maskMsg: maskMsg,
      patternMsg: patternMsg,
      flowControlMsg: flowControlMsg,
    );
    final resp = await _sendAndWaitForResponse(req, _packetBuilder.sessionId);

    if (!resp.isSuccess) {
      throw VciException('PassThruStartMsgFilter failed');
    }

    // Extract filter ID from response
    if (resp.payload.length >= 4) {
      return resp.payload[0] |
          (resp.payload[1] << 8) |
          (resp.payload[2] << 16) |
          (resp.payload[3] << 24);
    }

    return 0;
  }

  /// Stop a message filter
  Future<void> passThruStopMsgFilter({
    int? channelId,
    required int filterId,
  }) async {
    final cid = channelId ?? _channelId;
    if (cid == null) {
      throw VciException('No channel open');
    }

    _packetBuilder.newSession();
    final req = _packetBuilder.buildPassThruStopMsgFilterRequest(
      channelId: cid,
      filterId: filterId,
    );
    final resp = await _sendAndWaitForResponse(req, _packetBuilder.sessionId);

    if (!resp.isSuccess) {
      throw VciException('PassThruStopMsgFilter failed');
    }
  }

  /// Perform IOCTL operation
  Future<Uint8List> passThruIoctl({
    int? channelId,
    required int ioctlId,
    Uint8List? input,
  }) async {
    final cid = channelId ?? _channelId;
    if (cid == null && ioctlId != J2534Ioctl.readVbatt) {
      throw VciException('No channel open');
    }

    _packetBuilder.newSession();
    final req = _packetBuilder.buildPassThruIoctlRequest(
      channelId: cid ?? 0,
      ioctlId: ioctlId,
      input: input,
    );
    final resp = await _sendAndWaitForResponse(req, _packetBuilder.sessionId);

    if (!resp.isSuccess) {
      throw VciException('PassThruIoctl failed');
    }

    return resp.payload;
  }

  /// Read battery voltage
  Future<double> readBatteryVoltage() async {
    final result = await passThruIoctl(
      channelId: 0,
      ioctlId: J2534Ioctl.readVbatt,
    );

    if (result.length >= 4) {
      final millivolts = result[0] |
          (result[1] << 8) |
          (result[2] << 16) |
          (result[3] << 24);
      return millivolts / 1000.0;
    }

    throw VciException('Invalid voltage response');
  }

  /// Clear TX buffer
  Future<void> clearTxBuffer({int? channelId}) async {
    await passThruIoctl(
      channelId: channelId,
      ioctlId: J2534Ioctl.clearTxBuffer,
    );
  }

  /// Clear RX buffer
  Future<void> clearRxBuffer({int? channelId}) async {
    await passThruIoctl(
      channelId: channelId,
      ioctlId: J2534Ioctl.clearRxBuffer,
    );
  }

  /// Parse multiple messages from response payload
  List<Uint8List> _parseMessages(Uint8List payload) {
    final messages = <Uint8List>[];

    if (payload.length < 4) return messages;

    int offset = 0;

    // First 4 bytes might be message count
    final numMsgs = payload[offset] |
        (payload[offset + 1] << 8) |
        (payload[offset + 2] << 16) |
        (payload[offset + 3] << 24);
    offset += 4;

    for (int i = 0; i < numMsgs && offset < payload.length; i++) {
      // Each message has: length (4 bytes), data
      if (offset + 4 > payload.length) break;

      final msgLen = payload[offset] |
          (payload[offset + 1] << 8) |
          (payload[offset + 2] << 16) |
          (payload[offset + 3] << 24);
      offset += 4;

      if (offset + msgLen > payload.length) break;

      messages.add(Uint8List.sublistView(payload, offset, offset + msgLen));
      offset += msgLen;
    }

    return messages;
  }


  // ==================== UDS Command Interface ====================

  /// Send UDS command to specific module address
  /// Supports multi-manufacturer CAN addressing schemes
  @override
  Future<List<int>> sendUDSCommand(
    int moduleAddress,
    List<int> data, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isConnected) {
      throw VciException('Not connected');
    }

    // Calculate CAN IDs based on module address and manufacturer conventions
    final canIds = _calculateCanIds(moduleAddress);
    final txId = canIds['tx']!;
    final rxId = canIds['rx']!;
    final isExtended = canIds['extended'] == 1;

    // Check if we need to open a new channel or reconfigure existing one
    if (_udsChannelId == null || _currentModuleAddress != moduleAddress) {
      await _setupUdsChannel(txId, rxId, isExtended);
      _currentModuleAddress = moduleAddress;
    }

    // Send UDS request
    final response = await _sendUdsRequest(data, rxId, timeout);
    return response;
  }

  /// Calculate CAN TX/RX IDs based on module address
  /// Supports multiple manufacturer conventions
  Map<String, int> _calculateCanIds(int moduleAddress) {
    // Functional addressing (broadcast to all modules)
    if (moduleAddress == 0x7DF) {
      return {'tx': 0x7DF, 'rx': 0x7E8, 'extended': 0};
    }

    // Check for extended (29-bit) addressing
    if (moduleAddress > 0x7FF) {
      // ISO 15765-4 extended addressing
      // Physical: 18DA00F1 -> 18DAF100 pattern
      final targetByte = moduleAddress & 0xFF;
      return {
        'tx': 0x18DA00F1 | (targetByte << 8),
        'rx': 0x18DAF100 | targetByte,
        'extended': 1,
      };
    }

    // Standard 11-bit addressing patterns
    int txId, rxId;

    // GM, Ford, Chrysler pattern: 7E0-7E7 -> 7E8-7EF
    if (moduleAddress >= 0x7E0 && moduleAddress <= 0x7E7) {
      txId = moduleAddress;
      rxId = moduleAddress + 0x08;
    }
    // Toyota, Honda pattern: 7C0-7C7 -> 7C8-7CF
    else if (moduleAddress >= 0x7C0 && moduleAddress <= 0x7C7) {
      txId = moduleAddress;
      rxId = moduleAddress + 0x08;
    }
    // European (VAG, BMW, Mercedes) pattern: 700-77F
    else if (moduleAddress >= 0x700 && moduleAddress <= 0x77F) {
      txId = moduleAddress;
      rxId = moduleAddress + 0x08;
      // Some BMW modules use +0x10 offset
      if ((moduleAddress & 0x0F) >= 0x08) {
        rxId = moduleAddress + 0x10;
      }
    }
    // Nissan pattern: 7E0-7E7 (same as GM)
    else if (moduleAddress >= 0x700 && moduleAddress <= 0x7FF) {
      txId = moduleAddress;
      rxId = moduleAddress + 0x08;
    }
    // Generic fallback: assume address is TX, add 8 for RX
    else {
      txId = moduleAddress;
      rxId = (moduleAddress < 0x800) ? moduleAddress + 0x08 : moduleAddress + 0x01;
    }

    return {'tx': txId, 'rx': rxId, 'extended': 0};
  }

  /// Setup UDS channel with ISO 15765 protocol
  Future<void> _setupUdsChannel(int txId, int rxId, bool isExtended) async {
    // Close existing channel if open
    await closeUdsChannel();

    // Determine protocol flags
    int flags = 0;
    if (isExtended) {
      flags |= 0x100; // CAN_29BIT_ID flag
    }

    // Try to connect at current baud rate
    try {
      // Open ISO 15765 channel
      _packetBuilder.newSession();
      final openReq = _packetBuilder.buildPassThruOpenRequest(
        protocolId: J2534Protocol.iso15765,
      );
      final openResp = await _sendAndWaitForResponse(openReq, _packetBuilder.sessionId);

      if (!openResp.isSuccess) {
        throw VciException('Failed to open ISO15765 channel');
      }

      if (openResp.payload.length >= 4) {
        _udsChannelId = openResp.payload[0] |
            (openResp.payload[1] << 8) |
            (openResp.payload[2] << 16) |
            (openResp.payload[3] << 24);
      }

      // Connect with protocol settings
      _packetBuilder.newSession();
      final connectReq = _packetBuilder.buildPassThruConnectRequest(
        protocolId: J2534Protocol.iso15765,
        flags: flags,
        baudrate: _udsBaudRate,
      );
      final connectResp = await _sendAndWaitForResponse(connectReq, _packetBuilder.sessionId);

      if (!connectResp.isSuccess) {
        // Try fallback baud rate
        if (_udsBaudRate == 500000) {
          _udsBaudRate = 250000;
          _packetBuilder.newSession();
          final retryReq = _packetBuilder.buildPassThruConnectRequest(
            protocolId: J2534Protocol.iso15765,
            flags: flags,
            baudrate: _udsBaudRate,
          );
          final retryResp = await _sendAndWaitForResponse(retryReq, _packetBuilder.sessionId);
          if (!retryResp.isSuccess) {
            throw VciException('Failed to connect at 250kbps');
          }
        } else {
          throw VciException('Failed to connect to vehicle');
        }
      }

      // Setup flow control filter for ISO-TP
      await _setupFlowControlFilter(txId, rxId, isExtended);

    } catch (e) {
      await closeUdsChannel();
      rethrow;
    }
  }

  /// Setup ISO-TP flow control filter
  Future<void> _setupFlowControlFilter(int txId, int rxId, bool isExtended) async {
    if (_udsChannelId == null) return;

    final maskLen = isExtended ? 4 : 2;
    final mask = isExtended
        ? [0xFF, 0xFF, 0xFF, 0xFF]  // Match all 29 bits
        : [0xFF, 0x07];             // Match 11-bit ID

    // Pattern: match RX ID
    final pattern = isExtended
        ? [(rxId >> 24) & 0xFF, (rxId >> 16) & 0xFF, (rxId >> 8) & 0xFF, rxId & 0xFF]
        : [(rxId >> 8) & 0xFF, rxId & 0xFF];

    // Flow control: TX ID for flow control frames
    final flowControl = isExtended
        ? [(txId >> 24) & 0xFF, (txId >> 16) & 0xFF, (txId >> 8) & 0xFF, txId & 0xFF]
        : [(txId >> 8) & 0xFF, txId & 0xFF];

    _packetBuilder.newSession();
    final filterReq = _packetBuilder.buildPassThruStartMsgFilterRequest(
      channelId: _udsChannelId!,
      filterType: J2534FilterType.flowControl,
      maskMsg: mask,
      patternMsg: pattern,
      flowControlMsg: flowControl,
    );
    final filterResp = await _sendAndWaitForResponse(filterReq, _packetBuilder.sessionId);

    if (filterResp.isSuccess && filterResp.payload.length >= 4) {
      _udsFilterId = filterResp.payload[0] |
          (filterResp.payload[1] << 8) |
          (filterResp.payload[2] << 16) |
          (filterResp.payload[3] << 24);
    }
  }

  /// Send UDS request and handle response
  Future<List<int>> _sendUdsRequest(List<int> data, int expectedRxId, Duration timeout) async {
    if (_udsChannelId == null) {
      throw VciException('UDS channel not open');
    }

    // Clear buffers
    await clearTxBuffer(channelId: _udsChannelId);
    await clearRxBuffer(channelId: _udsChannelId);

    // Send request
    await passThruWriteMsgs(
      channelId: _udsChannelId,
      data: data,
      timeout: timeout.inMilliseconds,
    );

    // Read response with NRC handling
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < timeout) {
      try {
        final messages = await passThruReadMsgs(
          channelId: _udsChannelId,
          numMsgs: 1,
          timeout: 500,
        );

        if (messages.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 50));
          continue;
        }

        final response = messages.first.toList();

        // Check for negative response
        if (response.isNotEmpty && response[0] == 0x7F) {
          if (response.length >= 3) {
            final nrc = response[2];

            // NRC 0x78: Response Pending - keep waiting
            if (nrc == 0x78) {
              continue;
            }

            // NRC 0x21: Busy, Repeat Request - retry after delay
            if (nrc == 0x21) {
              await Future.delayed(const Duration(milliseconds: 100));
              await passThruWriteMsgs(
                channelId: _udsChannelId,
                data: data,
                timeout: timeout.inMilliseconds,
              );
              continue;
            }
          }
        }

        // Valid response received
        return response;

      } catch (e) {
        // Timeout on read, continue loop
        if (e.toString().contains('timeout') || e.toString().contains('Timeout')) {
          continue;
        }
        rethrow;
      }
    }

    throw VciException('UDS response timeout');
  }

  /// Close UDS channel and cleanup
  Future<void> closeUdsChannel() async {
    if (_udsFilterId != null && _udsChannelId != null) {
      try {
        await passThruStopMsgFilter(
          channelId: _udsChannelId,
          filterId: _udsFilterId!,
        );
      } catch (_) {}
      _udsFilterId = null;
    }

    if (_udsChannelId != null) {
      try {
        await passThruDisconnect(channelId: _udsChannelId);
        await passThruClose(channelId: _udsChannelId);
      } catch (_) {}
      _udsChannelId = null;
    }

    _currentModuleAddress = null;
  }

  @override
  void dispose() {
    closeUdsChannel();
    disconnect();
    _responseController.close();
    _stateController.close();
  }
}
