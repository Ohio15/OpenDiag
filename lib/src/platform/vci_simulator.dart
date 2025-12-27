import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'vci_interface.dart';

/// Simulated VCI implementation for testing without a real OBD-II adapter
/// Provides realistic vehicle data simulation with multiple driving scenarios
class VciSimulator implements VciInterface {
  final _responseController = StreamController<List<int>>.broadcast();
  final _stateController = StreamController<VciConnectionState>.broadcast();

  VciConnectionState _state = VciConnectionState.disconnected;
  Timer? _simulationTimer;
  final Random _random = Random();

  // Simulation state
  SimulatorScenario _scenario = SimulatorScenario.idle;
  final SimulatorVehicle _vehicle = SimulatorVehicle();
  final List<SimulatedDTC> _activeDTCs = [];
  bool _milOn = false;

  // Protocol state
  String _selectedProtocol = 'AUTO';
  bool _echoEnabled = true;
  bool _headersEnabled = false;
  bool _spacesEnabled = true;

  @override
  Stream<List<int>> get responseStream => _responseController.stream;

  @override
  Stream<VciConnectionState> get connectionStateStream => _stateController.stream;

  @override
  VciConnectionState get state => _state;

  @override
  bool get isConnected => _state == VciConnectionState.connected;

  /// Current simulation scenario
  SimulatorScenario get scenario => _scenario;

  /// Set the simulation scenario
  set scenario(SimulatorScenario value) {
    _scenario = value;
    _vehicle.applyScenario(value);
  }

  /// Active DTCs in the simulation
  List<SimulatedDTC> get activeDTCs => List.unmodifiable(_activeDTCs);

  /// Whether the MIL (check engine light) is on
  bool get milOn => _milOn;

  /// Add a DTC to the simulation
  void addDTC(String code, {bool isPending = false}) {
    _activeDTCs.add(SimulatedDTC(code: code, isPending: isPending));
    _milOn = _activeDTCs.any((dtc) => !dtc.isPending);
  }

  /// Clear all DTCs
  void clearDTCs() {
    _activeDTCs.clear();
    _milOn = false;
  }

  /// Get the simulated vehicle state
  SimulatorVehicle get vehicle => _vehicle;

