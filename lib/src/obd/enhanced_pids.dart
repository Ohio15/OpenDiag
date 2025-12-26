/// Enhanced OBD-II PIDs and Manufacturer-Specific Codes
library;

/// Extended Mode 01 PIDs (0x60 and above)
enum ExtendedPid {
  // Mode 01 PIDs 0x60-0x80
  supportedPids61_80(0x60, 'Supported PIDs [61-80]', '', ExtPidType.bitEncoded),
  engineReferenceTorque(0x63, 'Engine Reference Torque', 'Nm', ExtPidType.torque),
  enginePercentTorque(0x64, 'Engine Percent Torque', '%', ExtPidType.multiPercentage),
  auxInputOutput(0x65, 'Auxiliary Input/Output', '', ExtPidType.bitEncoded),
  massAirFlowSensor(0x66, 'Mass Air Flow Sensor', 'g/s', ExtPidType.dualMaf),
  engineCoolantTemp2(0x67, 'Engine Coolant Temperature 2', '°C', ExtPidType.dualTemperature),
  intakeAirTemp2(0x68, 'Intake Air Temperature 2', '°C', ExtPidType.dualTemperature),
  commandedEgr2(0x69, 'Commanded EGR 2', '%', ExtPidType.egrData),
  dieselIntakeAirFlow(0x6A, 'Diesel Intake Air Flow', '', ExtPidType.raw),
  exhaustGasTemp(0x6B, 'Exhaust Gas Temperature Bank 1', '°C', ExtPidType.exhaustTemp),
  exhaustGasTempBank2(0x6C, 'Exhaust Gas Temperature Bank 2', '°C', ExtPidType.exhaustTemp),
  throttleActuator(0x6D, 'Throttle Actuator Control', '', ExtPidType.raw),
  fuelPressureControl(0x6E, 'Fuel Pressure Control', 'kPa', ExtPidType.raw),
  injectionPressure(0x6F, 'Injection Pressure Control', 'kPa', ExtPidType.raw),
  turboCompressorInletPressure(0x70, 'Turbo Compressor Inlet Pressure', 'kPa', ExtPidType.raw),
  boostPressureControl(0x71, 'Boost Pressure Control', '', ExtPidType.raw),
  variableGeometryTurbo(0x72, 'Variable Geometry Turbo Control', '', ExtPidType.raw),
  wastegateControl(0x73, 'Wastegate Control', '', ExtPidType.raw),
  exhaustPressure(0x74, 'Exhaust Pressure', 'kPa', ExtPidType.raw),
  turboRpm(0x75, 'Turbocharger RPM', 'RPM', ExtPidType.turboRpm),
  turboTemp1(0x76, 'Turbocharger Temperature 1', '°C', ExtPidType.turboTemp),
  turboTemp2(0x77, 'Turbocharger Temperature 2', '°C', ExtPidType.turboTemp),
  chargeAirCoolerTemp(0x78, 'Charge Air Cooler Temperature', '°C', ExtPidType.temperature),
  exhaustGasTempBank1Sensor(0x79, 'EGT Bank 1 Sensors', '°C', ExtPidType.exhaustTemp),
  dpfDifferentialPressure(0x7A, 'DPF Differential Pressure', 'kPa', ExtPidType.raw),
  dpfInletPressure(0x7B, 'DPF Inlet Pressure', 'kPa', ExtPidType.raw),
  dpfOutletPressure(0x7C, 'DPF Outlet Pressure', 'kPa', ExtPidType.raw),
  dpfTemperature(0x7D, 'DPF Temperature', '°C', ExtPidType.exhaustTemp),
  noxSensor(0x7E, 'NOx Sensor', 'ppm', ExtPidType.nox),
  pmSensor(0x7F, 'PM Sensor', 'mg/m³', ExtPidType.raw),

