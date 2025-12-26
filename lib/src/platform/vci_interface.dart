import 'dart:async';

/// Abstract interface for Vehicle Communication Interface (VCI) connections
/// Implemented by platform-specific classes (BLE for mobile, Serial for desktop)
abstract class VciInterface {
  /// Stream of raw data received from the VCI device
  Stream<List<int>> get responseStream;

  /// Stream of connection state changes
  Stream<VciConnectionState> get connectionStateStream;

  /// Current connection state
  VciConnectionState get state;

  /// Whether currently connected to a device
  bool get isConnected;

  /// Scan for available VCI devices
  /// Returns a list of discovered devices
  Future<List<VciDeviceInfo>> scanForDevices({
    Duration timeout = const Duration(seconds: 10),
  });

  /// Connect to a VCI device
  Future<void> connect(VciDeviceInfo device);

  /// Disconnect from the current device
  Future<void> disconnect();

  /// Send raw bytes to the VCI device
  /// Returns the response bytes
  Future<List<int>> sendCommand(
    List<int> command, {
    Duration timeout = const Duration(seconds: 5),
  });

  /// Send an AT command string (ELM327 compatible)
  /// Returns the response string
  Future<String> sendATCommand(
    String command, {
    Duration timeout = const Duration(seconds: 5),
  });

  /// Send UDS command to specific module address
  /// Used for advanced diagnostics (ISO 14229)
  Future<List<int>> sendUDSCommand(
    int moduleAddress,
    List<int> data, {
    Duration timeout = const Duration(seconds: 5),
  });

  /// Clean up resources
  void dispose();
}

/// Device information returned by scanning
class VciDeviceInfo {
  /// Unique identifier for the device (BLE address, COM port name, etc.)
  final String id;

  /// Human-readable name of the device
  final String name;

  /// Signal strength (for Bluetooth) or 0 for wired connections
  final int signalStrength;

  /// Type of VCI device
  final VciDeviceType type;

  /// Platform-specific device object (BluetoothDevice, SerialPort, etc.)
  final dynamic platformDevice;

  /// Additional description (e.g., COM port description, manufacturer)
  final String? description;

  VciDeviceInfo({
    required this.id,
    required this.name,
    required this.type,
    this.signalStrength = 0,
    this.platformDevice,
    this.description,
  });

  String get displayName => name.isNotEmpty ? name : id;

  String get typeDescription {
    switch (type) {
      case VciDeviceType.autelVci:
        return 'Autel VCI';
      case VciDeviceType.elm327:
        return 'ELM327 (BLE)';
      case VciDeviceType.elm327Bluetooth:
        return 'ELM327 (Bluetooth)';
      case VciDeviceType.serialPort:
        return 'Serial Port';
      case VciDeviceType.unknown:
        return 'Unknown';
    }
  }
}

/// Types of VCI devices
enum VciDeviceType {
  autelVci,
  elm327,
  elm327Bluetooth,  // Bluetooth Classic (SPP)
  serialPort,
  unknown,
}

/// Connection states for VCI devices
enum VciConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

/// Exception thrown by VCI operations
class VciException implements Exception {
  final String message;
  VciException(this.message);

  @override
  String toString() => 'VciException: $message';
}
