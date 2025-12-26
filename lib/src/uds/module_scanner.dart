/// Vehicle Module Scanner
/// Discovers all ECUs on the vehicle network using UDS protocol
library;

import 'dart:async';
import 'uds_protocol.dart';
import '../platform/vci_interface.dart';

/// Known ECU addresses for common vehicle modules
class KnownModules {
  // Standard OBD-II addresses (11-bit CAN)
  static const int engineECU = 0x7E0;
  static const int transmissionECU = 0x7E1;
  static const int absECU = 0x7E2;
  static const int airbagECU = 0x7E3;
  static const int bodyControlModule = 0x7E4;
  static const int instrumentCluster = 0x7E5;
  static const int hvacModule = 0x7E6;
  static const int parkingAssist = 0x7E7;

  // Extended address ranges
  static const List<int> standardRange = [
    0x700, 0x701, 0x702, 0x703, 0x704, 0x705, 0x706, 0x707,
    0x708, 0x709, 0x70A, 0x70B, 0x70C, 0x70D, 0x70E, 0x70F,
    0x710, 0x711, 0x712, 0x713, 0x714, 0x715, 0x716, 0x717,
    0x718, 0x719, 0x71A, 0x71B, 0x71C, 0x71D, 0x71E, 0x71F,
    0x720, 0x721, 0x722, 0x723, 0x724, 0x725, 0x726, 0x727,
    0x728, 0x729, 0x72A, 0x72B, 0x72C, 0x72D, 0x72E, 0x72F,
    0x730, 0x731, 0x732, 0x733, 0x734, 0x735, 0x736, 0x737,
    0x738, 0x739, 0x73A, 0x73B, 0x73C, 0x73D, 0x73E, 0x73F,
    0x740, 0x741, 0x742, 0x743, 0x744, 0x745, 0x746, 0x747,
    0x748, 0x749, 0x74A, 0x74B, 0x74C, 0x74D, 0x74E, 0x74F,
    0x750, 0x751, 0x752, 0x753, 0x754, 0x755, 0x756, 0x757,
    0x758, 0x759, 0x75A, 0x75B, 0x75C, 0x75D, 0x75E, 0x75F,
    0x760, 0x761, 0x762, 0x763, 0x764, 0x765, 0x766, 0x767,
    0x768, 0x769, 0x76A, 0x76B, 0x76C, 0x76D, 0x76E, 0x76F,
    0x770, 0x771, 0x772, 0x773, 0x774, 0x775, 0x776, 0x777,
    0x778, 0x779, 0x77A, 0x77B, 0x77C, 0x77D, 0x77E, 0x77F,
    0x780, 0x781, 0x782, 0x783, 0x784, 0x785, 0x786, 0x787,
    0x788, 0x789, 0x78A, 0x78B, 0x78C, 0x78D, 0x78E, 0x78F,
    0x790, 0x791, 0x792, 0x793, 0x794, 0x795, 0x796, 0x797,
    0x798, 0x799, 0x79A, 0x79B, 0x79C, 0x79D, 0x79E, 0x79F,
    0x7A0, 0x7A1, 0x7A2, 0x7A3, 0x7A4, 0x7A5, 0x7A6, 0x7A7,
    0x7A8, 0x7A9, 0x7AA, 0x7AB, 0x7AC, 0x7AD, 0x7AE, 0x7AF,
    0x7B0, 0x7B1, 0x7B2, 0x7B3, 0x7B4, 0x7B5, 0x7B6, 0x7B7,
    0x7B8, 0x7B9, 0x7BA, 0x7BB, 0x7BC, 0x7BD, 0x7BE, 0x7BF,
    0x7C0, 0x7C1, 0x7C2, 0x7C3, 0x7C4, 0x7C5, 0x7C6, 0x7C7,
    0x7C8, 0x7C9, 0x7CA, 0x7CB, 0x7CC, 0x7CD, 0x7CE, 0x7CF,
    0x7D0, 0x7D1, 0x7D2, 0x7D3, 0x7D4, 0x7D5, 0x7D6, 0x7D7,
    0x7D8, 0x7D9, 0x7DA, 0x7DB, 0x7DC, 0x7DD, 0x7DE, 0x7DF,
    0x7E0, 0x7E1, 0x7E2, 0x7E3, 0x7E4, 0x7E5, 0x7E6, 0x7E7,
    0x7E8, 0x7E9, 0x7EA, 0x7EB, 0x7EC, 0x7ED, 0x7EE, 0x7EF,
    0x7F0, 0x7F1, 0x7F2, 0x7F3, 0x7F4, 0x7F5, 0x7F6, 0x7F7,
    0x7F8, 0x7F9, 0x7FA, 0x7FB, 0x7FC, 0x7FD, 0x7FE, 0x7FF,
  ];