  @override
  Future<List<VciDeviceInfo>> scanForDevices({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _setState(VciConnectionState.scanning);

    // Simulate scan delay
    await Future.delayed(const Duration(milliseconds: 500));

    _setState(VciConnectionState.disconnected);

    return [
      VciDeviceInfo(
        id: 'SIMULATOR_001',
        name: 'OpenDiag Simulator',
        type: VciDeviceType.elm327,
        signalStrength: -50,
        description: 'Virtual OBD-II adapter for testing',
      ),
      VciDeviceInfo(
        id: 'SIMULATOR_002',
        name: 'Simulator (Sport Car)',
        type: VciDeviceType.elm327,
        signalStrength: -55,
        description: 'High-performance vehicle simulation',
      ),
      VciDeviceInfo(
        id: 'SIMULATOR_003',
        name: 'Simulator (Diesel Truck)',
        type: VciDeviceType.elm327,
        signalStrength: -60,
        description: 'Diesel engine simulation',
      ),
    ];
  }

  @override
  Future<void> connect(VciDeviceInfo device) async {
    _setState(VciConnectionState.connecting);

    // Simulate connection delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Configure based on device type
    if (device.id == 'SIMULATOR_002') {
      _vehicle.configureAsSportsCar();
    } else if (device.id == 'SIMULATOR_003') {
      _vehicle.configureAsDieselTruck();
    } else {
      _vehicle.configureAsStandardCar();
    }

    _setState(VciConnectionState.connected);
    _startSimulation();
  }

  @override
  Future<void> disconnect() async {
    _stopSimulation();
    _setState(VciConnectionState.disconnected);
  }

  @override
  Future<List<int>> sendCommand(List<int> command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Convert bytes to AT command if it looks like ASCII
    if (command.every((b) => b >= 0x20 && b <= 0x7E)) {
      final cmdStr = String.fromCharCodes(command).trim();
      final response = await sendATCommand(cmdStr, timeout: timeout);
      return response.codeUnits;
    }

    // Handle raw OBD command
    return _handleRawCommand(command);
  }

  @override
  Future<String> sendATCommand(String command, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Simulate response delay
    await Future.delayed(Duration(milliseconds: 20 + _random.nextInt(30)));

    final cmd = command.toUpperCase().trim();

    // Handle AT commands
    if (cmd.startsWith('AT')) {
      return _handleATCommand(cmd);
    }

    // Handle OBD commands (mode + PID in hex)
    return _handleOBDCommand(cmd);
  }

  @override
  Future<List<int>> sendUDSCommand(int moduleAddress, List<int> data, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // Simulate UDS response
    await Future.delayed(Duration(milliseconds: 50 + _random.nextInt(50)));

    if (data.isEmpty) return [0x7F, 0x00, 0x12]; // Negative response

    final serviceId = data[0];

    switch (serviceId) {
      case 0x10: // Diagnostic Session Control
        return [0x50, data.length > 1 ? data[1] : 0x01];
      case 0x22: // Read Data By Identifier
        if (data.length >= 3) {
          final did = (data[1] << 8) | data[2];
          return _handleUDSReadDID(did);
        }
        return [0x7F, 0x22, 0x13];
      case 0x19: // Read DTC Information
        return _handleUDSReadDTC(data);
      case 0x14: // Clear DTC
        clearDTCs();
        return [0x54];
      case 0x3E: // Tester Present
        return [0x7E, 0x00];
      default:
        return [0x7F, serviceId, 0x11]; // Service not supported
    }
  }

  String _handleATCommand(String cmd) {
    switch (cmd) {
      case 'ATZ': // Reset
        _echoEnabled = true;
        _headersEnabled = false;
        _spacesEnabled = true;
        return 'ELM327 v1.5 (Simulator)';
      case 'ATE0': // Echo off
        _echoEnabled = false;
        return 'OK';
      case 'ATE1': // Echo on
        _echoEnabled = true;
        return 'OK';
      case 'ATL0': // Linefeeds off
        return 'OK';
      case 'ATL1': // Linefeeds on
        return 'OK';
      case 'ATS0': // Spaces off
        _spacesEnabled = false;
        return 'OK';
      case 'ATS1': // Spaces on
        _spacesEnabled = true;
        return 'OK';
      case 'ATH0': // Headers off
        _headersEnabled = false;
        return 'OK';
      case 'ATH1': // Headers on
        _headersEnabled = true;
        return 'OK';
      case 'ATSP0': // Set protocol auto
        _selectedProtocol = 'AUTO';
        return 'OK';
      case 'ATI': // Version
        return 'ELM327 v1.5 (OpenDiag Simulator)';
      case 'AT@1': // Device description
        return 'OpenDiag Virtual OBD-II Adapter';
      case 'ATRV': // Read voltage
        return '${(12.4 + _random.nextDouble() * 0.4).toStringAsFixed(1)}V';
      case 'ATDP': // Describe protocol
        return 'AUTO, ISO 15765-4 (CAN 11/500)';
      case 'ATDPN': // Describe protocol number
        return '6';
      default:
        if (cmd.startsWith('ATSP')) {
          _selectedProtocol = cmd.substring(4);
          return 'OK';
        }
        if (cmd.startsWith('ATST')) {
          return 'OK'; // Set timeout
        }
        if (cmd.startsWith('ATAT')) {
          return 'OK'; // Adaptive timing
        }
        return 'OK';
    }
  }

  String _handleOBDCommand(String cmd) {
    if (cmd.length < 4) return 'NO DATA';

    final mode = int.tryParse(cmd.substring(0, 2), radix: 16) ?? 0;
    final pid = int.tryParse(cmd.substring(2, 4), radix: 16) ?? 0;

    switch (mode) {
      case 0x01: // Current data
        return _handleMode01(pid);
      case 0x02: // Freeze frame
        return _handleMode02(pid);
      case 0x03: // Stored DTCs
        return _handleMode03();
      case 0x04: // Clear DTCs
        clearDTCs();
        return '44';
      case 0x07: // Pending DTCs
        return _handleMode07();
      case 0x09: // Vehicle info
        return _handleMode09(pid);
      default:
        return 'NO DATA';
    }
  }

  String _handleMode01(int pid) {
    final v = _vehicle;
    String data;

    switch (pid) {
      case 0x00: // Supported PIDs 01-20
        data = 'BE1FA813'; // Bitmap of supported PIDs
        break;
      case 0x01: // Monitor status
        final dtcCount = _activeDTCs.where((d) => !d.isPending).length;
        final milBit = _milOn ? 0x80 : 0x00;
        data = _toHex(milBit | (dtcCount & 0x7F)) + '070700';
        break;
      case 0x03: // Fuel system status
        data = '0100';
        break;
      case 0x04: // Engine load
        data = _toHex((v.engineLoad * 255 / 100).round().clamp(0, 255));
        break;
      case 0x05: // Coolant temp
        data = _toHex((v.coolantTemp + 40).round().clamp(0, 255));
        break;
      case 0x06: // Short term fuel trim bank 1
        data = _toHex(((v.shortTermFuelTrim + 100) * 128 / 100).round().clamp(0, 255));
        break;
      case 0x07: // Long term fuel trim bank 1
        data = _toHex(((v.longTermFuelTrim + 100) * 128 / 100).round().clamp(0, 255));
        break;
      case 0x0B: // Intake manifold pressure
        data = _toHex(v.intakeManifoldPressure.round().clamp(0, 255));
        break;
      case 0x0C: // Engine RPM
        final rpmValue = (v.rpm * 4).round().clamp(0, 65535);
        data = _toHex(rpmValue >> 8) + _toHex(rpmValue & 0xFF);
        break;
      case 0x0D: // Vehicle speed
        data = _toHex(v.speed.round().clamp(0, 255));
        break;
      case 0x0E: // Timing advance
        data = _toHex(((v.timingAdvance + 64) * 2).round().clamp(0, 255));
        break;
      case 0x0F: // Intake air temp
        data = _toHex((v.intakeAirTemp + 40).round().clamp(0, 255));
        break;
      case 0x10: // MAF rate
        final mafValue = (v.mafRate * 100).round().clamp(0, 65535);
        data = _toHex(mafValue >> 8) + _toHex(mafValue & 0xFF);
        break;
      case 0x11: // Throttle position
        data = _toHex((v.throttlePosition * 255 / 100).round().clamp(0, 255));
        break;
      case 0x1C: // OBD standard
        data = '06'; // ISO 15765-4
        break;
      case 0x1F: // Run time since start
        final runtime = v.runTimeSinceStart.clamp(0, 65535);
        data = _toHex(runtime >> 8) + _toHex(runtime & 0xFF);
        break;
      case 0x20: // Supported PIDs 21-40
        data = '8007B015';
        break;
      case 0x21: // Distance with MIL
        final dist = _milOn ? _random.nextInt(500) : 0;
        data = _toHex(dist >> 8) + _toHex(dist & 0xFF);
        break;
      case 0x2F: // Fuel tank level
        data = _toHex((v.fuelLevel * 255 / 100).round().clamp(0, 255));
        break;
      case 0x31: // Distance since DTC clear
        final dist = 150 + _random.nextInt(1000);
        data = _toHex(dist >> 8) + _toHex(dist & 0xFF);
        break;
      case 0x33: // Barometric pressure
        data = _toHex(v.barometricPressure.round().clamp(0, 255));
        break;
      case 0x40: // Supported PIDs 41-60
        data = '7ED00011';
        break;
      case 0x42: // Control module voltage
        final voltage = ((v.batteryVoltage) * 1000).round().clamp(0, 65535);
        data = _toHex(voltage >> 8) + _toHex(voltage & 0xFF);
        break;
      case 0x46: // Ambient air temp
        data = _toHex((v.ambientAirTemp + 40).round().clamp(0, 255));
        break;
      case 0x5C: // Engine oil temp
        data = _toHex((v.oilTemp + 40).round().clamp(0, 255));
        break;
      case 0x5E: // Fuel rate
        final fuelRate = (v.fuelRate * 20).round().clamp(0, 65535);
        data = _toHex(fuelRate >> 8) + _toHex(fuelRate & 0xFF);
        break;
      case 0x60: // Supported PIDs 61-80
        data = '00000001';
        break;
      default:
        return 'NO DATA';
    }

    // Format response: 41 [PID] [DATA]
    final response = '41${_toHex(pid)}$data';
    return _spacesEnabled ? _addSpaces(response) : response;
  }

  String _handleMode02(int pid) {
    // Freeze frame - return similar to mode 01 but for stored frame
    if (_activeDTCs.isEmpty) return 'NO DATA';
    return _handleMode01(pid).replaceFirst('41', '42');
  }

  String _handleMode03() {
    final storedDTCs = _activeDTCs.where((d) => !d.isPending).toList();
    if (storedDTCs.isEmpty) return '43 00';

    final buffer = StringBuffer('43');
    buffer.write(_toHex(storedDTCs.length));

    for (final dtc in storedDTCs) {
      final bytes = _dtcToBytes(dtc.code);
      buffer.write(_toHex(bytes[0]));
      buffer.write(_toHex(bytes[1]));
    }

    final response = buffer.toString();
    return _spacesEnabled ? _addSpaces(response) : response;
  }

  String _handleMode07() {
    final pendingDTCs = _activeDTCs.where((d) => d.isPending).toList();
    if (pendingDTCs.isEmpty) return '47 00';

    final buffer = StringBuffer('47');
    buffer.write(_toHex(pendingDTCs.length));

    for (final dtc in pendingDTCs) {
      final bytes = _dtcToBytes(dtc.code);
      buffer.write(_toHex(bytes[0]));
      buffer.write(_toHex(bytes[1]));
    }

    final response = buffer.toString();
    return _spacesEnabled ? _addSpaces(response) : response;
  }

  String _handleMode09(int pid) {
    switch (pid) {
      case 0x00: // Supported PIDs
        return _formatResponse('49', pid, '55400000');
      case 0x02: // VIN
        final vinBytes = _vehicle.vin.codeUnits;
        final hexVin = vinBytes.map((b) => _toHex(b)).join();
        return _formatResponse('49', pid, '01$hexVin');
      case 0x04: // Calibration ID
        return _formatResponse('49', pid, '014F50454E444941475F53494D');
      case 0x06: // CVN
        return _formatResponse('49', pid, '01DEADBEEF');
      case 0x0A: // ECU name
        final name = 'ECM-Simulator';
        final hexName = name.codeUnits.map((b) => _toHex(b)).join();
        return _formatResponse('49', pid, '01$hexName');
      default:
        return 'NO DATA';
    }
  }

  List<int> _handleRawCommand(List<int> command) {
    // Simple echo for now
    return command;
  }

  List<int> _handleUDSReadDID(int did) {
    switch (did) {
      case 0xF190: // VIN
        return [0x62, 0xF1, 0x90, ..._vehicle.vin.codeUnits];
      case 0xF187: // Part number
        return [0x62, 0xF1, 0x87, ...('SIM-ECU-001').codeUnits];
      case 0xF18C: // Serial number
        return [0x62, 0xF1, 0x8C, ...('000000001').codeUnits];
      case 0xF197: // System name
        return [0x62, 0xF1, 0x97, ...('OpenDiag Sim').codeUnits];
      default:
        return [0x7F, 0x22, 0x31]; // Request out of range
    }
  }

  List<int> _handleUDSReadDTC(List<int> data) {
    if (data.length < 2) return [0x7F, 0x19, 0x12];

    final subFunction = data[1];

    switch (subFunction) {
      case 0x01: // Report number of DTCs
        final count = _activeDTCs.length;
        return [0x59, 0x01, 0xFF, count >> 8, count & 0xFF];
      case 0x02: // Report DTCs by status mask
        final result = <int>[0x59, 0x02, 0xFF];
        for (final dtc in _activeDTCs) {
          final bytes = _dtcToBytes(dtc.code);
          result.addAll([bytes[0], bytes[1], 0x00, dtc.isPending ? 0x04 : 0x09]);
        }
        return result;
      default:
        return [0x7F, 0x19, 0x12];
    }
  }

  List<int> _dtcToBytes(String code) {
    if (code.length != 5) return [0, 0];

    int firstByte = 0;
    switch (code[0]) {
      case 'P': firstByte = 0x00; break;
      case 'C': firstByte = 0x40; break;
      case 'B': firstByte = 0x80; break;
      case 'U': firstByte = 0xC0; break;
    }

    firstByte |= (int.tryParse(code[1], radix: 16) ?? 0) << 4;
    firstByte |= (int.tryParse(code[2], radix: 16) ?? 0);

    final secondByte = int.tryParse(code.substring(3), radix: 16) ?? 0;

    return [firstByte, secondByte];
  }

  String _toHex(int value) {
    return value.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  String _addSpaces(String hex) {
    final buffer = StringBuffer();
    for (var i = 0; i < hex.length; i += 2) {
      if (i > 0) buffer.write(' ');
      buffer.write(hex.substring(i, min(i + 2, hex.length)));
    }
    return buffer.toString();
  }

  String _formatResponse(String mode, int pid, String data) {
    final response = '$mode${_toHex(pid)}$data';
    return _spacesEnabled ? _addSpaces(response) : response;
  }

  void _startSimulation() {
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _vehicle.update(_scenario, _random);
    });
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
  }

