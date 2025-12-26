import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/vehicle_data.dart';
import '../obd/obd_protocol.dart';

/// Service for recording and persisting diagnostic sessions and live data
class RecordingService {
  static final RecordingService _instance = RecordingService._internal();
  factory RecordingService() => _instance;
  RecordingService._internal();

  Database? _database;
  bool _isRecording = false;
  String? _currentSessionId;
  final List<RecordedDataPoint> _buffer = [];
  Timer? _flushTimer;

  static const int _bufferSize = 50;
  static const Duration _flushInterval = Duration(seconds: 5);

  bool get isRecording => _isRecording;
  String? get currentSessionId => _currentSessionId;

  /// Initialize the database
  Future<void> initialize() async {
    if (_database != null) return;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'opendiag.db');

    _database = await openDatabase(
      path,
      version: 2,
      onCreate: _createTables,
      onUpgrade: _upgradeTables,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Vehicle profiles table
    await db.execute('''
      CREATE TABLE vehicles (
        id TEXT PRIMARY KEY,
        vin TEXT UNIQUE,
        nickname TEXT,
        make TEXT,
        model TEXT,
        year INTEGER,
        engine TEXT,
        transmission TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Diagnostic sessions table
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        vehicle_id TEXT,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        mileage INTEGER,
        notes TEXT,
        FOREIGN KEY (vehicle_id) REFERENCES vehicles(id)
      )
    ''');

    // DTC records table
    await db.execute('''
      CREATE TABLE dtc_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        code TEXT NOT NULL,
        raw_value INTEGER,
        timestamp INTEGER NOT NULL,
        is_pending INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');

    // Live data recordings table
    await db.execute('''
      CREATE TABLE data_recordings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        pid_code INTEGER NOT NULL,
        pid_name TEXT NOT NULL,
        value REAL,
        raw_value TEXT,
        unit TEXT,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');

    // Freeze frame records table
    await db.execute('''
      CREATE TABLE freeze_frames (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        dtc_code TEXT NOT NULL,
        data TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');

    // Create indexes for performance
    await db.execute('CREATE INDEX idx_sessions_vehicle ON sessions(vehicle_id)');
    await db.execute('CREATE INDEX idx_dtc_session ON dtc_records(session_id)');
    await db.execute('CREATE INDEX idx_data_session ON data_recordings(session_id)');
    await db.execute('CREATE INDEX idx_data_timestamp ON data_recordings(timestamp)');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add any migration logic here
    }
  }

  /// Start a new recording session
  Future<String> startSession({String? vehicleId, int? mileage, String? notes}) async {
    await initialize();

    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentSessionId = sessionId;
    _isRecording = true;

    await _database!.insert('sessions', {
      'id': sessionId,
      'vehicle_id': vehicleId,
      'start_time': DateTime.now().millisecondsSinceEpoch,
      'mileage': mileage,
      'notes': notes,
    });

    // Start periodic flush timer
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flushBuffer());

    return sessionId;
  }

  /// Stop the current recording session
  Future<void> stopSession() async {
    if (!_isRecording || _currentSessionId == null) return;

    _flushTimer?.cancel();
    await _flushBuffer();

    await _database!.update(
      'sessions',
      {'end_time': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [_currentSessionId],
    );

    _isRecording = false;
    _currentSessionId = null;
  }

  /// Record a live data reading
  void recordReading(LiveDataReading reading) {
    if (!_isRecording || _currentSessionId == null) return;

    _buffer.add(RecordedDataPoint(
      sessionId: _currentSessionId!,
      pidCode: reading.pid.code,
      pidName: reading.pid.description,
      value: reading.value is num ? (reading.value as num).toDouble() : null,
      rawValue: reading.value?.toString(),
      unit: reading.unit,
      timestamp: reading.timestamp,
    ));

    if (_buffer.length >= _bufferSize) {
      _flushBuffer();
    }
  }

  /// Record a PID reading from DiagnosticService
  void recordPidReading(PidReading reading) {
    if (!_isRecording || _currentSessionId == null) return;

    _buffer.add(RecordedDataPoint(
      sessionId: _currentSessionId!,
      pidCode: reading.pid.code,
      pidName: reading.pid.description,
      value: reading.parsedValue is num ? (reading.parsedValue as num).toDouble() : null,
      rawValue: reading.parsedValue?.toString(),
      unit: reading.pid.unit,
      timestamp: reading.timestamp,
    ));

    if (_buffer.length >= _bufferSize) {
      _flushBuffer();
    }
  }

  /// Record DTCs
  Future<void> recordDTCs(List<DTC> dtcs, {bool isPending = false}) async {
    if (!_isRecording || _currentSessionId == null) return;
    await initialize();

    final batch = _database!.batch();
    for (final dtc in dtcs) {
      batch.insert('dtc_records', {
        'session_id': _currentSessionId,
        'code': dtc.code,
        'raw_value': dtc.rawValue,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'is_pending': isPending ? 1 : 0,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Record freeze frame data
  Future<void> recordFreezeFrame(FreezeFrame freezeFrame) async {
    if (!_isRecording || _currentSessionId == null) return;
    await initialize();

    final dataJson = freezeFrame.readings.entries
        .map((e) => '${e.key.code}:${e.value}')
        .join(';');

    await _database!.insert('freeze_frames', {
      'session_id': _currentSessionId,
      'dtc_code': freezeFrame.dtc.code,
      'data': dataJson,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> _flushBuffer() async {
    if (_buffer.isEmpty) return;
    await initialize();

    final batch = _database!.batch();
    for (final point in _buffer) {
      batch.insert('data_recordings', {
        'session_id': point.sessionId,
        'pid_code': point.pidCode,
        'pid_name': point.pidName,
        'value': point.value,
        'raw_value': point.rawValue,
        'unit': point.unit,
        'timestamp': point.timestamp.millisecondsSinceEpoch,
      });
    }
    await batch.commit(noResult: true);
    _buffer.clear();
  }

  /// Get all sessions for a vehicle
  Future<List<SessionSummary>> getSessionsForVehicle(String vehicleId) async {
    await initialize();

    final results = await _database!.query(
      'sessions',
      where: 'vehicle_id = ?',
      whereArgs: [vehicleId],
      orderBy: 'start_time DESC',
    );

    return results.map((row) => SessionSummary.fromMap(row)).toList();
  }

  /// Get all sessions
  Future<List<SessionSummary>> getAllSessions() async {
    await initialize();

    final results = await _database!.query(
      'sessions',
      orderBy: 'start_time DESC',
    );

    return results.map((row) => SessionSummary.fromMap(row)).toList();
  }

  /// Get session details with all recorded data
  Future<SessionDetails?> getSessionDetails(String sessionId) async {
    await initialize();

    final sessionRows = await _database!.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );

    if (sessionRows.isEmpty) return null;

    final session = SessionSummary.fromMap(sessionRows.first);

    // Get DTCs
    final dtcRows = await _database!.query(
      'dtc_records',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );

    // Get data recordings
    final dataRows = await _database!.query(
      'data_recordings',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );

    return SessionDetails(
      session: session,
      dtcs: dtcRows.map((r) => RecordedDTC.fromMap(r)).toList(),
      dataPoints: dataRows.map((r) => RecordedDataPoint.fromMap(r)).toList(),
    );
  }

  /// Delete a session and all its data
  Future<void> deleteSession(String sessionId) async {
    await initialize();

    await _database!.delete('data_recordings', where: 'session_id = ?', whereArgs: [sessionId]);
    await _database!.delete('dtc_records', where: 'session_id = ?', whereArgs: [sessionId]);
    await _database!.delete('freeze_frames', where: 'session_id = ?', whereArgs: [sessionId]);
    await _database!.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  /// Export session data as CSV
  Future<String> exportSessionToCsv(String sessionId) async {
    final details = await getSessionDetails(sessionId);
    if (details == null) throw Exception('Session not found');

    final buffer = StringBuffer();

    // Header
    buffer.writeln('OpenDiag Session Export');
    buffer.writeln('Session ID,$sessionId');
    buffer.writeln('Start Time,${details.session.startTime.toIso8601String()}');
    if (details.session.endTime != null) {
      buffer.writeln('End Time,${details.session.endTime!.toIso8601String()}');
    }
    buffer.writeln();

    // DTCs
    if (details.dtcs.isNotEmpty) {
      buffer.writeln('Diagnostic Trouble Codes');
      buffer.writeln('Code,Type,Timestamp');
      for (final dtc in details.dtcs) {
        buffer.writeln('${dtc.code},${dtc.isPending ? "Pending" : "Stored"},${dtc.timestamp.toIso8601String()}');
      }
      buffer.writeln();
    }

    // Live Data
    if (details.dataPoints.isNotEmpty) {
      buffer.writeln('Live Data Recordings');
      buffer.writeln('Timestamp,PID,Name,Value,Unit');
      for (final point in details.dataPoints) {
        buffer.writeln('${point.timestamp.toIso8601String()},0x${point.pidCode.toRadixString(16)},${point.pidName},${point.value ?? point.rawValue},${point.unit}');
      }
    }

    return buffer.toString();
  }

  void dispose() {
    _flushTimer?.cancel();
    _database?.close();
  }
}

/// Summary of a recording session
class SessionSummary {
  final String id;
  final String? vehicleId;
  final DateTime startTime;
  final DateTime? endTime;
  final int? mileage;
  final String? notes;

  SessionSummary({
    required this.id,
    this.vehicleId,
    required this.startTime,
    this.endTime,
    this.mileage,
    this.notes,
  });

  factory SessionSummary.fromMap(Map<String, dynamic> map) {
    return SessionSummary(
      id: map['id'] as String,
      vehicleId: map['vehicle_id'] as String?,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: map['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int)
          : null,
      mileage: map['mileage'] as int?,
      notes: map['notes'] as String?,
    );
  }

  Duration? get duration {
    if (endTime == null) return null;
    return endTime!.difference(startTime);
  }
}

/// Full session details with all data
class SessionDetails {
  final SessionSummary session;
  final List<RecordedDTC> dtcs;
  final List<RecordedDataPoint> dataPoints;

  SessionDetails({
    required this.session,
    required this.dtcs,
    required this.dataPoints,
  });
}

/// Recorded DTC entry
class RecordedDTC {
  final String code;
  final int? rawValue;
  final DateTime timestamp;
  final bool isPending;

  RecordedDTC({
    required this.code,
    this.rawValue,
    required this.timestamp,
    required this.isPending,
  });

  factory RecordedDTC.fromMap(Map<String, dynamic> map) {
    return RecordedDTC(
      code: map['code'] as String,
      rawValue: map['raw_value'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      isPending: (map['is_pending'] as int) == 1,
    );
  }
}

/// Recorded live data point
class RecordedDataPoint {
  final String sessionId;
  final int pidCode;
  final String pidName;
  final double? value;
  final String? rawValue;
  final String? unit;
  final DateTime timestamp;

  RecordedDataPoint({
    required this.sessionId,
    required this.pidCode,
    required this.pidName,
    this.value,
    this.rawValue,
    this.unit,
    required this.timestamp,
  });

  factory RecordedDataPoint.fromMap(Map<String, dynamic> map) {
    return RecordedDataPoint(
      sessionId: map['session_id'] as String,
      pidCode: map['pid_code'] as int,
      pidName: map['pid_name'] as String,
      value: map['value'] as double?,
      rawValue: map['raw_value'] as String?,
      unit: map['unit'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }
}