  // Priority addresses to scan first
  static const List<int> priorityAddresses = [
    0x7E0, 0x7E1, 0x7E2, 0x7E3, 0x7E4, 0x7E5, 0x7E6, 0x7E7,
    0x7E8, 0x7E9, 0x7EA, 0x7EB, 0x7EC, 0x7ED, 0x7EE, 0x7EF,
  ];
}

/// Vehicle module category
enum ModuleCategory {
  powertrain('Powertrain', '🔧'),
  chassis('Chassis', '🚗'),
  body('Body', '🚪'),
  network('Network', '📡'),
  safety('Safety', '🛡️'),
  comfort('Comfort', '💺'),
  infotainment('Infotainment', '📺'),
  lighting('Lighting', '💡'),
  climate('Climate', '❄️'),
  unknown('Unknown', '❓');

  final String name;
  final String icon;
  const ModuleCategory(this.name, this.icon);
}

/// Module information database
class ModuleDatabase {
  static final Map<int, ModuleDefinition> _knownModules = {
    // Engine/Powertrain
    0x7E0: ModuleDefinition(
      name: 'Engine Control Module (ECM)',
      shortName: 'ECM',
      category: ModuleCategory.powertrain,
      description: 'Main engine computer controlling fuel injection, ignition timing, emissions',
    ),
    0x7E1: ModuleDefinition(
      name: 'Transmission Control Module (TCM)',
      shortName: 'TCM',
      category: ModuleCategory.powertrain,
      description: 'Automatic/CVT transmission control, shift patterns, torque converter',
    ),
    0x7E2: ModuleDefinition(
      name: 'ABS/Stability Control Module',
      shortName: 'ABS',
      category: ModuleCategory.chassis,
      description: 'Anti-lock brakes, traction control, electronic stability',
    ),
    0x7E3: ModuleDefinition(
      name: 'Airbag/SRS Module',
      shortName: 'SRS',
      category: ModuleCategory.safety,
      description: 'Supplemental restraint system, airbags, seatbelt pretensioners',
    ),
    0x7E4: ModuleDefinition(
      name: 'Body Control Module (BCM)',
      shortName: 'BCM',
      category: ModuleCategory.body,
      description: 'Central body electronics, lighting, locks, windows, wipers',
    ),
    0x7E5: ModuleDefinition(
      name: 'Instrument Cluster (IPC)',
      shortName: 'IPC',
      category: ModuleCategory.body,
      description: 'Dashboard gauges, warning lights, odometer, trip computer',
    ),
    0x7E6: ModuleDefinition(
      name: 'HVAC Control Module',
      shortName: 'HVAC',
      category: ModuleCategory.climate,
      description: 'Heating, ventilation, air conditioning, climate control',
    ),
    0x7E7: ModuleDefinition(
      name: 'Parking Assist Module',
      shortName: 'PAM',
      category: ModuleCategory.chassis,
      description: 'Parking sensors, backup camera, automated parking',
    ),

    // Additional common modules
    0x720: ModuleDefinition(
      name: 'Electric Power Steering (EPS)',
      shortName: 'EPS',
      category: ModuleCategory.chassis,
      description: 'Electric power steering control, torque assist',
    ),
    0x730: ModuleDefinition(
      name: 'Keyless Entry Module',
      shortName: 'RKE',
      category: ModuleCategory.body,
      description: 'Remote keyless entry, passive entry, push-button start',
    ),
    0x740: ModuleDefinition(
      name: 'Tire Pressure Monitor (TPMS)',
      shortName: 'TPMS',
      category: ModuleCategory.chassis,
      description: 'Tire pressure monitoring system',
    ),
    0x750: ModuleDefinition(
      name: 'Gateway Module',
      shortName: 'GW',
      category: ModuleCategory.network,
      description: 'Central gateway, CAN bus routing, diagnostic access',
    ),
    0x760: ModuleDefinition(
      name: 'Headlight Control Module',
      shortName: 'HCM',
      category: ModuleCategory.lighting,
      description: 'Automatic headlights, adaptive lighting, LED control',
    ),
    0x770: ModuleDefinition(
      name: 'Audio/Infotainment Unit',
      shortName: 'IVI',
      category: ModuleCategory.infotainment,
      description: 'Head unit, navigation, Bluetooth, media playback',
    ),
    0x780: ModuleDefinition(
      name: 'Telematics Module',
      shortName: 'TCU',
      category: ModuleCategory.network,
      description: 'Cellular connectivity, emergency call, remote services',
    ),
    0x790: ModuleDefinition(
      name: 'Driver Seat Module',
      shortName: 'DSM',
      category: ModuleCategory.comfort,
      description: 'Power seat control, memory positions, heating/cooling',
    ),
    0x7A0: ModuleDefinition(
      name: 'Battery Management System',
      shortName: 'BMS',
      category: ModuleCategory.powertrain,
      description: 'High voltage battery monitoring and control (hybrid/EV)',
    ),
    0x7B0: ModuleDefinition(
      name: 'Blind Spot Monitor',
      shortName: 'BSM',
      category: ModuleCategory.safety,
      description: 'Blind spot detection, lane change assist',
    ),
    0x7C0: ModuleDefinition(
      name: 'Adaptive Cruise Control',
      shortName: 'ACC',
      category: ModuleCategory.safety,
      description: 'Radar cruise control, collision warning, auto-braking',
    ),
    0x7D0: ModuleDefinition(
      name: 'Lane Keep Assist',
      shortName: 'LKA',
      category: ModuleCategory.safety,
      description: 'Lane departure warning, steering assist',
    ),
  };