  // Additional PIDs
  supportedPids81_A0(0x80, 'Supported PIDs [81-A0]', '', ExtPidType.bitEncoded),
  engineRunTime(0x81, 'Engine Run Time', 's', ExtPidType.runTime),
  engineRunTimeAECD1(0x82, 'Engine Run Time AECD 1', 's', ExtPidType.runTime),
  engineRunTimeAECD2(0x83, 'Engine Run Time AECD 2', 's', ExtPidType.runTime),
  noxSensorCorrected(0x84, 'NOx Sensor Corrected', 'ppm', ExtPidType.nox),
  noxSensorAlternative(0x85, 'NOx Sensor Alternative', 'ppm', ExtPidType.nox),
  pmSensorBank1(0x86, 'PM Sensor Bank 1', 'mg/m³', ExtPidType.raw),
  intakeManifoldAbsPressure(0x87, 'Intake Manifold Abs Pressure', 'kPa', ExtPidType.raw),
  scrInducement(0x88, 'SCR Inducement System', '', ExtPidType.raw),
  engineFrictionTorque(0x8E, 'Engine Friction Torque', '%', ExtPidType.percentage),
  pmSensorBank2(0x8F, 'PM Sensor Bank 2', 'mg/m³', ExtPidType.raw);

  final int code;
  final String description;
  final String unit;
  final ExtPidType dataType;
  const ExtendedPid(this.code, this.description, this.unit, this.dataType);
}

enum ExtPidType {
  raw,
  bitEncoded,
  percentage,
  temperature,
  torque,
  multiPercentage,
  dualMaf,
  dualTemperature,
  egrData,
  exhaustTemp,
  turboRpm,
  turboTemp,
  nox,
  runTime,
}

/// Common manufacturer-specific enhanced PIDs
/// These are accessed via Mode 22 (Enhanced Diagnostics)
class ManufacturerPids {
  // GM (General Motors) Enhanced PIDs
  static const gmEnhancedPids = <int, String>{
    0x0001: 'Engine Oil Life Remaining',
    0x0002: 'Engine Oil Temperature',
    0x0003: 'Transmission Fluid Temperature',
    0x0004: 'Fuel Level Remaining',
    0x0005: 'Battery State of Charge',
    0x0100: 'Odometer',
    0x0101: 'Trip Odometer',
  };

  // Ford Enhanced PIDs
  static const fordEnhancedPids = <int, String>{
    0x1001: 'Battery Voltage',
    0x1002: 'Alternator Voltage',
    0x1003: 'Oil Pressure',
    0x1004: 'Fuel Rail Pressure',
    0x2001: 'Transmission Temperature',
    0x2002: 'Transmission Gear',
  };

  // Toyota Enhanced PIDs
  static const toyotaEnhancedPids = <int, String>{
    0x0021: 'Hybrid Battery SOC',
    0x0022: 'Hybrid Battery Temperature',
    0x0023: 'Motor Generator 1 Speed',
    0x0024: 'Motor Generator 2 Speed',
  };

  // Volkswagen/Audi (VAG) Enhanced PIDs
  static const vagEnhancedPids = <int, String>{
    0xF40C: 'Engine RPM',
    0xF40D: 'Vehicle Speed',
    0xF405: 'Engine Coolant Temp',
    0xF412: 'Mass Air Flow',
    0xF452: 'Battery Voltage',
  };
}

