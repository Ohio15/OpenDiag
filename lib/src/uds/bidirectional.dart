/// Bi-directional Control Services
/// Implements actuator tests, routine control, and I/O control
library;

import 'dart:async';
import 'uds_protocol.dart';
import 'module_scanner.dart';
import 'security_access.dart';
import '../platform/vci_interface.dart';

/// Actuator control definition
class ActuatorControl {
  final String name;
  final String description;
  final int did;
  final ActuatorType type;
  final List<ActuatorState> states;
  final int? requiredSecurityLevel;
  final bool requiresEngineOff;
  final bool requiresKeyOn;

  const ActuatorControl({
    required this.name,
    required this.description,
    required this.did,
    required this.type,
    this.states = const [],
    this.requiredSecurityLevel,
    this.requiresEngineOff = false,
    this.requiresKeyOn = true,
  });
}

/// Actuator types
enum ActuatorType {
  onOff('On/Off', 'Binary control'),
  momentary('Momentary', 'Pulse activation'),
  variable('Variable', 'Adjustable value'),
  multiState('Multi-State', 'Multiple positions'),
  continuous('Continuous', 'Ongoing control');

  final String name;
  final String description;
  const ActuatorType(this.name, this.description);
}

/// Actuator state options
class ActuatorState {
  final String name;
  final List<int> controlBytes;

  const ActuatorState(this.name, this.controlBytes);
}

/// Common actuator controls database
class ActuatorDatabase {
  // Engine Module (ECM) Actuators
  static const List<ActuatorControl> engineActuators = [
    ActuatorControl(
      name: 'Fuel Injector 1',
      description: 'Activate fuel injector cylinder 1',
      did: 0xF000,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'Fuel Injector 2',
      description: 'Activate fuel injector cylinder 2',
      did: 0xF001,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'Fuel Injector 3',
      description: 'Activate fuel injector cylinder 3',
      did: 0xF002,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'Fuel Injector 4',
      description: 'Activate fuel injector cylinder 4',
      did: 0xF003,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'Ignition Coil 1',
      description: 'Activate ignition coil cylinder 1',
      did: 0xF010,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'Ignition Coil 2',
      description: 'Activate ignition coil cylinder 2',
      did: 0xF011,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'Idle Air Control',
      description: 'Control idle air valve position',
      did: 0xF020,
      type: ActuatorType.variable,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'Electronic Throttle',
      description: 'Control throttle body position',
      did: 0xF021,
      type: ActuatorType.variable,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'EGR Valve',
      description: 'Control EGR valve position',
      did: 0xF030,
      type: ActuatorType.variable,
    ),
    ActuatorControl(
      name: 'EVAP Purge Valve',
      description: 'Control evaporative emissions purge',
      did: 0xF031,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'Fuel Pump Relay',
      description: 'Control fuel pump operation',
      did: 0xF040,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'Cooling Fan Relay',
      description: 'Control radiator cooling fan',
      did: 0xF041,
      type: ActuatorType.multiState,
      states: [
        ActuatorState('Off', [0x00]),
        ActuatorState('Low Speed', [0x01]),
        ActuatorState('High Speed', [0x02]),
      ],
    ),
    ActuatorControl(
      name: 'A/C Compressor Clutch',
      description: 'Engage A/C compressor',
      did: 0xF042,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'VVT Solenoid',
      description: 'Variable valve timing control',
      did: 0xF050,
      type: ActuatorType.variable,
    ),
  ];

  // Transmission Module (TCM) Actuators
  static const List<ActuatorControl> transmissionActuators = [
    ActuatorControl(
      name: 'Shift Solenoid A',
      description: 'Control shift solenoid A',
      did: 0xF100,
      type: ActuatorType.onOff,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'Shift Solenoid B',
      description: 'Control shift solenoid B',
      did: 0xF101,
      type: ActuatorType.onOff,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'Shift Solenoid C',
      description: 'Control shift solenoid C',
      did: 0xF102,
      type: ActuatorType.onOff,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'TCC Solenoid',
      description: 'Torque converter clutch control',
      did: 0xF110,
      type: ActuatorType.variable,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'Line Pressure Solenoid',
      description: 'Control line pressure',
      did: 0xF111,
      type: ActuatorType.variable,
      requiresEngineOff: true,
    ),
  ];

