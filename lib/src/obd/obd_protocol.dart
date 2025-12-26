/// OBD-II Protocol Implementation
/// Supports standard PIDs and diagnostic commands
library;

/// OBD-II Service modes (SAE J1979)
enum OBDMode {
  currentData(0x01, 'Current Data'),
  freezeFrame(0x02, 'Freeze Frame'),
  storedDTCs(0x03, 'Stored DTCs'),
  clearDTCs(0x04, 'Clear DTCs'),
  oxygenSensorTest(0x05, 'O2 Sensor Test'),
  onboardTest(0x06, 'Onboard Test'),
  pendingDTCs(0x07, 'Pending DTCs'),
  controlOnboard(0x08, 'Control Onboard'),
  vehicleInfo(0x09, 'Vehicle Info'),
  permanentDTCs(0x0A, 'Permanent DTCs');

  final int code;
  final String description;
  const OBDMode(this.code, this.description);
}

/// Standard OBD-II PIDs for Mode 01 (Current Data)
enum OBDPid {
  supportedPids00(0x00, 'Supported PIDs [01-20]', '', PidDataType.bitEncoded),
  monitorStatus(0x01, 'Monitor Status', '', PidDataType.bitEncoded),
  freezeDtc(0x02, 'Freeze DTC', '', PidDataType.raw),
  fuelSystemStatus(0x03, 'Fuel System Status', '', PidDataType.bitEncoded),
  engineLoad(0x04, 'Calculated Engine Load', '%', PidDataType.percentage),
  coolantTemp(0x05, 'Engine Coolant Temperature', '°C', PidDataType.temperature),
  shortTermFuelBank1(0x06, 'Short Term Fuel Trim Bank 1', '%', PidDataType.fuelTrim),
  longTermFuelBank1(0x07, 'Long Term Fuel Trim Bank 1', '%', PidDataType.fuelTrim),
  shortTermFuelBank2(0x08, 'Short Term Fuel Trim Bank 2', '%', PidDataType.fuelTrim),
  longTermFuelBank2(0x09, 'Long Term Fuel Trim Bank 2', '%', PidDataType.fuelTrim),
  fuelPressure(0x0A, 'Fuel Pressure', 'kPa', PidDataType.pressure),
  intakeManifoldPressure(0x0B, 'Intake Manifold Pressure', 'kPa', PidDataType.raw),
  engineRpm(0x0C, 'Engine RPM', 'RPM', PidDataType.rpm),
  vehicleSpeed(0x0D, 'Vehicle Speed', 'km/h', PidDataType.raw),
  timingAdvance(0x0E, 'Timing Advance', '°', PidDataType.timing),
  intakeAirTemp(0x0F, 'Intake Air Temperature', '°C', PidDataType.temperature),
  mafAirFlow(0x10, 'MAF Air Flow Rate', 'g/s', PidDataType.maf),
  throttlePosition(0x11, 'Throttle Position', '%', PidDataType.percentage),
  commandedSecAirStatus(0x12, 'Commanded Secondary Air Status', '', PidDataType.bitEncoded),
  oxygenSensorsPresent(0x13, 'Oxygen Sensors Present', '', PidDataType.bitEncoded),
  oxygenSensor1(0x14, 'O2 Sensor 1', 'V', PidDataType.voltage),
  oxygenSensor2(0x15, 'O2 Sensor 2', 'V', PidDataType.voltage),
  oxygenSensor3(0x16, 'O2 Sensor 3', 'V', PidDataType.voltage),
  oxygenSensor4(0x17, 'O2 Sensor 4', 'V', PidDataType.voltage),
  obdStandard(0x1C, 'OBD Standard', '', PidDataType.raw),
  runTimeSinceStart(0x1F, 'Run Time Since Start', 's', PidDataType.raw),
  supportedPids20(0x20, 'Supported PIDs [21-40]', '', PidDataType.bitEncoded),
  distanceWithMil(0x21, 'Distance with MIL On', 'km', PidDataType.raw),
  fuelRailPressure(0x22, 'Fuel Rail Pressure', 'kPa', PidDataType.raw),
  fuelRailGaugePressure(0x23, 'Fuel Rail Gauge Pressure', 'kPa', PidDataType.raw),
  commandedEgr(0x2C, 'Commanded EGR', '%', PidDataType.percentage),
  egrError(0x2D, 'EGR Error', '%', PidDataType.signedPercentage),
  fuelTankLevel(0x2F, 'Fuel Tank Level', '%', PidDataType.percentage),
  warmupsSinceDtcClear(0x30, 'Warm-ups Since DTC Clear', '', PidDataType.raw),
  distanceSinceDtcClear(0x31, 'Distance Since DTC Clear', 'km', PidDataType.raw),
  barometricPressure(0x33, 'Barometric Pressure', 'kPa', PidDataType.raw),
  supportedPids40(0x40, 'Supported PIDs [41-60]', '', PidDataType.bitEncoded),
  controlModuleVoltage(0x42, 'Control Module Voltage', 'V', PidDataType.moduleVoltage),
  absoluteLoadValue(0x43, 'Absolute Load Value', '%', PidDataType.raw),
  ambientAirTemp(0x46, 'Ambient Air Temperature', '°C', PidDataType.temperature),
  engineOilTemp(0x5C, 'Engine Oil Temperature', '°C', PidDataType.temperature),
  fuelInjectionTiming(0x5D, 'Fuel Injection Timing', '°', PidDataType.raw),
  engineFuelRate(0x5E, 'Engine Fuel Rate', 'L/h', PidDataType.fuelRate),
  supportedPids60(0x60, 'Supported PIDs [61-80]', '', PidDataType.bitEncoded);

