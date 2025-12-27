import 'dart:io' show Platform;
import 'vci_interface.dart';
import 'vci_ble_impl.dart';
import 'vci_serial_impl.dart';
import 'vci_bluetooth_classic_impl.dart';
import 'vci_network_impl.dart';
import 'vci_autel_impl.dart';
import 'vci_simulator.dart';

/// Factory for creating platform-appropriate VCI implementations
class VciFactory {
  /// Create a VCI implementation appropriate for the current platform
  /// - Windows/Linux/macOS: Serial port implementation
  /// - Android/iOS: BLE implementation (default)
  static VciInterface create() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return VciSerialImpl();
    } else {
      return VciBleImpl();
    }
  }

  /// Create a BLE VCI implementation
  static VciInterface createBle() {
    return VciBleImpl();
  }

  /// Create a Bluetooth Classic (SPP) VCI implementation
  /// This works with standard ELM327 adapters on Android
  static VciInterface createBluetoothClassic() {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Bluetooth Classic is only supported on Android');
    }
    return VciBluetoothClassicImpl();
  }

  /// Create an Autel VCI implementation
  /// Uses proprietary J2534-over-Bluetooth protocol
  static VciAutelImpl createAutelVci() {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Autel VCI is only supported on Android via Bluetooth');
    }
    return VciAutelImpl();
  }

  /// Create a Serial port VCI implementation
  static VciInterface createSerial() {
    if (!isSerialPlatform) {
      throw UnsupportedError('Serial ports are only supported on desktop platforms');
    }
    return VciSerialImpl();
  }

  /// Create a Network VCI implementation
  /// Connects to a TCP/IP VCI server (mock or remote)
  static VciInterface createNetwork() {
    return NetworkVciImpl();
  }


  /// Create a Simulator VCI implementation
  /// For testing without a real OBD-II adapter
  static VciSimulator createSimulator() {
    return VciSimulator();
  }

  /// Get all available VCI implementations for the current platform
  static List<VciImplementationInfo> getAvailableImplementations() {
    final implementations = <VciImplementationInfo>[];

    // Simulator is always available for testing
    implementations.add(VciImplementationInfo(
      name: 'Simulator',
      description: 'Virtual OBD-II adapter for testing without hardware',
      type: VciDeviceType.elm327,
      create: createSimulator,
    ));

    // Network VCI is available on all platforms
    implementations.add(VciImplementationInfo(
      name: 'Network VCI',
      description: 'TCP/IP connection to mock or remote VCI server',
      type: VciDeviceType.autelVci,
      create: createNetwork,
    ));

    if (Platform.isAndroid) {
      // Autel VCI (J2534 over Bluetooth)
      implementations.add(VciImplementationInfo(
        name: 'Autel VCI',
        description: 'Autel MaxiSys/MaxiCheck VCI via Bluetooth',
        type: VciDeviceType.autelVci,
        create: createAutelVci,
      ));
      implementations.add(VciImplementationInfo(
        name: 'Bluetooth Classic (SPP)',
        description: 'Standard ELM327 adapters with Bluetooth 2.0/2.1',
        type: VciDeviceType.elm327Bluetooth,
        create: createBluetoothClassic,
      ));
      implementations.add(VciImplementationInfo(
        name: 'Bluetooth Low Energy',
        description: 'Modern BLE-compatible OBD adapters',
        type: VciDeviceType.elm327,
        create: createBle,
      ));
    } else if (Platform.isIOS) {
      implementations.add(VciImplementationInfo(
        name: 'Bluetooth Low Energy',
        description: 'BLE-compatible OBD adapters',
        type: VciDeviceType.elm327,
        create: createBle,
      ));
    } else if (isSerialPlatform) {
      implementations.add(VciImplementationInfo(
        name: 'Serial Port',
        description: 'USB or Bluetooth serial port',
        type: VciDeviceType.serialPort,
        create: createSerial,
      ));
    }

    return implementations;
  }

  /// Check if the current platform uses serial ports
  static bool get isSerialPlatform {
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  /// Check if the current platform uses Bluetooth
  static bool get isBluetoothPlatform {
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Check if Bluetooth Classic (SPP) is available
  static bool get isBluetoothClassicAvailable {
    return Platform.isAndroid;
  }

  /// Check if Autel VCI is available
  static bool get isAutelVciAvailable {
    return Platform.isAndroid;
  }

  /// Get a description of the connection method for the current platform
  static String get connectionMethodDescription {
    if (isSerialPlatform) {
      return 'USB, Bluetooth (paired) serial port, or Network VCI';
    } else if (Platform.isAndroid) {
      return 'Autel VCI, Bluetooth Classic (SPP), Bluetooth Low Energy, or Network VCI';
    } else {
      return 'Bluetooth Low Energy or Network VCI';
    }
  }

  /// Get help text for connecting on the current platform
  static String get connectionHelpText {
    if (Platform.isWindows) {
      return 'Connect your OBD adapter via USB, pair Bluetooth adapters in Windows Settings, or use Network VCI to connect to a mock/remote server.';
    } else if (Platform.isLinux) {
      return 'Connect your OBD adapter via USB, pair Bluetooth using system settings, or use Network VCI for remote/mock connections.';
    } else if (Platform.isMacOS) {
      return 'Connect your OBD adapter via USB, pair Bluetooth in System Preferences, or use Network VCI for remote/mock connections.';
    } else if (Platform.isAndroid) {
      return 'Pair your Autel VCI or ELM327 adapter in Android Settings, or use Network VCI for remote/mock connections. Autel VCI, Bluetooth Classic, and BLE adapters are supported.';
    } else if (Platform.isIOS) {
      return 'Enable Bluetooth and scan for nearby BLE OBD adapters, or use Network VCI for remote/mock connections.';
    }
    return 'Connect your OBD adapter or use Network VCI to begin diagnostics.';
  }
}

/// Information about a VCI implementation
class VciImplementationInfo {
  final String name;
  final String description;
  final VciDeviceType type;
  final VciInterface Function() create;

  VciImplementationInfo({
    required this.name,
    required this.description,
    required this.type,
    required this.create,
  });
}