  // ABS/Stability Module Actuators
  static const List<ActuatorControl> absActuators = [
    ActuatorControl(
      name: 'ABS Pump Motor',
      description: 'Activate ABS hydraulic pump',
      did: 0xF200,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'FL Inlet Valve',
      description: 'Front left ABS inlet valve',
      did: 0xF201,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'FL Outlet Valve',
      description: 'Front left ABS outlet valve',
      did: 0xF202,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'FR Inlet Valve',
      description: 'Front right ABS inlet valve',
      did: 0xF203,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'FR Outlet Valve',
      description: 'Front right ABS outlet valve',
      did: 0xF204,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'RL Inlet Valve',
      description: 'Rear left ABS inlet valve',
      did: 0xF205,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'RL Outlet Valve',
      description: 'Rear left ABS outlet valve',
      did: 0xF206,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'RR Inlet Valve',
      description: 'Rear right ABS inlet valve',
      did: 0xF207,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
    ActuatorControl(
      name: 'RR Outlet Valve',
      description: 'Rear right ABS outlet valve',
      did: 0xF208,
      type: ActuatorType.momentary,
      requiresEngineOff: true,
    ),
  ];

  // Body Control Module Actuators
  static const List<ActuatorControl> bodyActuators = [
    ActuatorControl(
      name: 'Horn',
      description: 'Activate horn',
      did: 0xF300,
      type: ActuatorType.momentary,
    ),
    ActuatorControl(
      name: 'Left Turn Signal',
      description: 'Activate left turn signal',
      did: 0xF301,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'Right Turn Signal',
      description: 'Activate right turn signal',
      did: 0xF302,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'Hazard Lights',
      description: 'Activate hazard lights',
      did: 0xF303,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'Low Beam Headlights',
      description: 'Activate low beam headlights',
      did: 0xF310,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'High Beam Headlights',
      description: 'Activate high beam headlights',
      did: 0xF311,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'Fog Lights',
      description: 'Activate fog lights',
      did: 0xF312,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'Brake Lights',
      description: 'Activate brake lights',
      did: 0xF313,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'Reverse Lights',
      description: 'Activate reverse lights',
      did: 0xF314,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'Interior Lights',
      description: 'Control interior dome light',
      did: 0xF320,
      type: ActuatorType.variable,
    ),
    ActuatorControl(
      name: 'Driver Door Lock',
      description: 'Control driver door lock motor',
      did: 0xF330,
      type: ActuatorType.multiState,
      states: [
        ActuatorState('Unlock', [0x00]),
        ActuatorState('Lock', [0x01]),
      ],
    ),
    ActuatorControl(
      name: 'Passenger Door Lock',
      description: 'Control passenger door lock motor',
      did: 0xF331,
      type: ActuatorType.multiState,
      states: [
        ActuatorState('Unlock', [0x00]),
        ActuatorState('Lock', [0x01]),
      ],
    ),
    ActuatorControl(
      name: 'All Door Locks',
      description: 'Control all door lock motors',
      did: 0xF332,
      type: ActuatorType.multiState,
      states: [
        ActuatorState('Unlock All', [0x00]),
        ActuatorState('Lock All', [0x01]),
      ],
    ),
    ActuatorControl(
      name: 'Driver Window',
      description: 'Control driver window motor',
      did: 0xF340,
      type: ActuatorType.multiState,
      states: [
        ActuatorState('Stop', [0x00]),
        ActuatorState('Up', [0x01]),
        ActuatorState('Down', [0x02]),
        ActuatorState('Auto Up', [0x03]),
        ActuatorState('Auto Down', [0x04]),
      ],
    ),
    ActuatorControl(
      name: 'Passenger Window',
      description: 'Control passenger window motor',
      did: 0xF341,
      type: ActuatorType.multiState,
      states: [
        ActuatorState('Stop', [0x00]),
        ActuatorState('Up', [0x01]),
        ActuatorState('Down', [0x02]),
      ],
    ),
    ActuatorControl(
      name: 'Windshield Wipers',
      description: 'Control windshield wipers',
      did: 0xF350,
      type: ActuatorType.multiState,
      states: [
        ActuatorState('Off', [0x00]),
        ActuatorState('Low', [0x01]),
        ActuatorState('High', [0x02]),
        ActuatorState('Intermittent', [0x03]),
      ],
    ),
    ActuatorControl(
      name: 'Windshield Washer',
      description: 'Activate windshield washer pump',
      did: 0xF351,
      type: ActuatorType.momentary,
    ),
    ActuatorControl(
      name: 'Rear Wiper',
      description: 'Control rear wiper motor',
      did: 0xF352,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'Trunk Release',
      description: 'Activate trunk release solenoid',
      did: 0xF360,
      type: ActuatorType.momentary,
    ),
    ActuatorControl(
      name: 'Fuel Door Release',
      description: 'Activate fuel door release',
      did: 0xF361,
      type: ActuatorType.momentary,
    ),
  ];

  // HVAC Module Actuators
  static const List<ActuatorControl> hvacActuators = [
    ActuatorControl(
      name: 'Blower Motor',
      description: 'Control HVAC blower speed',
      did: 0xF400,
      type: ActuatorType.variable,
    ),
    ActuatorControl(
      name: 'A/C Clutch',
      description: 'Engage A/C compressor clutch',
      did: 0xF401,
      type: ActuatorType.onOff,
    ),
    ActuatorControl(
      name: 'Mode Door Actuator',
      description: 'Control airflow direction',
      did: 0xF410,
      type: ActuatorType.multiState,
      states: [
        ActuatorState('Face', [0x00]),
        ActuatorState('Face/Feet', [0x01]),
        ActuatorState('Feet', [0x02]),
        ActuatorState('Feet/Defrost', [0x03]),
        ActuatorState('Defrost', [0x04]),
      ],
    ),
    ActuatorControl(
      name: 'Blend Door Actuator',
      description: 'Control temperature blend',
      did: 0xF411,
      type: ActuatorType.variable,
    ),
    ActuatorControl(
      name: 'Recirculation Door',
      description: 'Control fresh/recirculated air',
      did: 0xF412,
      type: ActuatorType.onOff,
    ),
  ];

  /// Get actuators for a module category
  static List<ActuatorControl> getActuatorsForCategory(ModuleCategory category) {
    switch (category) {
      case ModuleCategory.powertrain:
        return [...engineActuators, ...transmissionActuators];
      case ModuleCategory.chassis:
        return absActuators;
      case ModuleCategory.body:
        return bodyActuators;
      case ModuleCategory.climate:
        return hvacActuators;
      default:
        return [];
    }
  }

  /// Alias for UI compatibility
  static List<ActuatorControl> getActuatorsForModule(ModuleCategory category) =>
      getActuatorsForCategory(category);

  /// Get all actuators
  static List<ActuatorControl> get allActuators => [
        ...engineActuators,
        ...transmissionActuators,
        ...absActuators,
        ...bodyActuators,
        ...hvacActuators,
      ];
}

/// Routine definitions
class RoutineDefinition {
  final String name;
  final String description;
  final int routineId;
  final RoutineType type;
  final bool requiresSecurityAccess;
  final int? securityLevel;
  final List<RoutineParameter> parameters;