  void _setState(VciConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  @override
  void dispose() {
    _stopSimulation();
    _responseController.close();
    _stateController.close();
  }
}

/// Simulation scenarios
enum SimulatorScenario {
  /// Engine off
  off,

  /// Engine idling
  idle,

  /// City driving (stop and go)
  cityDriving,

  /// Highway cruising
  highway,

  /// Aggressive/sport driving
  aggressive,

  /// Cold start warm-up
  coldStart,

  /// Engine problem (misfiring, rough idle)
  engineProblem,

  /// Overheating
  overheating,
}

/// Simulated vehicle state
class SimulatorVehicle {
  // Engine parameters
  double rpm = 0;
  double speed = 0;
  double coolantTemp = 20;
  double intakeAirTemp = 25;
  double oilTemp = 20;
  double throttlePosition = 0;
  double engineLoad = 0;
  double mafRate = 0;
  double timingAdvance = 10;
  double intakeManifoldPressure = 101;
  double shortTermFuelTrim = 0;
  double longTermFuelTrim = 0;
  double fuelLevel = 75;
  double fuelRate = 0;
  double batteryVoltage = 12.6;
  double ambientAirTemp = 22;
  double barometricPressure = 101;
  int runTimeSinceStart = 0;

  // Vehicle config
  String vin = 'WVWZZZ3CZWE123456';
  double maxRpm = 6500;
  double maxSpeed = 220;
  double idleRpm = 800;
  double normalCoolantTemp = 90;
  double normalOilTemp = 100;