  final int code;
  final String description;
  final String unit;
  final PidDataType dataType;
  const OBDPid(this.code, this.description, this.unit, this.dataType);
}

enum PidDataType {
  raw,
  percentage,
  temperature,
  rpm,
  pressure,
  voltage,
  fuelTrim,
  timing,
  maf,
  bitEncoded,
  signedPercentage,
  moduleVoltage,
  fuelRate,
}

/// OBD Command builder and parser
class OBDCommand {
  final OBDMode mode;
  final int pid;
  final List<int>? data;

  OBDCommand({
    required this.mode,
    required this.pid,
    this.data,
  });

  /// Build command bytes to send to VCI
  List<int> toBytes() {
    final bytes = <int>[mode.code, pid];
    if (data != null) {
      bytes.addAll(data!);
    }
    return bytes;
  }

  /// Build AT command string (ELM327 compatible)
  String toATCommand() {
    final modeHex = mode.code.toRadixString(16).padLeft(2, '0').toUpperCase();
    final pidHex = pid.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '$modeHex$pidHex';
  }

  /// Parse response data based on PID type
  static dynamic parseResponse(OBDPid pid, List<int> data) {
    if (data.isEmpty) return null;

    switch (pid.dataType) {
      case PidDataType.raw:
        return _parseRaw(data);
      case PidDataType.percentage:
        return _parsePercentage(data);
      case PidDataType.temperature:
        return _parseTemperature(data);
      case PidDataType.rpm:
        return _parseRPM(data);
      case PidDataType.pressure:
        return _parsePressure(data);
      case PidDataType.voltage:
        return _parseVoltage(data);
      case PidDataType.fuelTrim:
        return _parseFuelTrim(data);
      case PidDataType.timing:
        return _parseTiming(data);
      case PidDataType.maf:
        return _parseMAF(data);
      case PidDataType.bitEncoded:
        return _parseBitEncoded(data);
      case PidDataType.signedPercentage:
        return _parseSignedPercentage(data);
      case PidDataType.moduleVoltage:
        return _parseModuleVoltage(data);
      case PidDataType.fuelRate:
        return _parseFuelRate(data);
    }
  }

  static int _parseRaw(List<int> data) {
    if (data.length == 1) return data[0];
    if (data.length == 2) return (data[0] << 8) | data[1];
    return data.fold(0, (acc, byte) => (acc << 8) | byte);
  }

  static double _parsePercentage(List<int> data) {
    return data[0] * 100.0 / 255.0;
  }

  static int _parseTemperature(List<int> data) {
    return data[0] - 40;
  }

  static double _parseRPM(List<int> data) {
    return ((data[0] << 8) | data[1]) / 4.0;
  }

  static int _parsePressure(List<int> data) {
    return data[0] * 3;
  }

  static double _parseVoltage(List<int> data) {
    return data[0] / 200.0;
  }

  static double _parseFuelTrim(List<int> data) {
    return (data[0] - 128) * 100.0 / 128.0;
  }

  static double _parseTiming(List<int> data) {
    return (data[0] - 128) / 2.0;
  }

  static double _parseMAF(List<int> data) {
    return ((data[0] << 8) | data[1]) / 100.0;
  }

  static List<bool> _parseBitEncoded(List<int> data) {
    final bits = <bool>[];
    for (final byte in data) {
      for (var i = 7; i >= 0; i--) {
        bits.add((byte >> i) & 1 == 1);
      }
    }
    return bits;
  }

  static double _parseSignedPercentage(List<int> data) {
    final signed = data[0] > 127 ? data[0] - 256 : data[0];
    return signed * 100.0 / 128.0;
  }