  /// Get module definition by address
  static ModuleDefinition? getDefinition(int address) {
    return _knownModules[address];
  }

  /// Get default module definition for unknown address
  static ModuleDefinition getDefaultDefinition(int address) {
    return ModuleDefinition(
      name: 'Module 0x${address.toRadixString(16).toUpperCase()}',
      shortName: '0x${address.toRadixString(16).toUpperCase()}',
      category: ModuleCategory.unknown,
      description: 'Unknown module at address 0x${address.toRadixString(16).toUpperCase()}',
    );
  }
}

/// Module definition structure
class ModuleDefinition {
  final String name;
  final String shortName;
  final ModuleCategory category;
  final String description;

  const ModuleDefinition({
    required this.name,
    required this.shortName,
    required this.category,
    required this.description,
  });
}

/// Discovered vehicle module
class VehicleModule {
  final int address;
  final int responseAddress;
  final ModuleDefinition definition;
  String? softwareVersion;
  String? hardwareVersion;
  String? serialNumber;
  String? partNumber;
  List<DTCInfo> dtcs = [];
  List<SupportedFunction> supportedFunctions = [];
  bool isSecurityUnlocked = false;
  int currentSession = DiagnosticSession.defaultSession;

  VehicleModule({
    required this.address,
    required this.responseAddress,
    required this.definition,
    this.softwareVersion,
    this.hardwareVersion,
    this.serialNumber,
    this.partNumber,
  });

  String get name => definition.name;
  String get shortName => definition.shortName;
  ModuleCategory get category => definition.category;
  String get description => definition.description;

  /// Check if module has any DTCs
  bool get hasDTCs => dtcs.isNotEmpty;

  /// Get total DTC count
  int get dtcCount => dtcs.length;

  /// Get confirmed DTC count
  int get confirmedDTCCount => dtcs.where((d) => d.isConfirmed).length;

  /// Get pending DTC count
  int get pendingDTCCount => dtcs.where((d) => d.isPending).length;

  /// Check if this module requires security access for bi-directional control
  bool get requiresSecurityAccess {
    // Most modules require security for actuator tests
    switch (category) {
      case ModuleCategory.powertrain:
      case ModuleCategory.chassis:
      case ModuleCategory.safety:
        return true;
      default:
        return false;
    }
  }

  /// Get manufacturer (from part number or identification)
  String? get manufacturer {
    if (partNumber != null) {
      // Try to extract manufacturer from part number patterns
      if (partNumber!.startsWith('GM') || partNumber!.startsWith('12')) {
        return 'General Motors';
      } else if (partNumber!.startsWith('F') && partNumber!.length > 8) {
        return 'Ford';
      } else if (partNumber!.startsWith('89')) {
        return 'Toyota';
      }
    }
    return null;
  }