  // Target values for smooth transitions
  double _targetRpm = 0;
  double _targetSpeed = 0;
  double _targetThrottle = 0;

  void configureAsStandardCar() {
    vin = 'WVWZZZ3CZWE123456';
    maxRpm = 6500;
    maxSpeed = 200;
    idleRpm = 800;
    normalCoolantTemp = 90;
    normalOilTemp = 95;
  }

  void configureAsSportsCar() {
    vin = '1G1YY22G965109876';
    maxRpm = 8000;
    maxSpeed = 280;
    idleRpm = 900;
    normalCoolantTemp = 95;
    normalOilTemp = 110;
  }

  void configureAsDieselTruck() {
    vin = '1FTFW1E88KFA12345';
    maxRpm = 4500;
    maxSpeed = 160;
    idleRpm = 650;
    normalCoolantTemp = 85;
    normalOilTemp = 90;
  }

  void applyScenario(SimulatorScenario scenario) {
    switch (scenario) {
      case SimulatorScenario.off:
        _targetRpm = 0;
        _targetSpeed = 0;
        _targetThrottle = 0;
        break;
      case SimulatorScenario.idle:
        _targetRpm = idleRpm;
        _targetSpeed = 0;
        _targetThrottle = 0;
        break;
      case SimulatorScenario.cityDriving:
        _targetRpm = 2000;
        _targetSpeed = 40;
        _targetThrottle = 20;
        break;
      case SimulatorScenario.highway:
        _targetRpm = 2800;
        _targetSpeed = 110;
        _targetThrottle = 35;
        break;
      case SimulatorScenario.aggressive:
        _targetRpm = 5500;
        _targetSpeed = 160;
        _targetThrottle = 85;
        break;
      case SimulatorScenario.coldStart:
        _targetRpm = idleRpm + 400;
        _targetSpeed = 0;
        _targetThrottle = 0;
        coolantTemp = 10;
        oilTemp = 10;
        break;
      case SimulatorScenario.engineProblem:
        _targetRpm = idleRpm - 100;
        _targetSpeed = 0;
        _targetThrottle = 0;
        break;
      case SimulatorScenario.overheating:
        _targetRpm = idleRpm;
        _targetSpeed = 0;
        _targetThrottle = 0;
        coolantTemp = 105;
        break;
    }
  }

