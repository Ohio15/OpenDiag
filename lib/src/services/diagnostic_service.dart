import 'dart:async';
import '../platform/platform.dart';
import '../obd/obd_protocol.dart';
import '../models/vehicle_data.dart';

/// Main diagnostic service coordinating VCI communication and OBD protocols
class DiagnosticService {
  final VciInterface _vciConnection;

  VciDeviceInfo? _connectedDevice;
  Set<int> _supportedPids = {};
  String? _vin;

  final _liveDataController = StreamController<LiveDataReading>.broadcast();
  final _dtcController = StreamController<List<DTC>>.broadcast();

  Stream<LiveDataReading> get liveDataStream => _liveDataController.stream;
  Stream<List<DTC>> get dtcStream => _dtcController.stream;

  bool _isMonitoring = false;
  Timer? _monitoringTimer;
  List<OBDPid> _monitoredPids = [];

  DiagnosticService(this._vciConnection);

  VciInterface get connection => _vciConnection;
  bool get isConnected => _vciConnection.isConnected;
  String? get vin => _vin;
  Set<int> get supportedPids => _supportedPids;

  /// Initialize connection and query supported PIDs
  Future<void> initialize() async {
    if (!isConnected) {
      throw DiagnosticException('Not connected to VCI');
    }

    // Initialize ELM327 compatible adapter
    if (_connectedDevice?.type == VciDeviceType.elm327 ||
        _connectedDevice?.type == VciDeviceType.serialPort) {
      await _initializeELM327();
    }

    // Query supported PIDs
    await _querySupportedPids();

    // Read VIN if supported
    if (_supportedPids.contains(0x02)) {
      await _readVIN();
    }
  }

  Future<void> _initializeELM327() async {
    // Reset adapter
    await _vciConnection.sendATCommand('ATZ');
    await Future.delayed(const Duration(milliseconds: 500));

    // Disable echo
    await _vciConnection.sendATCommand('ATE0');

    // Disable line feed
    await _vciConnection.sendATCommand('ATL0');

    // Disable spaces
    await _vciConnection.sendATCommand('ATS0');

    // Set protocol to auto
    await _vciConnection.sendATCommand('ATSP0');

    // Set timeout
    await _vciConnection.sendATCommand('ATSTFF');
  }

  Future<void> _querySupportedPids() async {
    _supportedPids.clear();

    // Query PIDs 00, 20, 40, 60 for supported PIDs
    final pidRanges = [0x00, 0x20, 0x40, 0x60];

    for (final rangePid in pidRanges) {
      try {
        final response = await _sendOBDCommand(OBDMode.currentData, rangePid);
        if (response != null && response.length >= 4) {
          final supportedBits = OBDCommand.parseResponse(
            OBDPid.supportedPids00,
            response,
          ) as List<bool>;

          for (var i = 0; i < supportedBits.length && i < 32; i++) {
            if (supportedBits[i]) {
              _supportedPids.add(rangePid + i + 1);
            }
          }
        }
      } catch (e) {
        // Stop querying if we get errors
        break;
      }
    }
  }

  Future<void> _readVIN() async {
    try {
      final response = await _sendOBDCommand(OBDMode.vehicleInfo, 0x02);
      if (response != null && response.length >= 17) {
        _vin = String.fromCharCodes(response.take(17));
      }
    } catch (e) {
      // VIN read failed, continue without it
    }
  }

