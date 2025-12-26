import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// VCI (Vehicle Communication Interface) connection manager
/// Supports Autel VCI dongles and generic ELM327 adapters
class VCIConnection {
  static const String autelVciPrefix = 'Autel';
  static const String autelServiceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
  static const String autelWriteCharUuid = '0000fff2-0000-1000-8000-00805f9b34fb';
  static const String autelNotifyCharUuid = '0000fff1-0000-1000-8000-00805f9b34fb';

  // Standard SPP UUID for ELM327 adapters
  static const String sppServiceUuid = '00001101-0000-1000-8000-00805f9b34fb';

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription? _notifySubscription;

  final _responseController = StreamController<List<int>>.broadcast();
  final _connectionStateController = StreamController<VCIConnectionState>.broadcast();

  Stream<List<int>> get responseStream => _responseController.stream;
  Stream<VCIConnectionState> get connectionStateStream => _connectionStateController.stream;

  VCIConnectionState _state = VCIConnectionState.disconnected;
  VCIConnectionState get state => _state;

  bool get isConnected => _state == VCIConnectionState.connected;

  /// Scan for available VCI devices
  Future<List<VCIDevice>> scanForDevices({Duration timeout = const Duration(seconds: 10)}) async {
    final devices = <VCIDevice>[];

    // Check if Bluetooth is available and on
    if (await FlutterBluePlus.isSupported == false) {
      throw VCIException('Bluetooth is not supported on this device');
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      throw VCIException('Bluetooth is not enabled');
    }

    _updateState(VCIConnectionState.scanning);

    final completer = Completer<List<VCIDevice>>();

    // Listen for scan results
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName;
        final deviceType = _identifyDeviceType(name);

        if (deviceType != VCIDeviceType.unknown) {
          final vciDevice = VCIDevice(
            device: result.device,
            name: name,
            rssi: result.rssi,
            type: deviceType,
          );

          if (!devices.any((d) => d.device.remoteId == vciDevice.device.remoteId)) {
            devices.add(vciDevice);
          }
        }
      }
    });

    // Start scanning
    await FlutterBluePlus.startScan(timeout: timeout);

    // Wait for scan to complete
    await Future.delayed(timeout);
    await subscription.cancel();
    await FlutterBluePlus.stopScan();

    _updateState(VCIConnectionState.disconnected);

    if (!completer.isCompleted) {
      completer.complete(devices);
    }

    return devices;
  }

  VCIDeviceType _identifyDeviceType(String name) {
    final upperName = name.toUpperCase();

    if (upperName.contains('AUTEL') || upperName.contains('MAXI')) {
      return VCIDeviceType.autelVci;
    } else if (upperName.contains('OBD') ||
               upperName.contains('ELM') ||
               upperName.contains('VLINK') ||
               upperName.contains('VEEPEAK')) {
      return VCIDeviceType.elm327;
    }

    return VCIDeviceType.unknown;
  }

  /// Connect to a VCI device
  Future<void> connect(VCIDevice vciDevice) async {
    try {
      _updateState(VCIConnectionState.connecting);

      await vciDevice.device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = vciDevice.device;

      // Discover services
      final services = await vciDevice.device.discoverServices();

      // Find the appropriate service and characteristics based on device type
      if (vciDevice.type == VCIDeviceType.autelVci) {
        await _setupAutelConnection(services);
      } else {
        await _setupELM327Connection(services);
      }

      _updateState(VCIConnectionState.connected);

      // Listen for disconnection
      vciDevice.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

    } catch (e) {
      _updateState(VCIConnectionState.error);
      throw VCIException('Failed to connect: $e');
    }
  }

  Future<void> _setupAutelConnection(List<BluetoothService> services) async {
    for (final service in services) {
      final serviceUuid = service.uuid.toString().toLowerCase();

      if (serviceUuid.contains('fff0') || serviceUuid.contains('ffe0')) {
        for (final char in service.characteristics) {
          final charUuid = char.uuid.toString().toLowerCase();

          if (charUuid.contains('fff2') || charUuid.contains('ffe2')) {
            _writeCharacteristic = char;
          } else if (charUuid.contains('fff1') || charUuid.contains('ffe1')) {
            _notifyCharacteristic = char;
          }
        }
      }
    }

    if (_writeCharacteristic == null || _notifyCharacteristic == null) {
      throw VCIException('Could not find Autel VCI characteristics');
    }

    // Enable notifications
    await _notifyCharacteristic!.setNotifyValue(true);
    _notifySubscription = _notifyCharacteristic!.lastValueStream.listen((data) {
      if (data.isNotEmpty) {
        _responseController.add(data);
      }
    });
  }

  Future<void> _setupELM327Connection(List<BluetoothService> services) async {
    // ELM327 typically uses SPP or a custom GATT service
    for (final service in services) {
      for (final char in service.characteristics) {
        if (char.properties.write || char.properties.writeWithoutResponse) {
          _writeCharacteristic = char;
        }
        if (char.properties.notify || char.properties.indicate) {
          _notifyCharacteristic = char;
        }
      }
    }

    if (_writeCharacteristic == null) {
      throw VCIException('Could not find writable characteristic');
    }

    if (_notifyCharacteristic != null) {
      await _notifyCharacteristic!.setNotifyValue(true);
      _notifySubscription = _notifyCharacteristic!.lastValueStream.listen((data) {
        if (data.isNotEmpty) {
          _responseController.add(data);
        }
      });
    }
  }

  /// Send a command to the VCI
  Future<List<int>> sendCommand(List<int> command, {Duration timeout = const Duration(seconds: 5)}) async {
    if (!isConnected || _writeCharacteristic == null) {
      throw VCIException('Not connected to VCI');
    }

    final completer = Completer<List<int>>();
    final responseData = <int>[];

    // Listen for response
    final subscription = responseStream.listen((data) {
      responseData.addAll(data);

      // Check for end of response (varies by protocol)
      if (_isResponseComplete(responseData)) {
        if (!completer.isCompleted) {
          completer.complete(responseData);
        }
      }
    });

    // Send command
    await _writeCharacteristic!.write(Uint8List.fromList(command), withoutResponse: false);

    // Wait for response with timeout
    try {
      final response = await completer.future.timeout(timeout);
      await subscription.cancel();
      return response;
    } on TimeoutException {
      await subscription.cancel();
      throw VCIException('Command timeout');
    }
  }

  /// Send AT command string (for ELM327 compatible devices)
  Future<String> sendATCommand(String command, {Duration timeout = const Duration(seconds: 5)}) async {
    final commandBytes = '$command\r'.codeUnits;
    final response = await sendCommand(commandBytes, timeout: timeout);
    return String.fromCharCodes(response).trim();
  }

  bool _isResponseComplete(List<int> data) {
    // Check for common end markers
    if (data.isEmpty) return false;

    // ELM327 ends with '>' prompt
    if (data.last == 0x3E) return true; // '>'

    // Check for carriage return/newline
    if (data.length >= 2 && data[data.length - 2] == 0x0D && data.last == 0x0A) {
      return true;
    }

    return false;
  }

  /// Disconnect from the VCI
  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;

    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }

    _writeCharacteristic = null;
    _notifyCharacteristic = null;

    _updateState(VCIConnectionState.disconnected);
  }

  void _handleDisconnection() {
    _updateState(VCIConnectionState.disconnected);
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _connectedDevice = null;
  }

  void _updateState(VCIConnectionState newState) {
    _state = newState;
    _connectionStateController.add(newState);
  }

  void dispose() {
    _responseController.close();
    _connectionStateController.close();
    _notifySubscription?.cancel();
  }
}

/// VCI device discovered during scanning
class VCIDevice {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  final VCIDeviceType type;

  VCIDevice({
    required this.device,
    required this.name,
    required this.rssi,
    required this.type,
  });

  String get displayName => name.isNotEmpty ? name : device.remoteId.toString();

  String get typeDescription {
    switch (type) {
      case VCIDeviceType.autelVci:
        return 'Autel VCI';
      case VCIDeviceType.elm327:
        return 'ELM327';
      case VCIDeviceType.unknown:
        return 'Unknown';
    }
  }
}

enum VCIDeviceType {
  autelVci,
  elm327,
  unknown,
}

enum VCIConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class VCIException implements Exception {
  final String message;
  VCIException(this.message);

  @override
  String toString() => 'VCIException: $message';
}