  @override
  String toString() => '$name (0x${address.toRadixString(16).toUpperCase()})';
}

/// Supported function for a module
class SupportedFunction {
  final String name;
  final String description;
  final FunctionType type;
  final int? routineId;
  final int? did;
  final List<FunctionParameter> parameters;

  SupportedFunction({
    required this.name,
    required this.description,
    required this.type,
    this.routineId,
    this.did,
    this.parameters = const [],
  });
}

/// Function types
enum FunctionType {
  readData('Read Data'),
  writeData('Write Data'),
  actuatorTest('Actuator Test'),
  routine('Routine'),
  reset('Reset'),
  clear('Clear/Reset'),
  calibration('Calibration'),
  programming('Programming');

  final String name;
  const FunctionType(this.name);
}

/// Function parameter definition
class FunctionParameter {
  final String name;
  final ParameterType type;
  final dynamic minValue;
  final dynamic maxValue;
  final dynamic defaultValue;
  final List<String>? options;

  FunctionParameter({
    required this.name,
    required this.type,
    this.minValue,
    this.maxValue,
    this.defaultValue,
    this.options,
  });
}

/// Parameter types
enum ParameterType {
  boolean,
  integer,
  float,
  selection,
  byteArray,
}

/// Module scanner service
class ModuleScanner {
  final VciInterface _vci;
  final List<VehicleModule> _discoveredModules = [];
  final _scanProgressController = StreamController<ScanProgress>.broadcast();

  Stream<ScanProgress> get scanProgress => _scanProgressController.stream;
  List<VehicleModule> get discoveredModules => List.unmodifiable(_discoveredModules);

  ModuleScanner(this._vci);

  /// Scan for all vehicle modules
  Future<List<VehicleModule>> scanAllModules({
    bool quickScan = false,
    void Function(ScanProgress)? onProgress,
  }) async {
    _discoveredModules.clear();

    final addressesToScan = quickScan
        ? KnownModules.priorityAddresses
        : KnownModules.standardRange;

    final totalAddresses = addressesToScan.length;
    var scannedCount = 0;

    for (final address in addressesToScan) {
      final progress = ScanProgress(
        currentAddress: address,
        scannedCount: scannedCount,
        totalCount: totalAddresses,
        foundModules: _discoveredModules.length,
        status: 'Scanning 0x${address.toRadixString(16).toUpperCase()}...',
      );

      _scanProgressController.add(progress);
      onProgress?.call(progress);

      try {
        final module = await _probeModule(address);
        if (module != null) {
          _discoveredModules.add(module);
        }
      } catch (e) {
        // Module didn't respond, continue scanning
      }

      scannedCount++;
    }

    // Sort modules by category and address
    _discoveredModules.sort((a, b) {
      final categoryCompare = a.category.index.compareTo(b.category.index);
      if (categoryCompare != 0) return categoryCompare;
      return a.address.compareTo(b.address);
    });

    final finalProgress = ScanProgress(
      currentAddress: 0,
      scannedCount: totalAddresses,
      totalCount: totalAddresses,
      foundModules: _discoveredModules.length,
      status: 'Scan complete - ${_discoveredModules.length} modules found',
      isComplete: true,
    );

    _scanProgressController.add(finalProgress);
    onProgress?.call(finalProgress);

    return _discoveredModules;
  }

  /// Probe a specific address for a module
  Future<VehicleModule?> _probeModule(int address) async {
    // Try TesterPresent first (most reliable)
    final testerPresentRequest = UDSRequest.testerPresent();
    final response = await _sendUDSRequest(address, testerPresentRequest);

    if (response == null || !response.isPositive) {
      // Try ReadDataByIdentifier as fallback
      final readRequest = UDSRequest.readDataByIdentifier([CommonDID.vin]);
      final readResponse = await _sendUDSRequest(address, readRequest);

      if (readResponse == null) {
        return null;
      }

      // Even negative response means module exists
      if (!readResponse.isPositive &&
          readResponse.negativeResponseCode ==
              NegativeResponseCode.serviceNotSupported) {
        return null;
      }
    }

    // Module found! Create entry
    final definition = ModuleDatabase.getDefinition(address) ??
        ModuleDatabase.getDefaultDefinition(address);

    final module = VehicleModule(
      address: address,
      responseAddress: address + 8, // Standard response offset
      definition: definition,
    );

    // Try to read module identification
    await _readModuleIdentification(module);

    return module;
  }