  static double _parseModuleVoltage(List<int> data) {
    return ((data[0] << 8) | data[1]) / 1000.0;
  }

  static double _parseFuelRate(List<int> data) {
    return ((data[0] << 8) | data[1]) / 20.0;
  }
}

/// Diagnostic Trouble Code (DTC) representation
class DTC {
  final String code;
  final DTCCategory category;
  final int rawValue;

  DTC({
    required this.code,
    required this.category,
    required this.rawValue,
  });

  /// Parse DTC from 2 bytes of data
  factory DTC.fromBytes(int byte1, int byte2) {
    final firstChar = _getFirstChar((byte1 >> 6) & 0x03);
    final secondChar = ((byte1 >> 4) & 0x03).toRadixString(16).toUpperCase();
    final thirdChar = (byte1 & 0x0F).toRadixString(16).toUpperCase();
    final fourthChar = ((byte2 >> 4) & 0x0F).toRadixString(16).toUpperCase();
    final fifthChar = (byte2 & 0x0F).toRadixString(16).toUpperCase();

    final code = '$firstChar$secondChar$thirdChar$fourthChar$fifthChar';
    final category = DTCCategory.fromCode(code);

    return DTC(
      code: code,
      category: category,
      rawValue: (byte1 << 8) | byte2,
    );
  }

  static String _getFirstChar(int value) {
    switch (value) {
      case 0:
        return 'P'; // Powertrain
      case 1:
        return 'C'; // Chassis
      case 2:
        return 'B'; // Body
      case 3:
        return 'U'; // Network
      default:
        return 'P';
    }
  }

  @override
  String toString() => code;
}

enum DTCCategory {
  powertrain('P', 'Powertrain'),
  chassis('C', 'Chassis'),
  body('B', 'Body'),
  network('U', 'Network/Communication');

  final String prefix;
  final String description;
  const DTCCategory(this.prefix, this.description);

  static DTCCategory fromCode(String code) {
    if (code.isEmpty) return DTCCategory.powertrain;
    switch (code[0]) {
      case 'C':
        return DTCCategory.chassis;
      case 'B':
        return DTCCategory.body;
      case 'U':
        return DTCCategory.network;
      default:
        return DTCCategory.powertrain;
    }
  }
}

/// VIN (Vehicle Identification Number) decoder
class VINDecoder {
  final String vin;

  VINDecoder(this.vin);

  bool get isValid => vin.length == 17 && _validateCheckDigit();

  String get worldManufacturerIdentifier => vin.substring(0, 3);
  String get vehicleDescriptorSection => vin.substring(3, 9);
  String get vehicleIdentifierSection => vin.substring(9, 17);
  String get modelYear => _decodeModelYear(vin[9]);
  String get plantCode => vin[10];
  String get serialNumber => vin.substring(11, 17);

  bool _validateCheckDigit() {
    const transliteration = {
      'A': 1, 'B': 2, 'C': 3, 'D': 4, 'E': 5, 'F': 6, 'G': 7, 'H': 8,
      'J': 1, 'K': 2, 'L': 3, 'M': 4, 'N': 5, 'P': 7, 'R': 9,
      'S': 2, 'T': 3, 'U': 4, 'V': 5, 'W': 6, 'X': 7, 'Y': 8, 'Z': 9,
    };
    const weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2];

    var sum = 0;
    for (var i = 0; i < 17; i++) {
      final char = vin[i].toUpperCase();
      int value;
      if (RegExp(r'[0-9]').hasMatch(char)) {
        value = int.parse(char);
      } else {
        value = transliteration[char] ?? 0;
      }
      sum += value * weights[i];
    }

    final checkDigit = sum % 11;
    final expected = checkDigit == 10 ? 'X' : checkDigit.toString();
    return vin[8].toUpperCase() == expected;
  }

  String _decodeModelYear(String char) {
    const yearCodes = {
      'A': '2010', 'B': '2011', 'C': '2012', 'D': '2013', 'E': '2014',
      'F': '2015', 'G': '2016', 'H': '2017', 'J': '2018', 'K': '2019',
      'L': '2020', 'M': '2021', 'N': '2022', 'P': '2023', 'R': '2024',
      'S': '2025', 'T': '2026', 'V': '2027', 'W': '2028', 'X': '2029',
      'Y': '2030', '1': '2001', '2': '2002', '3': '2003', '4': '2004',
      '5': '2005', '6': '2006', '7': '2007', '8': '2008', '9': '2009',
    };
    return yearCodes[char.toUpperCase()] ?? 'Unknown';
  }
}