/// DTC Definitions database
class DTCDatabase {
  static const Map<String, String> genericPowertrain = {
    'P0000': 'No fault',
    'P0001': 'Fuel Volume Regulator Control Circuit/Open',
    'P0002': 'Fuel Volume Regulator Control Circuit Range/Performance',
    'P0003': 'Fuel Volume Regulator Control Circuit Low',
    'P0004': 'Fuel Volume Regulator Control Circuit High',
    'P0010': 'Intake Camshaft Position Actuator Circuit (Bank 1)',
    'P0011': 'Intake Camshaft Position Timing - Over-Advanced (Bank 1)',
    'P0012': 'Intake Camshaft Position Timing - Over-Retarded (Bank 1)',
    'P0013': 'Exhaust Camshaft Position Actuator Circuit (Bank 1)',
    'P0014': 'Exhaust Camshaft Position Timing - Over-Advanced (Bank 1)',
    'P0015': 'Exhaust Camshaft Position Timing - Over-Retarded (Bank 1)',
    'P0016': 'Crankshaft Position - Camshaft Position Correlation (Bank 1 Sensor A)',
    'P0017': 'Crankshaft Position - Camshaft Position Correlation (Bank 1 Sensor B)',
    'P0030': 'HO2S Heater Control Circuit (Bank 1 Sensor 1)',
    'P0031': 'HO2S Heater Control Circuit Low (Bank 1 Sensor 1)',
    'P0032': 'HO2S Heater Control Circuit High (Bank 1 Sensor 1)',
    'P0100': 'Mass or Volume Air Flow Circuit Malfunction',
    'P0101': 'Mass or Volume Air Flow Circuit Range/Performance Problem',
    'P0102': 'Mass or Volume Air Flow Circuit Low Input',
    'P0103': 'Mass or Volume Air Flow Circuit High Input',
    'P0104': 'Mass or Volume Air Flow Circuit Intermittent',
    'P0105': 'Manifold Absolute Pressure/Barometric Pressure Circuit Malfunction',
    'P0106': 'Manifold Absolute Pressure/Barometric Pressure Circuit Range/Performance Problem',
    'P0107': 'Manifold Absolute Pressure/Barometric Pressure Circuit Low Input',
    'P0108': 'Manifold Absolute Pressure/Barometric Pressure Circuit High Input',
    'P0110': 'Intake Air Temperature Circuit Malfunction',
    'P0111': 'Intake Air Temperature Circuit Range/Performance Problem',
    'P0112': 'Intake Air Temperature Circuit Low Input',
    'P0113': 'Intake Air Temperature Circuit High Input',
    'P0115': 'Engine Coolant Temperature Circuit Malfunction',
    'P0116': 'Engine Coolant Temperature Circuit Range/Performance Problem',
    'P0117': 'Engine Coolant Temperature Circuit Low Input',
    'P0118': 'Engine Coolant Temperature Circuit High Input',
    'P0120': 'Throttle Position Sensor/Switch A Circuit Malfunction',
    'P0121': 'Throttle Position Sensor/Switch A Circuit Range/Performance Problem',
    'P0122': 'Throttle Position Sensor/Switch A Circuit Low Input',
    'P0123': 'Throttle Position Sensor/Switch A Circuit High Input',
    'P0125': 'Insufficient Coolant Temperature for Closed Loop Fuel Control',
    'P0130': 'O2 Sensor Circuit Malfunction (Bank 1 Sensor 1)',
    'P0131': 'O2 Sensor Circuit Low Voltage (Bank 1 Sensor 1)',
    'P0132': 'O2 Sensor Circuit High Voltage (Bank 1 Sensor 1)',
    'P0133': 'O2 Sensor Circuit Slow Response (Bank 1 Sensor 1)',
    'P0134': 'O2 Sensor Circuit No Activity Detected (Bank 1 Sensor 1)',
    'P0135': 'O2 Sensor Heater Circuit Malfunction (Bank 1 Sensor 1)',
    'P0136': 'O2 Sensor Circuit Malfunction (Bank 1 Sensor 2)',
    'P0137': 'O2 Sensor Circuit Low Voltage (Bank 1 Sensor 2)',
    'P0138': 'O2 Sensor Circuit High Voltage (Bank 1 Sensor 2)',
    'P0139': 'O2 Sensor Circuit Slow Response (Bank 1 Sensor 2)',
    'P0140': 'O2 Sensor Circuit No Activity Detected (Bank 1 Sensor 2)',
    'P0141': 'O2 Sensor Heater Circuit Malfunction (Bank 1 Sensor 2)',
    'P0171': 'System Too Lean (Bank 1)',
    'P0172': 'System Too Rich (Bank 1)',
    'P0174': 'System Too Lean (Bank 2)',
    'P0175': 'System Too Rich (Bank 2)',
    'P0300': 'Random/Multiple Cylinder Misfire Detected',
    'P0301': 'Cylinder 1 Misfire Detected',
    'P0302': 'Cylinder 2 Misfire Detected',
    'P0303': 'Cylinder 3 Misfire Detected',
    'P0304': 'Cylinder 4 Misfire Detected',
    'P0305': 'Cylinder 5 Misfire Detected',
    'P0306': 'Cylinder 6 Misfire Detected',
    'P0307': 'Cylinder 7 Misfire Detected',
    'P0308': 'Cylinder 8 Misfire Detected',
    'P0325': 'Knock Sensor 1 Circuit Malfunction (Bank 1 or Single Sensor)',
    'P0335': 'Crankshaft Position Sensor A Circuit Malfunction',
    'P0340': 'Camshaft Position Sensor Circuit Malfunction',
    'P0400': 'Exhaust Gas Recirculation Flow Malfunction',
    'P0401': 'Exhaust Gas Recirculation Flow Insufficient Detected',
    'P0402': 'Exhaust Gas Recirculation Flow Excessive Detected',
    'P0420': 'Catalyst System Efficiency Below Threshold (Bank 1)',
    'P0430': 'Catalyst System Efficiency Below Threshold (Bank 2)',
    'P0440': 'Evaporative Emission Control System Malfunction',
    'P0441': 'Evaporative Emission Control System Incorrect Purge Flow',
    'P0442': 'Evaporative Emission Control System Leak Detected (small leak)',
    'P0443': 'Evaporative Emission Control System Purge Control Valve Circuit Malfunction',
    'P0446': 'Evaporative Emission Control System Vent Control Circuit Malfunction',
    'P0450': 'Evaporative Emission Control System Pressure Sensor Malfunction',
    'P0455': 'Evaporative Emission Control System Leak Detected (large leak)',
    'P0500': 'Vehicle Speed Sensor Malfunction',
    'P0505': 'Idle Control System Malfunction',
    'P0506': 'Idle Control System RPM Lower Than Expected',
    'P0507': 'Idle Control System RPM Higher Than Expected',
    'P0600': 'Serial Communication Link Malfunction',
    'P0700': 'Transmission Control System Malfunction',
    'P0715': 'Input/Turbine Speed Sensor Circuit Malfunction',
    'P0720': 'Output Speed Sensor Circuit Malfunction',
    'P0730': 'Incorrect Gear Ratio',
    'P0740': 'Torque Converter Clutch Circuit Malfunction',
    'P0750': 'Shift Solenoid A Malfunction',
    'P0755': 'Shift Solenoid B Malfunction',
    'P0760': 'Shift Solenoid C Malfunction',
    'P0765': 'Shift Solenoid D Malfunction',
  };

