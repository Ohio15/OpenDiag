import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/platform.dart';
import '../services/diagnostic_service.dart';
import '../obd/obd_protocol.dart';
import '../models/vehicle_data.dart';

enum ConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}


/// Manager for VCI connections that allows runtime switching
class VciManager {
  VciInterface? _currentVci;
  DiagnosticService? _diagnosticService;

  VciInterface? get currentVci => _currentVci;
  DiagnosticService? get diagnosticService => _diagnosticService;
  bool get isConnected => _currentVci?.isConnected ?? false;

  /// Set a new VCI implementation (e.g., switch implementation at runtime)
  Future<void> setVci(VciInterface vci) async {
    // Disconnect existing
    if (_currentVci != null && _currentVci!.isConnected) {
      await _currentVci!.disconnect();
    }

    _currentVci = vci;
    _diagnosticService = DiagnosticService(vci);
  }

  /// Dispose all resources
  void dispose() {
    _currentVci?.dispose();
    _diagnosticService?.dispose();
  }
}

/// Global VCI Manager provider
final vciManagerProvider = Provider<VciManager>((ref) {
  final manager = VciManager();
  ref.onDispose(() => manager.dispose());
  return manager;
});

// Selected VCI implementation type provider (for Android with multiple options)
final selectedVciTypeProvider = StateProvider<VciDeviceType?>((ref) => null);

// VCI Connection provider - uses selected or platform-appropriate implementation
final vciConnectionProvider = Provider<VciInterface>((ref) {
  final selectedType = ref.watch(selectedVciTypeProvider);

  VciInterface connection;
  if (selectedType == VciDeviceType.elm327Bluetooth) {
    connection = VciFactory.createBluetoothClassic();
  } else if (selectedType == VciDeviceType.elm327) {
    connection = VciFactory.createBle();
  } else if (selectedType == VciDeviceType.serialPort) {
    connection = VciFactory.createSerial();
  } else {
    connection = VciFactory.create();
  }

  ref.onDispose(() => connection.dispose());
  return connection;
});

// Diagnostic Service provider
final diagnosticServiceProvider = Provider<DiagnosticService>((ref) {
  final connection = ref.watch(vciConnectionProvider);
  final service = DiagnosticService(connection);
  ref.onDispose(() => service.dispose());
  return service;
});

// Connection state provider
final connectionStateProvider = StateNotifierProvider<ConnectionStateNotifier, ConnectionStatus>((ref) {
  final connection = ref.watch(vciConnectionProvider);
  return ConnectionStateNotifier(connection);
});

class ConnectionStateNotifier extends StateNotifier<ConnectionStatus> {
  final VciInterface _connection;

  ConnectionStateNotifier(this._connection) : super(ConnectionStatus.disconnected) {
    _connection.connectionStateStream.listen((vciState) {
      state = _mapVCIState(vciState);
    });
  }

  ConnectionStatus _mapVCIState(VciConnectionState vciState) {
    switch (vciState) {
      case VciConnectionState.disconnected:
        return ConnectionStatus.disconnected;
      case VciConnectionState.scanning:
        return ConnectionStatus.scanning;
      case VciConnectionState.connecting:
        return ConnectionStatus.connecting;
      case VciConnectionState.connected:
        return ConnectionStatus.connected;
      case VciConnectionState.error:
        return ConnectionStatus.error;
    }
  }
}

// Connected device provider
final connectedDeviceProvider = StateProvider<VciDeviceInfo?>((ref) => null);

// Scanned devices provider
final scannedDevicesProvider = StateProvider<List<VciDeviceInfo>>((ref) => []);

// Available PIDs provider
final availablePidsProvider = StateProvider<Set<int>>((ref) => {});

// VIN provider
final vinProvider = StateProvider<String?>((ref) => null);

// DTC list providers
final storedDTCsProvider = FutureProvider<List<DTC>>((ref) async {
  final service = ref.watch(diagnosticServiceProvider);
  if (!service.isConnected) return [];
  return service.readStoredDTCs();
});

final pendingDTCsProvider = FutureProvider<List<DTC>>((ref) async {
  final service = ref.watch(diagnosticServiceProvider);
  if (!service.isConnected) return [];
  return service.readPendingDTCs();
});

// Readiness monitors provider
final readinessMonitorsProvider = FutureProvider<ReadinessMonitors?>((ref) async {
  final service = ref.watch(diagnosticServiceProvider);
  if (!service.isConnected) return null;
  return service.readReadinessMonitors();
});

// Live data providers
final selectedPidsProvider = StateProvider<List<OBDPid>>((ref) => [
  OBDPid.engineRpm,
  OBDPid.vehicleSpeed,
  OBDPid.coolantTemp,
  OBDPid.engineLoad,
]);

final liveDataProvider = StreamProvider<LiveDataReading>((ref) {
  final service = ref.watch(diagnosticServiceProvider);
  return service.liveDataStream;
});

final isMonitoringProvider = StateProvider<bool>((ref) => false);

// Current readings state
final currentReadingsProvider = StateNotifierProvider<CurrentReadingsNotifier, Map<OBDPid, LiveDataReading>>((ref) {
  return CurrentReadingsNotifier();
});

class CurrentReadingsNotifier extends StateNotifier<Map<OBDPid, LiveDataReading>> {
  CurrentReadingsNotifier() : super({});

  void updateReading(LiveDataReading reading) {
    state = {...state, reading.pid: reading};
  }

  void clear() {
    state = {};
  }
}
