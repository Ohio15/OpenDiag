import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'recording_service.dart';

/// Service for managing vehicle profiles and history
class VehicleProfileService {
  static final VehicleProfileService _instance = VehicleProfileService._internal();
  factory VehicleProfileService() => _instance;
  VehicleProfileService._internal();

  Database? _database;

  /// Initialize the database
  Future<void> initialize() async {
    if (_database != null) return;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'opendiag.db');

    _database = await openDatabase(
      path,
      version: 2,
      onCreate: _createTables,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Tables are created by RecordingService, this is a fallback
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vehicles (
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
  }

  /// Create a new vehicle profile
  Future<VehicleProfile> createVehicle({
    required String id,
    String? vin,
    String? nickname,
    String? make,
    String? model,
    int? year,
    String? engine,
    String? transmission,
    String? notes,
  }) async {
    await initialize();

    final now = DateTime.now().millisecondsSinceEpoch;

    await _database!.insert('vehicles', {
      'id': id,
      'vin': vin,
      'nickname': nickname,
      'make': make,
      'model': model,
      'year': year,
      'engine': engine,
      'transmission': transmission,
      'notes': notes,
      'created_at': now,
      'updated_at': now,
    });

    return VehicleProfile(
      id: id,
      vin: vin,
      nickname: nickname,
      make: make,
      model: model,
      year: year,
      engine: engine,
      transmission: transmission,
      notes: notes,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  /// Update an existing vehicle profile
  Future<void> updateVehicle(VehicleProfile vehicle) async {
    await initialize();

    await _database!.update(
      'vehicles',
      {
        'vin': vehicle.vin,
        'nickname': vehicle.nickname,
        'make': vehicle.make,
        'model': vehicle.model,
        'year': vehicle.year,
        'engine': vehicle.engine,
        'transmission': vehicle.transmission,
        'notes': vehicle.notes,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [vehicle.id],
    );
  }

  /// Delete a vehicle profile
  Future<void> deleteVehicle(String vehicleId) async {
    await initialize();

    // First delete all associated sessions
    final recordingService = RecordingService();
    final sessions = await recordingService.getSessionsForVehicle(vehicleId);
    for (final session in sessions) {
      await recordingService.deleteSession(session.id);
    }

    // Then delete the vehicle
    await _database!.delete('vehicles', where: 'id = ?', whereArgs: [vehicleId]);
  }

  /// Get all vehicle profiles
  Future<List<VehicleProfile>> getAllVehicles() async {
    await initialize();

    final results = await _database!.query(
      'vehicles',
      orderBy: 'updated_at DESC',
    );

    return results.map((row) => VehicleProfile.fromMap(row)).toList();
  }

  /// Get a vehicle by ID
  Future<VehicleProfile?> getVehicle(String id) async {
    await initialize();

    final results = await _database!.query(
      'vehicles',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isEmpty) return null;
    return VehicleProfile.fromMap(results.first);
  }

  /// Get a vehicle by VIN
  Future<VehicleProfile?> getVehicleByVIN(String vin) async {
    await initialize();

    final results = await _database!.query(
      'vehicles',
      where: 'vin = ?',
      whereArgs: [vin],
    );

    if (results.isEmpty) return null;
    return VehicleProfile.fromMap(results.first);
  }

  /// Get vehicle history (all sessions for a vehicle)
  Future<VehicleHistory> getVehicleHistory(String vehicleId) async {
    await initialize();

    final vehicle = await getVehicle(vehicleId);
    if (vehicle == null) throw Exception('Vehicle not found');

    final recordingService = RecordingService();
    final sessions = await recordingService.getSessionsForVehicle(vehicleId);

    // Calculate statistics
    int totalDtcs = 0;
    int totalDataPoints = 0;
    Duration totalSessionTime = Duration.zero;

    for (final session in sessions) {
      if (session.duration != null) {
        totalSessionTime += session.duration!;
      }

      final details = await recordingService.getSessionDetails(session.id);
      if (details != null) {
        totalDtcs += details.dtcs.length;
        totalDataPoints += details.dataPoints.length;
      }
    }

    return VehicleHistory(
      vehicle: vehicle,
      sessions: sessions,
      totalSessions: sessions.length,
      totalDtcs: totalDtcs,
      totalDataPoints: totalDataPoints,
      totalSessionTime: totalSessionTime,
    );
  }

  /// Find or create vehicle by VIN
  Future<VehicleProfile> findOrCreateByVIN(String vin, {String? nickname}) async {
    var vehicle = await getVehicleByVIN(vin);
    if (vehicle != null) return vehicle;

    final decoded = _decodeVIN(vin);

    return createVehicle(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      vin: vin,
      nickname: nickname,
      year: decoded['year'],
      make: decoded['make'],
    );
  }

  /// Decode VIN to extract basic information
  Map<String, dynamic> _decodeVIN(String vin) {
    if (vin.length != 17) return {};

    final result = <String, dynamic>{};

    // Model year (10th character)
    final yearChar = vin[9].toUpperCase();
    result['year'] = _decodeModelYear(yearChar);

    // Manufacturer (first 3 characters - WMI)
    final wmi = vin.substring(0, 3).toUpperCase();
    result['make'] = _decodeMake(wmi);

    return result;
  }

  int? _decodeModelYear(String char) {
    const yearCodes = {
      'A': 2010, 'B': 2011, 'C': 2012, 'D': 2013, 'E': 2014,
      'F': 2015, 'G': 2016, 'H': 2017, 'J': 2018, 'K': 2019,
      'L': 2020, 'M': 2021, 'N': 2022, 'P': 2023, 'R': 2024,
      'S': 2025, 'T': 2026, 'V': 2027, 'W': 2028, 'X': 2029,
      'Y': 2030, '1': 2001, '2': 2002, '3': 2003, '4': 2004,
      '5': 2005, '6': 2006, '7': 2007, '8': 2008, '9': 2009,
    };
    return yearCodes[char];
  }

  String? _decodeMake(String wmi) {
    // Common WMI codes
    if (wmi.startsWith('1G')) return 'General Motors';
    if (wmi.startsWith('1F')) return 'Ford';
    if (wmi.startsWith('1C')) return 'Chrysler';
    if (wmi.startsWith('1H')) return 'Honda';
    if (wmi.startsWith('1N')) return 'Nissan';
    if (wmi.startsWith('2G')) return 'General Motors Canada';
    if (wmi.startsWith('2T')) return 'Toyota Canada';
    if (wmi.startsWith('3G')) return 'General Motors Mexico';
    if (wmi.startsWith('3F')) return 'Ford Mexico';
    if (wmi.startsWith('4T')) return 'Toyota USA';
    if (wmi.startsWith('5F')) return 'Honda USA';
    if (wmi.startsWith('5T')) return 'Toyota USA';
    if (wmi.startsWith('JT')) return 'Toyota';
    if (wmi.startsWith('JH')) return 'Honda';
    if (wmi.startsWith('JM')) return 'Mazda';
    if (wmi.startsWith('JN')) return 'Nissan';
    if (wmi.startsWith('JS')) return 'Suzuki';
    if (wmi.startsWith('KM')) return 'Hyundai';
    if (wmi.startsWith('KN')) return 'Kia';
    if (wmi.startsWith('WA')) return 'Audi';
    if (wmi.startsWith('WB')) return 'BMW';
    if (wmi.startsWith('WD')) return 'Mercedes-Benz';
    if (wmi.startsWith('WF')) return 'Ford Germany';
    if (wmi.startsWith('WP')) return 'Porsche';
    if (wmi.startsWith('WV')) return 'Volkswagen';
    if (wmi.startsWith('YV')) return 'Volvo';
    if (wmi.startsWith('ZF')) return 'Ferrari';
    if (wmi.startsWith('ZA')) return 'Lamborghini';
    if (wmi.startsWith('ZH')) return 'Maserati';
    return null;
  }

  void dispose() {
    _database?.close();
  }
}

/// Vehicle profile model
class VehicleProfile {
  final String id;
  final String? vin;
  final String? nickname;
  final String? make;
  final String? model;
  final int? year;
  final String? engine;
  final String? transmission;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  VehicleProfile({
    required this.id,
    this.vin,
    this.nickname,
    this.make,
    this.model,
    this.year,
    this.engine,
    this.transmission,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VehicleProfile.fromMap(Map<String, dynamic> map) {
    return VehicleProfile(
      id: map['id'] as String,
      vin: map['vin'] as String?,
      nickname: map['nickname'] as String?,
      make: map['make'] as String?,
      model: map['model'] as String?,
      year: map['year'] as int?,
      engine: map['engine'] as String?,
      transmission: map['transmission'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  /// Display name for the vehicle
  String get displayName {
    if (nickname != null && nickname!.isNotEmpty) return nickname!;
    if (year != null && make != null) return '$year $make ${model ?? ''}'.trim();
    if (make != null) return make!;
    if (vin != null) return 'VIN: ${vin!.substring(vin!.length - 6)}';
    return 'Unknown Vehicle';
  }

  VehicleProfile copyWith({
    String? id,
    String? vin,
    String? nickname,
    String? make,
    String? model,
    int? year,
    String? engine,
    String? transmission,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return VehicleProfile(
      id: id ?? this.id,
      vin: vin ?? this.vin,
      nickname: nickname ?? this.nickname,
      make: make ?? this.make,
      model: model ?? this.model,
      year: year ?? this.year,
      engine: engine ?? this.engine,
      transmission: transmission ?? this.transmission,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Vehicle history with statistics
class VehicleHistory {
  final VehicleProfile vehicle;
  final List<SessionSummary> sessions;
  final int totalSessions;
  final int totalDtcs;
  final int totalDataPoints;
  final Duration totalSessionTime;

  VehicleHistory({
    required this.vehicle,
    required this.sessions,
    required this.totalSessions,
    required this.totalDtcs,
    required this.totalDataPoints,
    required this.totalSessionTime,
  });

  String get formattedTotalTime {
    final hours = totalSessionTime.inHours;
    final minutes = totalSessionTime.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