  void update(SimulatorScenario scenario, Random random) {
    runTimeSinceStart++;

    // Smooth transitions
    rpm = _lerp(rpm, _targetRpm, 0.1);
    speed = _lerp(speed, _targetSpeed, 0.08);
    throttlePosition = _lerp(throttlePosition, _targetThrottle, 0.15);

    // Add realistic variations
    if (rpm > 0) {
      rpm += (random.nextDouble() - 0.5) * 50;
      rpm = rpm.clamp(0, maxRpm);
    }

    if (speed > 0) {
      speed += (random.nextDouble() - 0.5) * 2;
      speed = speed.clamp(0, maxSpeed);
    }

    // Calculate derived values
    engineLoad = (throttlePosition * 0.8 + (rpm / maxRpm) * 20).clamp(0, 100);
    mafRate = (rpm / 1000) * (throttlePosition / 100 + 0.1) * 15;
    fuelRate = mafRate * 0.068; // Approximate fuel consumption
    timingAdvance = 10 + (rpm / 1000) * 3 - (engineLoad / 100) * 5;
    intakeManifoldPressure = 30 + (throttlePosition * 0.7);

    // Temperature dynamics
    if (rpm > 0) {
      // Warm up
      if (coolantTemp < normalCoolantTemp) {
        coolantTemp += 0.05;
      } else if (scenario == SimulatorScenario.overheating) {
        coolantTemp += 0.02;
        coolantTemp = coolantTemp.clamp(0, 130);
      } else {
        coolantTemp = _lerp(coolantTemp, normalCoolantTemp, 0.01);
      }

      if (oilTemp < normalOilTemp) {
        oilTemp += 0.03;
      } else {
        oilTemp = _lerp(oilTemp, normalOilTemp + (engineLoad / 10), 0.01);
      }
    } else {
      // Cool down
      coolantTemp = _lerp(coolantTemp, ambientAirTemp, 0.005);
      oilTemp = _lerp(oilTemp, ambientAirTemp, 0.003);
    }

    // Fuel trim variations
    shortTermFuelTrim = (random.nextDouble() - 0.5) * 6;
    if (scenario == SimulatorScenario.engineProblem) {
      shortTermFuelTrim += 10;
      longTermFuelTrim = 8;
    } else {
      longTermFuelTrim = _lerp(longTermFuelTrim, 0, 0.01);
    }

    // Battery voltage
    if (rpm > 0) {
      batteryVoltage = 13.8 + (random.nextDouble() - 0.5) * 0.4;
    } else {
      batteryVoltage = 12.4 + (random.nextDouble() - 0.5) * 0.2;
    }

    // Fuel consumption
    if (rpm > 0 && fuelLevel > 0) {
      fuelLevel -= fuelRate * 0.0001;
      fuelLevel = fuelLevel.clamp(0, 100);
    }

    // City driving scenario - vary speed and RPM
    if (scenario == SimulatorScenario.cityDriving) {
      if (random.nextDouble() < 0.02) {
        // Occasionally stop
        _targetSpeed = random.nextDouble() < 0.5 ? 0 : (30 + random.nextInt(30)).toDouble();
        _targetRpm = _targetSpeed == 0 ? idleRpm : (1500 + random.nextInt(1500)).toDouble();
        _targetThrottle = _targetSpeed == 0 ? 0 : (10 + random.nextInt(40)).toDouble();
      }
    }

    // Engine problem - rough idle
    if (scenario == SimulatorScenario.engineProblem) {
      rpm += (random.nextDouble() - 0.5) * 150;
      rpm = rpm.clamp(idleRpm - 200, idleRpm + 200);
    }
  }

  double _lerp(double current, double target, double factor) {
    return current + (target - current) * factor;
  }
}

/// Simulated DTC
class SimulatedDTC {
  final String code;
  final bool isPending;

  SimulatedDTC({required this.code, this.isPending = false});
}
