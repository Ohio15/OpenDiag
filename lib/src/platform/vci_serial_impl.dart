import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'vci_interface.dart';

/// Serial port implementation of VCI interface
/// Used on Windows/Linux/macOS for USB and Bluetooth (paired) adapters
class VciSerialImpl implements VciInterface {
  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription? _readerSubscription;

  final _responseController = StreamController<List<int>>.broadcast();
  final _connectionStateController = StreamController<VciConnectionState>.broadcast();

  VciConnectionState _state = VciConnectionState.disconnected;

  // Common baud rates for OBD adapters
  static const List<int> commonBaudRates = [38400, 115200, 9600, 57600, 19200];
  int _baudRate = 38400;

  @override
  Stream<List<int>> get responseStream => _responseController.stream;

  @override
  Stream<VciConnectionState> get connectionStateStream => _connectionStateController.stream;

  @override
  VciConnectionState get state => _state;

  @override
  bool get isConnected => _state == VciConnectionState.connected;

  /// Set the baud rate for serial communication
  void setBaudRate(int baudRate) {
    _baudRate = baudRate;
  }

  @override
  Future<List<VciDeviceInfo>> scanForDevices({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _updateState(VciConnectionState.scanning);

    final devices = <VciDeviceInfo>[];
    final availablePorts = SerialPort.availablePorts;

    for (final portName in availablePorts) {
      try {
        final port = SerialPort(portName);
        final description = port.description ?? '';
        final manufacturer = port.manufacturer ?? '';
        final serialNumber = port.serialNumber ?? '';

        final deviceType = _identifyDeviceType(description, manufacturer);

        devices.add(VciDeviceInfo(
          id: portName,
          name: _formatPortName(portName, description),
          type: deviceType,
          signalStrength: 0,
          platformDevice: portName,
          description: _buildDescription(description, manufacturer, serialNumber),
        ));

        port.dispose();
      } catch (e) {
        // Skip ports that can't be accessed
      }
    }

    _updateState(VciConnectionState.disconnected);

    return devices;
  }

  String _formatPortName(String portName, String description) {
    if (description.isNotEmpty) {
      return '$portName - $description';
    }
    return portName;
  }

  String _buildDescription(String description, String manufacturer, String serialNumber) {
    final parts = <String>[];
    if (manufacturer.isNotEmpty) parts.add('Manufacturer: $manufacturer');
    if (serialNumber.isNotEmpty) parts.add('S/N: $serialNumber');
    if (description.isNotEmpty && parts.isEmpty) parts.add(description);
    return parts.join(', ');
  }

  VciDeviceType _identifyDeviceType(String description, String manufacturer) {
    final combined = '$description $manufacturer'.toUpperCase();

    if (combined.contains('AUTEL') || combined.contains('MAXI')) {
      return VciDeviceType.autelVci;
    } else if (combined.contains('ELM') ||
        combined.contains('OBD') ||
        combined.contains('FTDI') ||
        combined.contains('CH340') ||
        combined.contains('CP210') ||
        combined.contains('PL2303') ||
        combined.contains('PROLIFIC') ||
        combined.contains('BLUETOOTH') ||
        combined.contains('SERIAL')) {
      return VciDeviceType.elm327;
    }

    // Default to serial port type for unknown devices
    return VciDeviceType.serialPort;
  }

  @override
  Future<void> connect(VciDeviceInfo device) async {
    final portName = device.platformDevice as String?;
    if (portName == null) {
      throw VciException('Invalid device');
    }

    try {
      _updateState(VciConnectionState.connecting);

      _port = SerialPort(portName);

      // Configure port settings
      final config = SerialPortConfig();
      config.baudRate = _baudRate;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      config.setFlowControl(SerialPortFlowControl.none);

      _port!.config = config;

      // Open the port
      if (!_port!.openReadWrite()) {
        throw VciException('Failed to open port: ${SerialPort.lastError}');
      }

      // Set up reader for incoming data
      _reader = SerialPortReader(_port!);
      _readerSubscription = _reader!.stream.listen(
        (data) {
          _responseController.add(data.toList());
        },
        onError: (error) {
          _handleDisconnection();
        },
      );

      _updateState(VciConnectionState.connected);

      // Initialize ELM327 adapter
      await _initializeAdapter();
    } catch (e) {
      _cleanup();
      _updateState(VciConnectionState.error);
      throw VciException('Failed to connect: $e');
    }
  }

  Future<void> _initializeAdapter() async {
    // Reset adapter
    try {
      await sendATCommand('ATZ', timeout: const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 500));

      // Disable echo
      await sendATCommand('ATE0', timeout: const Duration(seconds: 1));

      // Set protocol to auto
      await sendATCommand('ATSP0', timeout: const Duration(seconds: 1));
    } catch (e) {
      // Initialization commands may timeout on first connect, which is okay
    }
  }

  @override
  Future<List<int>> sendCommand(
    List<int> command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isConnected || _port == null) {
      throw VciException('Not connected to VCI');
    }

    final completer = Completer<List<int>>();
    final responseData = <int>[];

    // Listen for response
    final subscription = responseStream.listen((data) {
      responseData.addAll(data);

      // Check for end of response
      if (_isResponseComplete(responseData)) {
        if (!completer.isCompleted) {
          completer.complete(responseData);
        }
      }
    });

    // Send command
    _port!.write(Uint8List.fromList(command));

    // Wait for response with timeout
    try {
      final response = await completer.future.timeout(timeout);
      await subscription.cancel();
      return response;
    } on TimeoutException {
      await subscription.cancel();
      // Return what we have so far, or throw if empty
      if (responseData.isNotEmpty) {
        return responseData;
      }
      throw VciException('Command timeout');
    }
  }

  @override
  Future<String> sendATCommand(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final commandBytes = '$command\r'.codeUnits;
    final response = await sendCommand(commandBytes, timeout: timeout);
    return String.fromCharCodes(response)
        .replaceAll('\r', '')
        .replaceAll('>', '')
        .trim();
  }

  bool _isResponseComplete(List<int> data) {
    if (data.isEmpty) return false;

    // ELM327 ends with '>' prompt
    if (data.last == 0x3E) return true;

    // Check for carriage return at end
    if (data.last == 0x0D) return true;

    // Check for newline at end
    if (data.last == 0x0A) return true;

    return false;
  }

  @override
  Future<void> disconnect() async {
    _cleanup();
    _updateState(VciConnectionState.disconnected);
  }

  void _cleanup() {
    _readerSubscription?.cancel();
    _readerSubscription = null;
    _reader = null;

    if (_port != null && _port!.isOpen) {
      _port!.close();
    }
    _port?.dispose();
    _port = null;
  }

  void _handleDisconnection() {
    _cleanup();
    _updateState(VciConnectionState.disconnected);
  }

  void _updateState(VciConnectionState newState) {
    _state = newState;
    _connectionStateController.add(newState);
  }

  @override
  Future<List<int>> sendUDSCommand(
    int moduleAddress,
    List<int> data, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // For USB ELM327, use AT commands to set header and send data
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
    _cleanup();
    _responseController.close();
    _connectionStateController.close();
  }
}
