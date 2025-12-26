import '../obd/obd_protocol.dart';

/// A reading from a specific PID
class PidReading {
  final OBDPid pid;
  final List<int> rawValue;
  final dynamic parsedValue;
  final DateTime timestamp;

  PidReading({
    required this.pid,
    required this.rawValue,
    required this.parsedValue,
    required this.timestamp,
  });

  String get formattedValue {
    if (parsedValue == null) return 'N/A';

    if (parsedValue is double) {
      return '${parsedValue.toStringAsFixed(1)} ${pid.unit}';
    } else if (parsedValue is int) {
      return '$parsedValue ${pid.unit}'.trim();
    }

    return parsedValue.toString();
  }
}

/// Live data stream reading
class LiveDataReading {
  final OBDPid pid;
  final dynamic value;
  final String unit;
  final DateTime timestamp;

  LiveDataReading({
    required this.pid,
    required this.value,
    required this.unit,
    required this.timestamp,
  });

  String get formattedValue {
    if (value == null) return 'N/A';

    if (value is double) {
      return '${value.toStringAsFixed(1)} $unit'.trim();
    } else if (value is int) {
      return '$value $unit'.trim();
    }

    return value.toString();
  }
}

/// Readiness monitors status
class ReadinessMonitors {
  final bool milOn;
  final int dtcCount;
  final Map<String, MonitorStatus> monitors;

  ReadinessMonitors({
    required this.milOn,
    required this.dtcCount,
    required this.monitors,
  });

  factory ReadinessMonitors.fromBytes(List<int> data) {
    if (data.length < 4) {
      return ReadinessMonitors(
        milOn: false,
        dtcCount: 0,
        monitors: {},
      );
    }

    final byte1 = data[0];
    final byte2 = data[1];
    final byte3 = data[2];
    final byte4 = data[3];

    final milOn = (byte1 & 0x80) != 0;
    final dtcCount = byte1 & 0x7F;

    final monitors = <String, MonitorStatus>{};

    // Byte 2 - Misfire and fuel system monitors
    monitors['Misfire'] = MonitorStatus(
      supported: (byte2 & 0x01) != 0,
      complete: (byte2 & 0x10) == 0,
    );
    monitors['Fuel System'] = MonitorStatus(
      supported: (byte2 & 0x02) != 0,
      complete: (byte2 & 0x20) == 0,
    );
    monitors['Components'] = MonitorStatus(
      supported: (byte2 & 0x04) != 0,
      complete: (byte2 & 0x40) == 0,
    );

    // Check if spark ignition (gasoline) or compression ignition (diesel)
    final isSparkIgnition = (byte2 & 0x08) == 0;

    if (isSparkIgnition) {
      // Spark ignition monitors (byte 3 and 4)
      monitors['Catalyst'] = MonitorStatus(
        supported: (byte3 & 0x01) != 0,
        complete: (byte4 & 0x01) == 0,
      );
      monitors['Heated Catalyst'] = MonitorStatus(
        supported: (byte3 & 0x02) != 0,
        complete: (byte4 & 0x02) == 0,
      );
      monitors['Evaporative System'] = MonitorStatus(
        supported: (byte3 & 0x04) != 0,
        complete: (byte4 & 0x04) == 0,
      );
      monitors['Secondary Air System'] = MonitorStatus(
        supported: (byte3 & 0x08) != 0,
        complete: (byte4 & 0x08) == 0,
      );
      monitors['A/C Refrigerant'] = MonitorStatus(
        supported: (byte3 & 0x10) != 0,
        complete: (byte4 & 0x10) == 0,
      );
      monitors['Oxygen Sensor'] = MonitorStatus(
        supported: (byte3 & 0x20) != 0,
        complete: (byte4 & 0x20) == 0,
      );
      monitors['Oxygen Sensor Heater'] = MonitorStatus(
        supported: (byte3 & 0x40) != 0,
        complete: (byte4 & 0x40) == 0,
      );
      monitors['EGR System'] = MonitorStatus(
        supported: (byte3 & 0x80) != 0,
        complete: (byte4 & 0x80) == 0,
      );
    } else {
      // Compression ignition monitors (diesel)
      monitors['NMHC Catalyst'] = MonitorStatus(
        supported: (byte3 & 0x01) != 0,
        complete: (byte4 & 0x01) == 0,
      );
      monitors['NOx/SCR Monitor'] = MonitorStatus(
        supported: (byte3 & 0x02) != 0,
        complete: (byte4 & 0x02) == 0,
      );
      monitors['Boost Pressure'] = MonitorStatus(
        supported: (byte3 & 0x08) != 0,
        complete: (byte4 & 0x08) == 0,
      );
      monitors['Exhaust Gas Sensor'] = MonitorStatus(
        supported: (byte3 & 0x20) != 0,
        complete: (byte4 & 0x20) == 0,
      );
      monitors['PM Filter'] = MonitorStatus(
        supported: (byte3 & 0x40) != 0,
        complete: (byte4 & 0x40) == 0,
      );
      monitors['EGR/VVT System'] = MonitorStatus(
        supported: (byte3 & 0x80) != 0,
        complete: (byte4 & 0x80) == 0,
      );
    }

    return ReadinessMonitors(
      milOn: milOn,
      dtcCount: dtcCount,
      monitors: monitors,
    );
  }

  int get completedCount => monitors.values.where((m) => m.supported && m.complete).length;
  int get incompleteCount => monitors.values.where((m) => m.supported && !m.complete).length;
  int get supportedCount => monitors.values.where((m) => m.supported).length;

  bool get allComplete => incompleteCount == 0;
}

class MonitorStatus {
  final bool supported;
  final bool complete;

  MonitorStatus({
    required this.supported,
    required this.complete,
  });

  String get statusText {
    if (!supported) return 'N/A';
    return complete ? 'Complete' : 'Incomplete';
  }
}

/// Freeze frame data captured when DTC was set
class FreezeFrame {
  final DTC dtc;
  final Map<OBDPid, dynamic> readings;
  final DateTime timestamp;

  FreezeFrame({
    required this.dtc,
    required this.readings,
    required this.timestamp,
  });
}

/// Vehicle information summary
class VehicleInfo {
  final String? vin;
  final String? make;
  final String? model;
  final String? year;
  final String? ecuName;
  final String? calibrationId;

  VehicleInfo({
    this.vin,
    this.make,
    this.model,
    this.year,
    this.ecuName,
    this.calibrationId,
  });

  factory VehicleInfo.fromVIN(String vin) {
    final decoder = VINDecoder(vin);

    return VehicleInfo(
      vin: vin,
      year: decoder.modelYear,
      // Make and model would need a VIN database lookup
    );
  }
}

/// Diagnostic session summary
class DiagnosticSession {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final VehicleInfo? vehicleInfo;
  final List<DTC> dtcs;
  final List<PidReading> readings;
  final ReadinessMonitors? monitors;

  DiagnosticSession({
    required this.id,
    required this.startTime,
    this.endTime,
    this.vehicleInfo,
    this.dtcs = const [],
    this.readings = const [],
    this.monitors,
  });

  Duration? get duration {
    if (endTime == null) return null;
    return endTime!.difference(startTime);
  }
}