  const RoutineDefinition({
    required this.name,
    required this.description,
    required this.routineId,
    required this.type,
    this.requiresSecurityAccess = false,
    this.securityLevel,
    this.parameters = const [],
  });
}

/// Routine types
enum RoutineType {
  diagnostic('Diagnostic', 'Self-test routines'),
  calibration('Calibration', 'Sensor/system calibration'),
  reset('Reset', 'Reset/clear functions'),
  actuation('Actuation', 'Component activation'),
  programming('Programming', 'Configuration changes');

  final String name;
  final String description;
  const RoutineType(this.name, this.description);
}

/// Routine parameter
class RoutineParameter {
  final String name;
  final ParameterType type;
  final dynamic defaultValue;

  const RoutineParameter({
    required this.name,
    required this.type,
    this.defaultValue,
  });
}

/// Routine category for UI display
enum RoutineCategory {
  diagnostic,
  calibration,
  reset,
  actuation,
  programming,
}

/// Common routines database
class RoutineDatabase {
  /// Get routines for a module category
  static List<RoutineDefinition> getRoutinesForModule(ModuleCategory category) {
    switch (category) {
      case ModuleCategory.powertrain:
        return commonRoutines.where((r) =>
            r.type == RoutineType.calibration ||
            r.type == RoutineType.reset ||
            r.name.contains('Throttle') ||
            r.name.contains('Idle') ||
            r.name.contains('Injector') ||
            r.name.contains('Coil') ||
            r.name.contains('EVAP') ||
            r.name.contains('DPF')).toList();
      case ModuleCategory.chassis:
        return commonRoutines.where((r) =>
            r.name.contains('Steering') ||
            r.name.contains('TPMS') ||
            r.name.contains('ABS') ||
            r.name.contains('Brake')).toList();
      case ModuleCategory.body:
        return commonRoutines.where((r) =>
            r.type == RoutineType.reset).toList();
      default:
        return commonRoutines.where((r) =>
            r.type == RoutineType.diagnostic ||
            r.type == RoutineType.reset).toList();
    }
  }

