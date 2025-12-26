import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/platform.dart';
import '../uds/uds_protocol.dart';
import '../uds/module_scanner.dart';
import '../uds/security_access.dart';
import '../uds/bidirectional.dart';
import 'diagnostic_providers.dart';

/// Module scanner provider
final moduleScannerProvider = Provider<ModuleScanner>((ref) {
  final connection = ref.watch(vciConnectionProvider);
  return ModuleScanner(connection);
});

/// Security access manager provider
final securityAccessProvider = Provider<SecurityAccessManager>((ref) {
  final connection = ref.watch(vciConnectionProvider);
  return SecurityAccessManager(connection);
});

/// Bi-directional control service provider
final bidirectionalServiceProvider = Provider<BidirectionalControlService>((ref) {
  final connection = ref.watch(vciConnectionProvider);
  final securityManager = ref.watch(securityAccessProvider);
  return BidirectionalControlService(connection, securityManager);
});

/// Module scan state
enum ModuleScanState {
  idle,
  scanning,
  complete,
  error,
}

/// Module scan state notifier
class ModuleScanNotifier extends StateNotifier<ModuleScanState> {
  final ModuleScanner _scanner;

  ModuleScanNotifier(this._scanner) : super(ModuleScanState.idle);

  Future<void> startScan() async {
    state = ModuleScanState.scanning;
  }

  void complete() {
    state = ModuleScanState.complete;
  }

  void setError() {
    state = ModuleScanState.error;
  }

  void reset() {
    state = ModuleScanState.idle;
  }
}

final moduleScanStateProvider = StateNotifierProvider<ModuleScanNotifier, ModuleScanState>((ref) {
  final scanner = ref.watch(moduleScannerProvider);
  return ModuleScanNotifier(scanner);
});

/// Discovered modules list
final discoveredModulesProvider = StateProvider<List<VehicleModule>>((ref) => []);

/// Currently selected module
final selectedModuleProvider = StateProvider<VehicleModule?>((ref) => null);

/// Module DTCs provider
class ModuleDTCNotifier extends StateNotifier<Map<int, List<ModuleDTC>>> {
  ModuleDTCNotifier() : super({});

  void setDTCs(int moduleAddress, List<ModuleDTC> dtcs) {
    state = {...state, moduleAddress: dtcs};
  }

  void clearDTCs(int moduleAddress) {
    final newState = Map<int, List<ModuleDTC>>.from(state);
    newState.remove(moduleAddress);
    state = newState;
  }

  void clearAll() {
    state = {};
  }

  List<ModuleDTC> getDTCs(int moduleAddress) {
    return state[moduleAddress] ?? [];
  }
}

final moduleDTCsProvider = StateNotifierProvider<ModuleDTCNotifier, Map<int, List<ModuleDTC>>>((ref) {
  return ModuleDTCNotifier();
});

/// DTC class for module-specific DTCs (UDS format)
class ModuleDTC {
  final int highByte;
  final int lowByte;
  final int statusByte;
  final String code;
  final String? description;
  final DTCStatus status;

  ModuleDTC({
    required this.highByte,
    required this.lowByte,
    required this.statusByte,
    required this.code,
    this.description,
    required this.status,
  });

  factory ModuleDTC.fromBytes(List<int> bytes) {
    if (bytes.length < 3) {
      return ModuleDTC(
        highByte: 0,
        lowByte: 0,
        statusByte: 0,
        code: 'Unknown',
        status: DTCStatus.pending,
      );
    }

    final high = bytes[0];
    final mid = bytes[1];
    final low = bytes[2];

    // Parse DTC code from bytes (ISO 15031-6)
    final prefix = _getDTCPrefix((high >> 6) & 0x03);
    final digit1 = (high >> 4) & 0x03;
    final digit2 = high & 0x0F;
    final digit3 = (mid >> 4) & 0x0F;
    final digit4 = mid & 0x0F;

    final code = '$prefix$digit1${digit2.toRadixString(16).toUpperCase()}${digit3.toRadixString(16).toUpperCase()}${digit4.toRadixString(16).toUpperCase()}';

    final statusByte = bytes.length > 3 ? bytes[3] : low;
    final status = DTCStatus.fromStatusByte(statusByte);

    return ModuleDTC(
      highByte: high,
      lowByte: mid,
      statusByte: statusByte,
      code: code,
      description: _getDTCDescription(code),
      status: status,
    );
  }

  static String _getDTCPrefix(int value) {
    switch (value) {
      case 0: return 'P'; // Powertrain
      case 1: return 'C'; // Chassis
      case 2: return 'B'; // Body
      case 3: return 'U'; // Network
      default: return 'P';
    }
  }