  static String? getDescription(String code) {
    return genericPowertrain[code.toUpperCase()];
  }
}

/// CAN Bus Protocol Identifiers
class CANProtocols {
  static const int iso15765_11bit_500k = 6;
  static const int iso15765_29bit_500k = 7;
  static const int iso15765_11bit_250k = 8;
  static const int iso15765_29bit_250k = 9;

  static const Map<int, String> protocolNames = {
    1: 'SAE J1850 PWM',
    2: 'SAE J1850 VPW',
    3: 'ISO 9141-2',
    4: 'ISO 14230-4 KWP (5 baud init)',
    5: 'ISO 14230-4 KWP (fast init)',
    6: 'ISO 15765-4 CAN (11 bit ID, 500 kbaud)',
    7: 'ISO 15765-4 CAN (29 bit ID, 500 kbaud)',
    8: 'ISO 15765-4 CAN (11 bit ID, 250 kbaud)',
    9: 'ISO 15765-4 CAN (29 bit ID, 250 kbaud)',
    10: 'SAE J1939 CAN (29 bit ID, 250 kbaud)',
    11: 'User1 CAN (11 bit ID, 125 kbaud)',
    12: 'User2 CAN (11 bit ID, 50 kbaud)',
  };
}

/// Unit conversion utilities
class UnitConverter {
  static double celsiusToFahrenheit(double celsius) => (celsius * 9 / 5) + 32;
  static double fahrenheitToCelsius(double fahrenheit) => (fahrenheit - 32) * 5 / 9;
  static double kphToMph(double kph) => kph * 0.621371;
  static double mphToKph(double mph) => mph / 0.621371;
  static double kpaToBar(double kpa) => kpa / 100;
  static double kpaToPsi(double kpa) => kpa * 0.145038;
  static double litersToGallons(double liters) => liters * 0.264172;
  static double gallonsToLiters(double gallons) => gallons / 0.264172;
  static double kmToMiles(double km) => km * 0.621371;
  static double milesToKm(double miles) => miles / 0.621371;
  static double gramsPerSecToLbsPerMin(double gps) => gps * 0.132277;
}