  /// Get routine category for UI display
  static RoutineCategory getCategory(RoutineDefinition routine) {
    switch (routine.type) {
      case RoutineType.diagnostic:
        return RoutineCategory.diagnostic;
      case RoutineType.calibration:
        return RoutineCategory.calibration;
      case RoutineType.reset:
        return RoutineCategory.reset;
      case RoutineType.actuation:
        return RoutineCategory.actuation;
      case RoutineType.programming:
        return RoutineCategory.programming;
    }
  }

  static const List<RoutineDefinition> commonRoutines = [
    // Diagnostic Routines
    RoutineDefinition(
      name: 'Component Self-Test',
      description: 'Run module self-diagnostic test',
      routineId: 0x0200,
      type: RoutineType.diagnostic,
    ),
    RoutineDefinition(
      name: 'Sensor Calibration Check',
      description: 'Verify sensor calibration status',
      routineId: 0x0201,
      type: RoutineType.diagnostic,
    ),

    // Calibration Routines
    RoutineDefinition(
      name: 'Throttle Position Learn',
      description: 'Learn throttle body minimum/maximum positions',
      routineId: 0x0300,
      type: RoutineType.calibration,
      requiresSecurityAccess: true,
    ),
    RoutineDefinition(
      name: 'Idle Speed Learn',
      description: 'Learn base idle speed',
      routineId: 0x0301,
      type: RoutineType.calibration,
      requiresSecurityAccess: true,
    ),
    RoutineDefinition(
      name: 'Steering Angle Sensor Calibration',
      description: 'Calibrate steering angle sensor center position',
      routineId: 0x0310,
      type: RoutineType.calibration,
      requiresSecurityAccess: true,
    ),
    RoutineDefinition(
      name: 'TPMS Sensor Learn',
      description: 'Learn tire pressure sensor IDs',
      routineId: 0x0320,
      type: RoutineType.calibration,
    ),
    RoutineDefinition(
      name: 'Battery Registration',
      description: 'Register new battery parameters',
      routineId: 0x0330,
      type: RoutineType.calibration,
      requiresSecurityAccess: true,
    ),

    // Reset Routines
    RoutineDefinition(
      name: 'Oil Service Reset',
      description: 'Reset oil life monitor/service indicator',
      routineId: 0x0400,
      type: RoutineType.reset,
    ),
    RoutineDefinition(
      name: 'Brake Pad Reset',
      description: 'Reset brake pad wear indicator',
      routineId: 0x0401,
      type: RoutineType.reset,
    ),
    RoutineDefinition(
      name: 'Transmission Adaptation Reset',
      description: 'Reset transmission shift adaptation values',
      routineId: 0x0410,
      type: RoutineType.reset,
      requiresSecurityAccess: true,
    ),
    RoutineDefinition(
      name: 'ABS Bleeding Procedure',
      description: 'Initiate ABS brake bleeding sequence',
      routineId: 0x0420,
      type: RoutineType.actuation,
      requiresSecurityAccess: true,
    ),

    // Actuation Routines
    RoutineDefinition(
      name: 'Injector Buzz Test',
      description: 'Buzz test all fuel injectors sequentially',
      routineId: 0x0500,
      type: RoutineType.actuation,
    ),
    RoutineDefinition(
      name: 'Coil-On-Plug Test',
      description: 'Test ignition coils sequentially',
      routineId: 0x0501,
      type: RoutineType.actuation,
    ),
    RoutineDefinition(
      name: 'EVAP Leak Test',
      description: 'Run evaporative system leak test',
      routineId: 0x0510,
      type: RoutineType.diagnostic,
    ),
    RoutineDefinition(
      name: 'DPF Regeneration',
      description: 'Force diesel particulate filter regeneration',
      routineId: 0x0520,
      type: RoutineType.actuation,
      requiresSecurityAccess: true,
    ),
  ];
}

/// Bi-directional control service
class BidirectionalControlService {
  final VciInterface _vci;
  final SecurityAccessManager _securityManager;
  Timer? _testerPresentTimer;
  VehicleModule? _activeModule;