  static String? _getDTCDescription(String code) {
    // Common DTC descriptions - would be expanded with full database
    final descriptions = {
      'P0300': 'Random/Multiple Cylinder Misfire Detected',
      'P0301': 'Cylinder 1 Misfire Detected',
      'P0302': 'Cylinder 2 Misfire Detected',
      'P0303': 'Cylinder 3 Misfire Detected',
      'P0304': 'Cylinder 4 Misfire Detected',
      'P0171': 'System Too Lean (Bank 1)',
      'P0172': 'System Too Rich (Bank 1)',
      'P0420': 'Catalyst System Efficiency Below Threshold (Bank 1)',
      'P0442': 'Evaporative Emission System Leak Detected (Small Leak)',
      'P0455': 'Evaporative Emission System Leak Detected (Large Leak)',
      'P0500': 'Vehicle Speed Sensor Malfunction',
      'P0700': 'Transmission Control System Malfunction',
      'C0035': 'Left Front Wheel Speed Sensor Circuit',
      'C0040': 'Right Front Wheel Speed Sensor Circuit',
      'C0045': 'Left Rear Wheel Speed Sensor Circuit',
      'C0050': 'Right Rear Wheel Speed Sensor Circuit',
      'B0100': 'Electronic Frontal Sensor 1',
      'U0100': 'Lost Communication With ECM/PCM',
      'U0101': 'Lost Communication With TCM',
      'U0121': 'Lost Communication With ABS',
    };
    return descriptions[code];
  }
}

/// DTC Status
class DTCStatus {
  final bool testFailed;
  final bool testFailedThisOperationCycle;
  final bool pendingDTC;
  final bool confirmedDTC;
  final bool testNotCompletedSinceLastClear;
  final bool testFailedSinceLastClear;
  final bool testNotCompletedThisOperationCycle;
  final bool warningIndicatorRequested;

  DTCStatus({
    required this.testFailed,
    required this.testFailedThisOperationCycle,
    required this.pendingDTC,
    required this.confirmedDTC,
    required this.testNotCompletedSinceLastClear,
    required this.testFailedSinceLastClear,
    required this.testNotCompletedThisOperationCycle,
    required this.warningIndicatorRequested,
  });

  factory DTCStatus.fromStatusByte(int statusByte) {
    return DTCStatus(
      testFailed: (statusByte & 0x01) != 0,
      testFailedThisOperationCycle: (statusByte & 0x02) != 0,
      pendingDTC: (statusByte & 0x04) != 0,
      confirmedDTC: (statusByte & 0x08) != 0,
      testNotCompletedSinceLastClear: (statusByte & 0x10) != 0,
      testFailedSinceLastClear: (statusByte & 0x20) != 0,
      testNotCompletedThisOperationCycle: (statusByte & 0x40) != 0,
      warningIndicatorRequested: (statusByte & 0x80) != 0,
    );
  }

  static DTCStatus get pending => DTCStatus(
    testFailed: false,
    testFailedThisOperationCycle: false,
    pendingDTC: true,
    confirmedDTC: false,
    testNotCompletedSinceLastClear: false,
    testFailedSinceLastClear: false,
    testNotCompletedThisOperationCycle: false,
    warningIndicatorRequested: false,
  );

  String get displayStatus {
    if (confirmedDTC) return 'Confirmed';
    if (pendingDTC) return 'Pending';
    if (testFailed) return 'Failed';
    return 'Stored';
  }
}

/// Actuator test state
enum ActuatorTestState {
  idle,
  running,
  success,
  failed,
}

/// Actuator test state notifier
class ActuatorTestNotifier extends StateNotifier<Map<String, ActuatorTestState>> {
  ActuatorTestNotifier() : super({});

  void setTestState(String actuatorId, ActuatorTestState testState) {
    state = {...state, actuatorId: testState};
  }

  void clearTest(String actuatorId) {
    final newState = Map<String, ActuatorTestState>.from(state);
    newState.remove(actuatorId);
    state = newState;
  }

  void clearAll() {
    state = {};
  }

  ActuatorTestState getTestState(String actuatorId) {
    return state[actuatorId] ?? ActuatorTestState.idle;
  }
}

final actuatorTestStateProvider = StateNotifierProvider<ActuatorTestNotifier, Map<String, ActuatorTestState>>((ref) {
  return ActuatorTestNotifier();
});

/// Security access state per module
class SecurityAccessStateNotifier extends StateNotifier<Map<int, bool>> {
  SecurityAccessStateNotifier() : super({});

  void setUnlocked(int moduleAddress, bool unlocked) {
    state = {...state, moduleAddress: unlocked};
  }

  bool isUnlocked(int moduleAddress) {
    return state[moduleAddress] ?? false;
  }

  void clearAll() {
    state = {};
  }
}

final securityAccessStateProvider = StateNotifierProvider<SecurityAccessStateNotifier, Map<int, bool>>((ref) {
  return SecurityAccessStateNotifier();
});

/// Routine control results
class RoutineResultNotifier extends StateNotifier<Map<String, RoutineControlResult?>> {
  RoutineResultNotifier() : super({});

  void setResult(String routineId, RoutineControlResult? result) {
    state = {...state, routineId: result};
  }

  RoutineControlResult? getResult(String routineId) {
    return state[routineId];
  }

  void clearAll() {
    state = {};
  }
}

final routineResultsProvider = StateNotifierProvider<RoutineResultNotifier, Map<String, RoutineControlResult?>>((ref) {
  return RoutineResultNotifier();
});

/// Module scan progress (0.0 to 1.0)
final moduleScanProgressProvider = StateProvider<double>((ref) => 0.0);

/// Current scan message
final moduleScanMessageProvider = StateProvider<String>((ref) => '');
