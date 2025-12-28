import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:bluetooth_classic/bluetooth_classic.dart';
import 'package:bluetooth_classic/models/device.dart';
import 'vci_interface.dart';

/// Bluetooth Classic (SPP) implementation for ELM327 adapters
/// This works with standard ELM327 adapters that use Bluetooth 2.0/2.1 SPP profile
class VciBluetoothClassicImpl implements VciInterface {
  final BluetoothClassic _bluetooth = BluetoothClassic();
  Device? _connectedDevice;

  // Non-nullable final controllers - same pattern as BLE implementation
  // These are created once and never recreated, so subscriptions stay valid
  final _responseController = StreamController<List<int>>.broadcast();
  final _stateController = StreamController<VciConnectionState>.broadcast();

  VciConnectionState _state = VciConnectionState.disconnected;
  StreamSubscription<Uint8List>? _inputSubscription;
  StreamSubscription<int>? _statusSubscription;
  final StringBuffer _responseBuffer = StringBuffer();
  Completer<String>? _responseCompleter;

  @override
  Stream<List<int>> get responseStream => _responseController.stream;

  @override
  Stream<VciConnectionState> get connectionStateStream => _stateController.stream;

  @override
  VciConnectionState get state => _state;

  @override
  bool get isConnected => _state == VciConnectionState.connected;

  void _updateState(VciConnectionState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
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
        // Filter for likely OBD adapters
        final name = device.name?.toLowerCase() ?? '';
        final isObd = name.contains('obd') ||
                      name.contains('elm') ||
                      name.contains('obdii') ||
                      name.contains('vlink') ||
                      name.contains('vgate') ||
                      name.contains('scan') ||
                      name.contains('car');

        devices.add(VciDeviceInfo(
          id: device.address,
          name: device.name ?? 'Unknown Device',
          type: isObd ? VciDeviceType.elm327Bluetooth : VciDeviceType.unknown,
          signalStrength: isObd ? -50 : -70, // Prioritize OBD devices
          platformDevice: device,
          description: 'Bluetooth Classic (${device.address})',
        ));
      }

      // Sort by signal strength (OBD devices first)
      devices.sort((a, b) => a.signalStrength.compareTo(b.signalStrength));

    } catch (e) {
      // Log but don't throw - return empty list
      print('Error scanning for Bluetooth Classic devices: $e');
    }

    _updateState(VciConnectionState.disconnected);
    return devices;
  }

  @override
  Future<void> connect(VciDeviceInfo device) async {
    if (_state == VciConnectionState.connected) {
      await disconnect();
    }

    _updateState(VciConnectionState.connecting);

    try {
      final address = device.id;
      print('Connecting to Bluetooth Classic device: $address');

      // Connect using the bluetooth_classic package
      final connected = await _bluetooth.connect(address, "00001101-0000-1000-8000-00805F9B34FB");

      if (!connected) {
        throw VciException('Failed to establish Bluetooth connection');
      }

      _connectedDevice = device.platformDevice as Device?;
      _connectedDevice ??= Device(name: device.name, address: address);

      // Listen for incoming data
      _inputSubscription = _bluetooth.onDeviceDataReceived().listen(
        (data) {
          if (!_responseController.isClosed) {
            _responseController.add(data.toList());
          }

          // Process for command responses
          final chars = String.fromCharCodes(data);
          _responseBuffer.write(chars);

          // Check if response is complete (ends with >)
          if (_responseBuffer.toString().contains('>')) {
            _responseCompleter?.complete(_responseBuffer.toString());
            _responseCompleter = null;
          }
        },
        onError: (error) {
          print('Bluetooth error: $error');
          _handleDisconnection();
        },
      );

      // Cancel previous status subscription if any
      await _statusSubscription?.cancel();

      // Listen for connection status changes
      _statusSubscription = _bluetooth.onDeviceStatusChanged().listen((status) {
        if (status == Device.disconnected) {
          _handleDisconnection();
        }
      });

      _updateState(VciConnectionState.connected);

      // Initialize ELM327
      await _initializeElm327();

    } catch (e) {
      print('Bluetooth Classic connection error: $e');
      _updateState(VciConnectionState.error);
      await disconnect();
      throw VciException('Connection failed: $e');
    }
  }

  Future<void> _initializeElm327() async {
    try {
      // Reset ELM327
      await sendATCommand('ATZ', timeout: const Duration(seconds: 2));
      await Future.delayed(const Duration(milliseconds: 500));

      // Turn echo off
      await sendATCommand('ATE0');
      await Future.delayed(const Duration(milliseconds: 100));

      // Turn linefeeds off
      await sendATCommand('ATL0');
      await Future.delayed(const Duration(milliseconds: 100));

      // Turn spaces off (more compact responses)
      await sendATCommand('ATS0');
      await Future.delayed(const Duration(milliseconds: 100));

      // Turn headers off
      await sendATCommand('ATH0');
      await Future.delayed(const Duration(milliseconds: 100));

      // Set protocol to auto
      await sendATCommand('ATSP0');
      await Future.delayed(const Duration(milliseconds: 100));

      print('ELM327 initialized successfully via Bluetooth Classic');
    } catch (e) {
      print('ELM327 initialization warning: $e');
      // Don't throw - some commands might fail on certain adapters
    }
  }

  void _handleDisconnection() {
    _inputSubscription?.cancel();
    _inputSubscription = null;
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _connectedDevice = null;
    _responseCompleter?.completeError(VciException('Connection lost'));
    _responseCompleter = null;
    _updateState(VciConnectionState.disconnected);
  }

  @override
  Future<void> disconnect() async {
    try {
      _inputSubscription?.cancel();
      _inputSubscription = null;
      _statusSubscription?.cancel();
      _statusSubscription = null;

      await _bluetooth.disconnect();

      _connectedDevice = null;
      _responseCompleter?.completeError(VciException('Disconnected'));
      _responseCompleter = null;
      _updateState(VciConnectionState.disconnected);
    } catch (e) {
      print('Error disconnecting: $e');
      _updateState(VciConnectionState.disconnected);
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

    try {
      _responseBuffer.clear();
      _responseCompleter = Completer<String>();

      // Send command
      await _bluetooth.write(Uint8List.fromList(command).toString());

      // Wait for response
      final response = await _responseCompleter!.future.timeout(timeout);
      return utf8.encode(response);
    } catch (e) {
      _responseCompleter = null;
      throw VciException('Command failed: $e');
    }
  }

  @override
  Future<String> sendATCommand(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isConnected) {
      throw VciException('Not connected');
    }

    try {
      _responseBuffer.clear();
      _responseCompleter = Completer<String>();

      // Add carriage return if not present
      final cmd = command.endsWith('\r') ? command : '$command\r';

      await _bluetooth.write(cmd);

      // Wait for response with > prompt
      final response = await _responseCompleter!.future.timeout(timeout);

      // Clean up response
      return response
          .replaceAll(command, '')
          .replaceAll(cmd, '')
          .replaceAll('\r', '')
          .replaceAll('\n', ' ')
          .replaceAll('>', '')
          .trim();
    } catch (e) {
      _responseCompleter = null;
      if (e is TimeoutException) {
        // Return partial response if we have one
        final partial = _responseBuffer.toString().trim();
        if (partial.isNotEmpty) {
          return partial.replaceAll('>', '').trim();
        }
      }
      throw VciException('AT command failed: $e');
    }
  }

  @override
  Future<List<int>> sendUDSCommand(
    int moduleAddress,
    List<int> data, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // For ELM327 over Bluetooth Classic, use AT commands to set header and send data
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
    disconnect();
    _responseController.close();
    _stateController.close();
  }
}
