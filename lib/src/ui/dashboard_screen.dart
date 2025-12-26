import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import '../providers/diagnostic_providers.dart';
import '../obd/obd_protocol.dart';
import '../services/recording_service.dart';
import '../models/vehicle_data.dart';
import 'theme.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _refreshTimer;
  bool _isRecording = false;
  final _recordingService = RecordingService();

  // Live data values
  double _rpm = 0;
  double _speed = 0;
  double _coolantTemp = 0;
  double _throttle = 0;
  double _engineLoad = 0;
  double _fuelLevel = 0;
  double _intakeTemp = 0;
  double _maf = 0;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_isRecording) {
      _recordingService.stopSession();
    }
    super.dispose();
  }

  void _startPolling() {
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _pollData();
    });
  }


  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return 0;
  }

  Future<void> _pollData() async {
    try {
      final service = ref.read(diagnosticServiceProvider);

      // Poll each PID and update values
      final readings = await Future.wait<PidReading?>([
        service.readPid(OBDPid.engineRpm).catchError((_) => null),
        service.readPid(OBDPid.vehicleSpeed).catchError((_) => null),
        service.readPid(OBDPid.coolantTemp).catchError((_) => null),
        service.readPid(OBDPid.throttlePosition).catchError((_) => null),
        service.readPid(OBDPid.engineLoad).catchError((_) => null),
        service.readPid(OBDPid.fuelTankLevel).catchError((_) => null),
        service.readPid(OBDPid.intakeAirTemp).catchError((_) => null),
        service.readPid(OBDPid.mafAirFlow).catchError((_) => null),
      ]);

      if (!mounted) return;

      setState(() {
        if (readings[0] != null) _rpm = _toDouble(readings[0]!.parsedValue);
        if (readings[1] != null) _speed = _toDouble(readings[1]!.parsedValue);
        if (readings[2] != null) _coolantTemp = _toDouble(readings[2]!.parsedValue);
        if (readings[3] != null) _throttle = _toDouble(readings[3]!.parsedValue);
        if (readings[4] != null) _engineLoad = _toDouble(readings[4]!.parsedValue);
        if (readings[5] != null) _fuelLevel = _toDouble(readings[5]!.parsedValue);
        if (readings[6] != null) _intakeTemp = _toDouble(readings[6]!.parsedValue);
        if (readings[7] != null) _maf = _toDouble(readings[7]!.parsedValue);
      });

      // Record if active
      if (_isRecording) {
        for (final reading in readings) {
          if (reading != null) {
            _recordingService.recordPidReading(reading);
          }
        }
      }
    } catch (e) {
      // Ignore polling errors
    }
  }

  void _toggleRecording() async {
    if (_isRecording) {
      await _recordingService.stopSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording stopped')),
        );
      }
    } else {
      await _recordingService.startSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording started')),
        );
      }
    }
    setState(() => _isRecording = !_isRecording);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Dashboard'),
        actions: [
          IconButton(
            icon: Icon(
              _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
              color: _isRecording ? Colors.red : null,
            ),
            onPressed: _toggleRecording,
            tooltip: _isRecording ? 'Stop Recording' : 'Start Recording',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Main gauges row
            Row(
              children: [
                Expanded(
                  child: _buildRadialGauge(
                    'RPM',
                    _rpm,
                    0,
                    8000,
                    'rpm',
                    [
                      _GaugeRange(0, 2000, Colors.blue),
                      _GaugeRange(2000, 4000, Colors.green),
                      _GaugeRange(4000, 6000, Colors.orange),
                      _GaugeRange(6000, 8000, Colors.red),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildRadialGauge(
                    'Speed',
                    _speed,
                    0,
                    200,
                    'km/h',
                    [
                      _GaugeRange(0, 50, Colors.green),
                      _GaugeRange(50, 100, Colors.blue),
                      _GaugeRange(100, 150, Colors.orange),
                      _GaugeRange(150, 200, Colors.red),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Secondary gauges
            Row(
              children: [
                Expanded(
                  child: _buildMiniGauge(
                    'Coolant',
                    _coolantTemp,
                    -40,
                    120,
                    '°C',
                    _coolantTemp > 100 ? Colors.red :
                    _coolantTemp > 90 ? Colors.orange : Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildMiniGauge(
                    'Throttle',
                    _throttle,
                    0,
                    100,
                    '%',
                    AppTheme.primaryColor,
                  ),
                ),
                Expanded(
                  child: _buildMiniGauge(
                    'Load',
                    _engineLoad,
                    0,
                    100,
                    '%',
                    _engineLoad > 80 ? Colors.red :
                    _engineLoad > 50 ? Colors.orange : Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Linear gauges
            _buildLinearGauge('Fuel Level', _fuelLevel, 0, 100, '%', Colors.amber),
            const SizedBox(height: 12),
            _buildLinearGauge('Intake Air', _intakeTemp, -40, 80, '°C', Colors.cyan),
            const SizedBox(height: 12),
            _buildLinearGauge('MAF Rate', _maf, 0, 500, 'g/s', Colors.purple),

            const SizedBox(height: 24),

            // Data cards
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Readings',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _buildDataRow('Engine RPM', '${_rpm.toStringAsFixed(0)} rpm'),
                    _buildDataRow('Vehicle Speed', '${_speed.toStringAsFixed(0)} km/h'),
                    _buildDataRow('Coolant Temp', '${_coolantTemp.toStringAsFixed(1)} °C'),
                    _buildDataRow('Throttle Position', '${_throttle.toStringAsFixed(1)} %'),
                    _buildDataRow('Engine Load', '${_engineLoad.toStringAsFixed(1)} %'),
                    _buildDataRow('Fuel Level', '${_fuelLevel.toStringAsFixed(1)} %'),
                    _buildDataRow('Intake Air Temp', '${_intakeTemp.toStringAsFixed(1)} °C'),
                    _buildDataRow('MAF Rate', '${_maf.toStringAsFixed(2)} g/s'),
                  ],
                ),
              ),
            ),

            if (_isRecording) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Recording in progress...',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRadialGauge(
    String title,
    double value,
    double min,
    double max,
    String unit,
    List<_GaugeRange> ranges,
  ) {
    return Column(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: SfRadialGauge(
            axes: [
              RadialAxis(
                minimum: min,
                maximum: max,
                showLabels: true,
                showTicks: true,
                axisLineStyle: const AxisLineStyle(
                  thickness: 0.15,
                  thicknessUnit: GaugeSizeUnit.factor,
                ),
                ranges: ranges.map((r) => GaugeRange(
                  startValue: r.start,
                  endValue: r.end,
                  color: r.color.withOpacity(0.3),
                  startWidth: 20,
                  endWidth: 20,
                )).toList(),
                pointers: [
                  NeedlePointer(
                    value: value.clamp(min, max),
                    enableAnimation: true,
                    animationType: AnimationType.ease,
                    animationDuration: 200,
                    needleLength: 0.7,
                    needleStartWidth: 1,
                    needleEndWidth: 5,
                    knobStyle: const KnobStyle(
                      knobRadius: 0.08,
                      sizeUnit: GaugeSizeUnit.factor,
                    ),
                  ),
                ],
                annotations: [
                  GaugeAnnotation(
                    widget: Text(
                      '${value.toStringAsFixed(0)} $unit',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    angle: 90,
                    positionFactor: 0.5,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniGauge(
    String title,
    double value,
    double min,
    double max,
    String unit,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 80,
              child: SfRadialGauge(
                axes: [
                  RadialAxis(
                    minimum: min,
                    maximum: max,
                    showLabels: false,
                    showTicks: false,
                    startAngle: 180,
                    endAngle: 0,
                    axisLineStyle: AxisLineStyle(
                      thickness: 0.2,
                      thicknessUnit: GaugeSizeUnit.factor,
                      color: Colors.grey[300],
                    ),
                    pointers: [
                      RangePointer(
                        value: value.clamp(min, max),
                        width: 0.2,
                        sizeUnit: GaugeSizeUnit.factor,
                        color: color,
                        enableAnimation: true,
                        animationDuration: 200,
                      ),
                    ],
                    annotations: [
                      GaugeAnnotation(
                        widget: Text(
                          '${value.toStringAsFixed(0)}$unit',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        angle: 90,
                        positionFactor: 0.0,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinearGauge(
    String title,
    double value,
    double min,
    double max,
    String unit,
    Color color,
  ) {
    final percentage = ((value - min) / (max - min)).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  '${value.toStringAsFixed(1)} $unit',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _GaugeRange {
  final double start;
  final double end;
  final Color color;

  _GaugeRange(this.start, this.end, this.color);
}