  BidirectionalControlService(this._vci, this._securityManager);

  /// Start bi-directional session with module
  Future<bool> startSession(VehicleModule module) async {
    // Switch to extended diagnostic session
    if (!await _securityManager.switchToExtendedSession(module)) {
      return false;
    }

    _activeModule = module;

    // Start tester present keepalive
    _startTesterPresent(module);

    return true;
  }

  /// End bi-directional session
  Future<void> endSession() async {
    _stopTesterPresent();

    if (_activeModule != null) {
      await _securityManager.switchToDefaultSession(_activeModule!);
      _activeModule = null;
    }
  }

  /// Execute Input/Output Control
  Future<ActuatorControlResult> executeIOControl(
    VehicleModule module,
    ActuatorControl actuator, {
    int controlParameter = IOControlParameter.shortTermAdjustment,
    List<int>? controlState,
  }) async {
    // Check security if required
    if (actuator.requiredSecurityLevel != null) {
      if (!_securityManager.isUnlocked(module, actuator.requiredSecurityLevel!)) {
        final result = await _securityManager.requestSecurityAccess(
          module,
          actuator.requiredSecurityLevel!,
        );
        if (!result.success) {
          return ActuatorControlResult(
            success: false,
            errorMessage: 'Security access denied: ${result.errorMessage}',
          );
        }
      }
    }

    // Build and send I/O control request
    final request = UDSRequest.inputOutputControl(
      actuator.did,
      controlParameter,
      controlState: controlState,
    );

    final response = await _sendUDSRequest(module.address, request);

    if (response == null) {
      return ActuatorControlResult(
        success: false,
        errorMessage: 'No response from module',
      );
    }

    if (!response.isPositive) {
      return ActuatorControlResult(
        success: false,
        errorMessage: response.errorMessage,
        negativeResponseCode: response.negativeResponseCode,
      );
    }

    return ActuatorControlResult(
      success: true,
      message: 'Actuator control successful',
      responseData: response.data,
    );
  }

  /// Return actuator control to ECU
  Future<ActuatorControlResult> returnControlToECU(
    VehicleModule module,
    ActuatorControl actuator,
  ) async {
    final request = UDSRequest.inputOutputControl(
      actuator.did,
      IOControlParameter.returnControlToECU,
    );

    final response = await _sendUDSRequest(module.address, request);

    if (response?.isPositive != true) {
      return ActuatorControlResult(
        success: false,
        errorMessage: response?.errorMessage ?? 'No response',
      );
    }

    return ActuatorControlResult(
      success: true,
      message: 'Control returned to ECU',
    );
  }

  /// Execute a simple actuator test (momentary activation)
  Future<ActuatorControlResult> executeActuatorTest(
    VehicleModule module,
    ActuatorControl actuator,
  ) async {
    // Use short-term adjustment with default on state
    return executeIOControl(
      module,
      actuator,
      controlParameter: IOControlParameter.shortTermAdjustment,
      controlState: actuator.type == ActuatorType.variable ? [0x80] : [0xFF],
    );
  }

  /// Stop an actuator (return control to ECU)
  Future<ActuatorControlResult> stopActuator(
    VehicleModule module,
    ActuatorControl actuator,
  ) async {
    return returnControlToECU(module, actuator);
  }

  /// Set actuator state with control parameter
  Future<ActuatorControlResult> setActuatorState(
    VehicleModule module,
    ActuatorControl actuator,
    int controlParameter,
    List<int> controlState,
  ) async {
    return executeIOControl(
      module,
      actuator,
      controlParameter: controlParameter,
      controlState: controlState,
    );
  }

