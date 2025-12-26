import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'vci_interface.dart';

/// Bluetooth Low Energy implementation of VCI interface
/// Used on Android and iOS for wireless connection to VCI adapters
class VciBleImpl implements VciInterface {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription? _notifySubscription;
  StreamSubscription? _connectionSubscription;

  final _responseController = StreamController<List<int>>.broadcast();
  final _connectionStateController = StreamController<VciConnectionState>.broadcast();

  VciConnectionState _state = VciConnectionState.disconnected;

  @override
  Stream<List<int>> get responseStream => _responseController.stream;

  @override
  Stream<VciConnectionState> get connectionStateStream => _connectionStateController.stream;

  @override
  VciConnectionState get state => _state;

  @override
  bool get isConnected => _state == VciConnectionState.connected;

  @override
  Future<List<VciDeviceInfo>> scanForDevices({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final devices = <VciDeviceInfo>[];

    // Check if Bluetooth is available and on
    if (await FlutterBluePlus.isSupported == false) {
      throw VciException('Bluetooth is not supported on this device');
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      throw VciException('Bluetooth is not enabled');
    }

    _updateState(VciConnectionState.scanning);

    // Listen for scan results
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName;
        final deviceType = _identifyDeviceType(name);

        if (deviceType != VciDeviceType.unknown) {
          final vciDevice = VciDeviceInfo(
            id: result.device.remoteId.toString(),
            name: name,
            signalStrength: result.rssi,
            type: deviceType,
            platformDevice: result.device,
          );

          if (!devices.any((d) => d.id == vciDevice.id)) {
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

    _updateState(VciConnectionState.disconnected);

    return devices;
  }

  VciDeviceType _identifyDeviceType(String name) {
    final upperName = name.toUpperCase();

    if (upperName.contains('AUTEL') || upperName.contains('MAXI')) {
      return VciDeviceType.autelVci;
    } else if (upperName.contains('OBD') ||
        upperName.contains('ELM') ||
        upperName.contains('VLINK') ||
        upperName.contains('VEEPEAK')) {
      return VciDeviceType.elm327;
    }

    return VciDeviceType.unknown;
  }

  @override
  Future<void> connect(VciDeviceInfo device) async {
    if (device.platformDevice == null || device.platformDevice is! BluetoothDevice) {
      throw VciException('Invalid device');
    }

    final bluetoothDevice = device.platformDevice as BluetoothDevice;

    try {
      _updateState(VciConnectionState.connecting);

      await bluetoothDevice.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = bluetoothDevice;

      // Discover services
      final services = await bluetoothDevice.discoverServices();

      // Find the appropriate service and characteristics based on device type
      if (device.type == VciDeviceType.autelVci) {
        await _setupAutelConnection(services);
      } else {
        await _setupELM327Connection(services);
      }

      _updateState(VciConnectionState.connected);

      // Listen for disconnection
      _connectionSubscription = bluetoothDevice.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });
    } catch (e) {
      _updateState(VciConnectionState.error);
      throw VciException('Failed to connect: $e');
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
      throw VciException('Could not find Autel VCI characteristics');
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
      throw VciException('Could not find writable characteristic');
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

  @override
  Future<List<int>> sendCommand(
    List<int> command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isConnected || _writeCharacteristic == null) {
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
    await _writeCharacteristic!.write(
      Uint8List.fromList(command),
      withoutResponse: false,
    );

    // Wait for response with timeout
    try {
      final response = await completer.future.timeout(timeout);
      await subscription.cancel();
      return response;
    } on TimeoutException {
      await subscription.cancel();
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
    return String.fromCharCodes(response).trim();
  }

  bool _isResponseComplete(List<int> data) {
    if (data.isEmpty) return false;

    // ELM327 ends with '>' prompt
    if (data.last == 0x3E) return true;

    // Check for carriage return/newline
    if (data.length >= 2 && data[data.length - 2] == 0x0D && data.last == 0x0A) {
      return true;
    }

    return false;
  }

  @override
  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }

    _writeCharacteristic = null;
    _notifyCharacteristic = null;

    _updateState(VciConnectionState.disconnected);
  }

  void _handleDisconnection() {
    _updateState(VciConnectionState.disconnected);
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _connectedDevice = null;
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
    // Build ISO-TP frame for UDS command
    // First byte is PCI (Protocol Control Information)
    // For single frame (SF): PCI = 0x0N where N = data length
    final frame = <int>[];

    if (data.length <= 7) {
      // Single frame
      frame.add(data.length); // PCI for SF
      frame.addAll(data);
      // Pad to 8 bytes
      while (frame.length < 8) {
        frame.add(0x00);
      }
    } else {
      // Multi-frame not yet implemented - throw error for now
      throw VciException('Multi-frame UDS not yet supported over BLE');
    }

    // Prepend module address (CAN ID format varies by device)
    final command = <int>[
      (moduleAddress >> 8) & 0xFF,
      moduleAddress & 0xFF,
      ...frame,
    ];

    return await sendCommand(command, timeout: timeout);
  }

  @override
  void dispose() {
    _responseController.close();
    _connectionStateController.close();
    _notifySubscription?.cancel();
    _connectionSubscription?.cancel();
  }
}
