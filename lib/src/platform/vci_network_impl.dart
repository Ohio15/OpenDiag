import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'vci_interface.dart';

/// Network-based VCI implementation for connecting to mock or remote VCI servers
/// This allows testing without physical hardware by connecting to a TCP server
class NetworkVciImpl implements VciInterface {
  Socket? _socket;
  final _responseController = StreamController<List<int>>.broadcast();
  final _stateController = StreamController<VciConnectionState>.broadcast();
  VciConnectionState _state = VciConnectionState.disconnected;
  final List<int> _buffer = [];
  Completer<List<int>>? _responseCompleter;
  Timer? _timeoutTimer;

  @override
  Stream<List<int>> get responseStream => _responseController.stream;

  @override
  Stream<VciConnectionState> get connectionStateStream =>
      _stateController.stream;

  @override
  VciConnectionState get state => _state;

  @override
  bool get isConnected => _state == VciConnectionState.connected;

  void _setState(VciConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  @override
  Future<List<VciDeviceInfo>> scanForDevices({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _setState(VciConnectionState.scanning);

    final devices = <VciDeviceInfo>[];

    // Default mock server locations to scan
    final serversToScan = [
      {'host': 'localhost', 'port': 35000},
      {'host': '127.0.0.1', 'port': 35000},
      {'host': '192.168.1.1', 'port': 35000}, // Common router/gateway
    ];

    for (final server in serversToScan) {
      try {
        final socket = await Socket.connect(
          server['host'] as String,
          server['port'] as int,
          timeout: const Duration(seconds: 2),
        );

        // Successfully connected, add to devices
        devices.add(VciDeviceInfo(
          id: '${server['host']}:${server['port']}',
          name: 'Network VCI (${server['host']}:${server['port']})',
          type: VciDeviceType.autelVci,
          description: 'TCP/IP connected VCI server',
        ));

        await socket.close();
      } catch (e) {
        // Server not available, skip
      }
    }

    _setState(VciConnectionState.disconnected);
    return devices;
  }

  /// Scan for network VCI with custom address
  Future<VciDeviceInfo?> scanCustomAddress(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );

      await socket.close();

      return VciDeviceInfo(
        id: '$host:$port',
        name: 'Network VCI ($host:$port)',
        type: VciDeviceType.autelVci,
        description: 'TCP/IP connected VCI server',
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> connect(VciDeviceInfo device) async {
    if (_state == VciConnectionState.connected) {
      await disconnect();
    }

    _setState(VciConnectionState.connecting);

    try {
      // Parse host:port from device ID
      final parts = device.id.split(':');
      if (parts.length != 2) {
        throw VciException('Invalid device ID format. Expected host:port');
      }

      final host = parts[0];
      final port = int.parse(parts[1]);

      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );

      _socket!.listen(
        _onDataReceived,
        onError: (error) {
          _setState(VciConnectionState.error);
          _responseCompleter?.completeError(
              VciException('Socket error: $error'));
        },
        onDone: () {
          _setState(VciConnectionState.disconnected);
        },
        cancelOnError: false,
      );

      _setState(VciConnectionState.connected);

      // Wait for initial prompt
      await Future.delayed(const Duration(milliseconds: 500));

      // Initialize connection
      await _initializeConnection();
    } catch (e) {
      _setState(VciConnectionState.error);
      throw VciException('Failed to connect: $e');
    }
  }

  Future<void> _initializeConnection() async {
    // Reset and configure the adapter
    try {
      await sendATCommand('ATZ', timeout: const Duration(seconds: 3));
      await sendATCommand('ATE0'); // Echo off
      await sendATCommand('ATL0'); // Linefeeds off
      await sendATCommand('ATS0'); // Spaces off
      await sendATCommand('ATH0'); // Headers off
      await sendATCommand('ATSP0'); // Auto protocol
    } catch (e) {
      // Initialization commands may time out on first connect, that's OK
    }
  }

  void _onDataReceived(Uint8List data) {
    _buffer.addAll(data);
    _responseController.add(data);

    // Check if we have a complete response (ends with >)
    final text = utf8.decode(_buffer, allowMalformed: true);
    if (text.contains('>')) {
      _timeoutTimer?.cancel();
      _timeoutTimer = null;

      final response = _buffer.toList();
      _buffer.clear();

      _responseCompleter?.complete(response);
      _responseCompleter = null;
    }
  }

  @override
  Future<void> disconnect() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _responseCompleter?.completeError(VciException('Disconnected'));
    _responseCompleter = null;

    await _socket?.close();
    _socket = null;
    _buffer.clear();

    _setState(VciConnectionState.disconnected);
  }

  @override
  Future<List<int>> sendCommand(
    List<int> command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isConnected || _socket == null) {
      throw VciException('Not connected');
    }

    // Wait for any pending response
    if (_responseCompleter != null) {
      await _responseCompleter!.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () => <int>[],
      );
    }

    _buffer.clear();
    _responseCompleter = Completer<List<int>>();

    // Set up timeout
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(timeout, () {
      if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
        _responseCompleter!.completeError(VciException('Command timeout'));
        _responseCompleter = null;
      }
    });

    // Send command with carriage return
    _socket!.add([...command, 0x0D]);

    try {
      return await _responseCompleter!.future;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<String> sendATCommand(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final bytes = utf8.encode(command);
    final response = await sendCommand(bytes, timeout: timeout);

    // Parse response - remove echo and prompt
    String text = utf8.decode(response, allowMalformed: true);

    // Remove the command echo if present
    if (text.startsWith(command)) {
      text = text.substring(command.length);
    }

    // Clean up response
    text = text
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n+'), '\n')
        .replaceAll('>', '')
        .trim();

    return text;
  }

  @override
  Future<List<int>> sendUDSCommand(
    int moduleAddress,
    List<int> data, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // For WiFi ELM327, use AT commands to set header and send data
    // Set CAN header to module address
    await sendATCommand('AT SH ${moduleAddress.toRadixString(16).padLeft(3, '0')}');

    // Convert data to hex string
    final hexData = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

    // Send command and parse hex response
    final response = await sendATCommand(hexData, timeout: timeout);

    // Parse hex response back to bytes
    final bytes = <int>[];
    final cleanResponse = response.replaceAll(' ', '').replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    for (var i = 0; i < cleanResponse.length - 1; i += 2) {
      bytes.add(int.parse(cleanResponse.substring(i, i + 2), radix: 16));
    }

    return bytes;
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _socket?.close();
    _responseController.close();
    _stateController.close();
  }
}