  /// Read module identification data
  Future<void> _readModuleIdentification(VehicleModule module) async {
    // Try to read software version
    try {
      final swRequest = UDSRequest.readDataByIdentifier(
          [CommonDID.applicationSoftwareIdentification]);
      final swResponse = await _sendUDSRequest(module.address, swRequest);
      if (swResponse?.isPositive == true && swResponse!.data.length > 2) {
        module.softwareVersion = String.fromCharCodes(swResponse.data.sublist(2))
            .replaceAll(RegExp(r'[^\x20-\x7E]'), '');
      }
    } catch (e) {
      // Identification read failed
    }

    // Try to read ECU serial number
    try {
      final snRequest =
          UDSRequest.readDataByIdentifier([CommonDID.ecuSerialNumber]);
      final snResponse = await _sendUDSRequest(module.address, snRequest);
      if (snResponse?.isPositive == true && snResponse!.data.length > 2) {
        module.serialNumber = String.fromCharCodes(snResponse.data.sublist(2))
            .replaceAll(RegExp(r'[^\x20-\x7E]'), '');
      }
    } catch (e) {
      // Serial number read failed
    }

    // Try to read part number
    try {
      final pnRequest = UDSRequest.readDataByIdentifier(
          [CommonDID.vehicleManufacturerSparePartNumber]);
      final pnResponse = await _sendUDSRequest(module.address, pnRequest);
      if (pnResponse?.isPositive == true && pnResponse!.data.length > 2) {
        module.partNumber = String.fromCharCodes(pnResponse.data.sublist(2))
            .replaceAll(RegExp(r'[^\x20-\x7E]'), '');
      }
    } catch (e) {
      // Part number read failed
    }
  }

  /// Read DTCs for a specific module
  Future<List<DTCInfo>> readModuleDTCs(VehicleModule module) async {
    final dtcs = <DTCInfo>[];

    // Read confirmed DTCs
    try {
      final confirmedRequest = UDSRequest.readDTCInformation(
        DTCReportType.reportDTCByStatusMask,
        statusMask: DTCStatusMask.confirmedDTC,
      );
      final confirmedResponse =
          await _sendUDSRequest(module.address, confirmedRequest);
      if (confirmedResponse?.isPositive == true) {
        dtcs.addAll(confirmedResponse!.parseDTCs());
      }
    } catch (e) {
      // DTC read failed
    }

    // Read pending DTCs
    try {
      final pendingRequest = UDSRequest.readDTCInformation(
        DTCReportType.reportDTCByStatusMask,
        statusMask: DTCStatusMask.pendingDTC,
      );
      final pendingResponse =
          await _sendUDSRequest(module.address, pendingRequest);
      if (pendingResponse?.isPositive == true) {
        for (final dtc in pendingResponse!.parseDTCs()) {
          // Avoid duplicates
          if (!dtcs.any((d) => d.dtcNumber == dtc.dtcNumber)) {
            dtcs.add(dtc);
          }
        }
      }
    } catch (e) {
      // Pending DTC read failed
    }

    module.dtcs = dtcs;
    return dtcs;
  }

  /// Clear DTCs for a specific module
  Future<bool> clearModuleDTCs(VehicleModule module) async {
    try {
      final clearRequest = UDSRequest.clearDiagnosticInformation();
      final response = await _sendUDSRequest(module.address, clearRequest);
      if (response?.isPositive == true) {
        module.dtcs.clear();
        return true;
      }
    } catch (e) {
      // Clear failed
    }
    return false;
  }

  /// Send UDS request to module
  Future<UDSResponse?> _sendUDSRequest(
      int address, UDSRequest request) async {
    try {
      // Build ISO-TP frame with module address
      final data = request.toBytes();
      final response = await _vci.sendUDSCommand(address, data.toList());

      if (response.isEmpty) return null;

      return UDSResponse.fromBytes(response);
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _scanProgressController.close();
  }
}

/// Scan progress information
class ScanProgress {
  final int currentAddress;
  final int scannedCount;
  final int totalCount;
  final int foundModules;
  final String status;
  final bool isComplete;

  ScanProgress({
    required this.currentAddress,
    required this.scannedCount,
    required this.totalCount,
    required this.foundModules,
    required this.status,
    this.isComplete = false,
  });

  double get progress => totalCount > 0 ? scannedCount / totalCount : 0;
}