  /// Execute routine
  Future<RoutineControlResult> executeRoutine(
    VehicleModule module,
    RoutineDefinition routine, {
    int controlType = RoutineControlType.startRoutine,
    List<int>? optionRecord,
  }) async {
    // Check security if required
    if (routine.requiresSecurityAccess) {
      final level = routine.securityLevel ?? SecurityLevel.routineControl;
      if (!_securityManager.isUnlocked(module, level)) {
        final result = await _securityManager.requestSecurityAccess(
          module,
          level,
        );
        if (!result.success) {
          return RoutineControlResult(
            success: false,
            errorMessage: 'Security access denied: ${result.errorMessage}',
          );
        }
      }
    }

    // Build and send routine control request
    final request = UDSRequest.routineControl(
      controlType,
      routine.routineId,
      routineOptionRecord: optionRecord,
    );

    final response = await _sendUDSRequest(module.address, request);

    if (response == null) {
      return RoutineControlResult(
        success: false,
        errorMessage: 'No response from module',
      );
    }

    if (!response.isPositive) {
      return RoutineControlResult(
        success: false,
        errorMessage: response.errorMessage,
        negativeResponseCode: response.negativeResponseCode,
      );
    }

    return RoutineControlResult(
      success: true,
      message: 'Routine executed successfully',
      routineInfo: response.data,
    );
  }

  /// Read data by identifier
  Future<ReadDataResult> readDataByIdentifier(
    VehicleModule module,
    List<int> dids,
  ) async {
    final request = UDSRequest.readDataByIdentifier(dids);
    final response = await _sendUDSRequest(module.address, request);

    if (response == null) {
      return ReadDataResult(
        success: false,
        errorMessage: 'No response from module',
      );
    }

    if (!response.isPositive) {
      return ReadDataResult(
        success: false,
        errorMessage: response.errorMessage,
      );
    }

    return ReadDataResult(
      success: true,
      data: response.parseDIDValues(),
    );
  }

  /// Write data by identifier
  Future<WriteDataResult> writeDataByIdentifier(
    VehicleModule module,
    int did,
    List<int> value,
  ) async {
    // Writing typically requires security access
    if (!_securityManager.isUnlocked(module, SecurityLevel.ioControl)) {
      final result = await _securityManager.requestSecurityAccess(
        module,
        SecurityLevel.ioControl,
      );
      if (!result.success) {
        return WriteDataResult(
          success: false,
          errorMessage: 'Security access denied',
        );
      }
    }

    final request = UDSRequest.writeDataByIdentifier(did, value);
    final response = await _sendUDSRequest(module.address, request);

    if (response?.isPositive != true) {
      return WriteDataResult(
        success: false,
        errorMessage: response?.errorMessage ?? 'No response',
      );
    }

    return WriteDataResult(
      success: true,
      message: 'Data written successfully',
    );
  }

  /// Start tester present keepalive
  void _startTesterPresent(VehicleModule module) {
    _stopTesterPresent();
    _testerPresentTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _securityManager.sendTesterPresent(module),
    );
  }

  /// Stop tester present keepalive
  void _stopTesterPresent() {
    _testerPresentTimer?.cancel();
    _testerPresentTimer = null;
  }

  /// Send UDS request
  Future<UDSResponse?> _sendUDSRequest(
    int address,
    UDSRequest request,
  ) async {
    try {
      final data = request.toBytes();
      final response = await _vci.sendUDSCommand(address, data.toList());

      if (response.isEmpty) return null;

      var udsResponse = UDSResponse.fromBytes(response);

      // Handle response pending
      while (udsResponse.isPending) {
        await Future.delayed(const Duration(milliseconds: 100));
        final nextResponse = await _vci.sendUDSCommand(address, data.toList());
        if (nextResponse.isEmpty) break;
        udsResponse = UDSResponse.fromBytes(nextResponse);
      }

      return udsResponse;
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _stopTesterPresent();
  }
}

/// Actuator control result
class ActuatorControlResult {
  final bool success;
  final String? message;
  final String? errorMessage;
  final int? negativeResponseCode;
  final List<int>? responseData;

  ActuatorControlResult({
    required this.success,
    this.message,
    this.errorMessage,
    this.negativeResponseCode,
    this.responseData,
  });
}

/// Routine control result
class RoutineControlResult {
  final bool success;
  final String? message;
  final String? errorMessage;
  final int? negativeResponseCode;
  final List<int>? routineInfo;

  RoutineControlResult({
    required this.success,
    this.message,
    this.errorMessage,
    this.negativeResponseCode,
    this.routineInfo,
  });
}

/// Read data result
class ReadDataResult {
  final bool success;
  final String? errorMessage;
  final Map<int, List<int>>? data;

  ReadDataResult({
    required this.success,
    this.errorMessage,
    this.data,
  });
}

/// Write data result
class WriteDataResult {
  final bool success;
  final String? message;
  final String? errorMessage;

  WriteDataResult({
    required this.success,
    this.message,
    this.errorMessage,
  });
}