  /// Read a specific PID value
  Future<PidReading?> readPid(OBDPid pid) async {
    if (!isConnected) return null;

    try {
      final response = await _sendOBDCommand(OBDMode.currentData, pid.code);
      if (response == null || response.isEmpty) return null;

      final value = OBDCommand.parseResponse(pid, response);

      return PidReading(
        pid: pid,
        rawValue: response,
        parsedValue: value,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Read multiple PIDs efficiently
  Future<List<PidReading>> readPids(List<OBDPid> pids) async {
    final readings = <PidReading>[];

    for (final pid in pids) {
      final reading = await readPid(pid);
      if (reading != null) {
        readings.add(reading);
      }
    }

    return readings;
  }

  /// Start live data monitoring
  void startMonitoring(List<OBDPid> pids, {Duration interval = const Duration(milliseconds: 500)}) {
    if (_isMonitoring) {
      stopMonitoring();
    }

    _monitoredPids = pids;
    _isMonitoring = true;

    _monitoringTimer = Timer.periodic(interval, (_) async {
      if (!_isMonitoring || !isConnected) {
        stopMonitoring();
        return;
      }

      for (final pid in _monitoredPids) {
        final reading = await readPid(pid);
        if (reading != null) {
          _liveDataController.add(LiveDataReading(
            pid: pid,
            value: reading.parsedValue,
            unit: pid.unit,
            timestamp: reading.timestamp,
          ));
        }
      }
    });
  }

  /// Stop live data monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _monitoredPids.clear();
  }

  /// Read stored DTCs
  Future<List<DTC>> readStoredDTCs() async {
    if (!isConnected) return [];

    try {
      final response = await _sendOBDCommand(OBDMode.storedDTCs, 0x00);
      if (response == null || response.isEmpty) return [];

      return _parseDTCs(response);
    } catch (e) {
      return [];
    }
  }

  /// Read pending DTCs
  Future<List<DTC>> readPendingDTCs() async {
    if (!isConnected) return [];

    try {
      final response = await _sendOBDCommand(OBDMode.pendingDTCs, 0x00);
      if (response == null || response.isEmpty) return [];

      return _parseDTCs(response);
    } catch (e) {
      return [];
    }
  }

  List<DTC> _parseDTCs(List<int> data) {
    final dtcs = <DTC>[];

    // DTCs come in pairs of bytes
    for (var i = 0; i < data.length - 1; i += 2) {
      final byte1 = data[i];
      final byte2 = data[i + 1];

      // Skip if both bytes are 0 (no DTC)
      if (byte1 == 0 && byte2 == 0) continue;

      dtcs.add(DTC.fromBytes(byte1, byte2));
    }

    return dtcs;
  }

  /// Clear DTCs and reset monitors
  Future<bool> clearDTCs() async {
    if (!isConnected) return false;

    try {
      await _sendOBDCommand(OBDMode.clearDTCs, 0x00);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Read readiness monitors status
  Future<ReadinessMonitors?> readReadinessMonitors() async {
    if (!isConnected) return null;

    try {
      final response = await _sendOBDCommand(OBDMode.currentData, 0x01);
      if (response == null || response.length < 4) return null;

      return ReadinessMonitors.fromBytes(response);
    } catch (e) {
      return null;
    }
  }

  /// Read freeze frame data
  Future<FreezeFrame?> readFreezeFrame() async {
    if (!isConnected) return null;

    try {
      // First read the freeze frame DTC
      final dtcResponse = await _sendOBDCommand(OBDMode.freezeFrame, 0x02);
      if (dtcResponse == null || dtcResponse.length < 2) return null;

      final dtc = DTC.fromBytes(dtcResponse[0], dtcResponse[1]);

      // Read freeze frame PIDs
      final readings = <OBDPid, dynamic>{};

      final freezeFramePids = [
        OBDPid.engineLoad,
        OBDPid.coolantTemp,
        OBDPid.engineRpm,
        OBDPid.vehicleSpeed,
      ];

      for (final pid in freezeFramePids) {
        try {
          final response = await _sendOBDCommand(OBDMode.freezeFrame, pid.code);
          if (response != null && response.isNotEmpty) {
            readings[pid] = OBDCommand.parseResponse(pid, response);
          }
        } catch (e) {
          // Skip if freeze frame data not available for this PID
        }
      }

      return FreezeFrame(
        dtc: dtc,
        readings: readings,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  Future<List<int>?> _sendOBDCommand(OBDMode mode, int pid) async {
    if (_connectedDevice?.type == VciDeviceType.autelVci) {
      return _sendAutelCommand(mode, pid);
    } else {
      // ELM327 and serial port devices use AT commands
      return _sendELM327Command(mode, pid);
    }
  }

  Future<List<int>?> _sendELM327Command(OBDMode mode, int pid) async {
    final command = OBDCommand(mode: mode, pid: pid);
    final response = await _vciConnection.sendATCommand(command.toATCommand());

    // Parse hex response
    return _parseHexResponse(response);
  }

  Future<List<int>?> _sendAutelCommand(OBDMode mode, int pid) async {
    final command = OBDCommand(mode: mode, pid: pid);
    final response = await _vciConnection.sendCommand(command.toBytes());

    // Skip header bytes for Autel response
    if (response.length > 2) {
      return response.sublist(2);
    }
    return response;
  }

  List<int>? _parseHexResponse(String response) {
    // Remove whitespace and common artifacts
    final cleaned = response
        .replaceAll(RegExp(r'[^0-9A-Fa-f]'), '')
        .toUpperCase();

    if (cleaned.isEmpty || cleaned.length < 4) return null;

    // Skip mode and PID bytes (first 4 chars = 2 bytes)
    final dataHex = cleaned.substring(4);

    final bytes = <int>[];
    for (var i = 0; i < dataHex.length - 1; i += 2) {
      bytes.add(int.parse(dataHex.substring(i, i + 2), radix: 16));
    }

    return bytes;
  }

  void setConnectedDevice(VciDeviceInfo device) {
    _connectedDevice = device;
  }

  void dispose() {
    stopMonitoring();
    _liveDataController.close();
    _dtcController.close();
  }
}

class DiagnosticException implements Exception {
  final String message;
  DiagnosticException(this.message);

  @override
  String toString() => 'DiagnosticException: $message';
}
