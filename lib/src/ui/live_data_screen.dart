import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/diagnostic_providers.dart';
import '../obd/obd_protocol.dart';
import '../models/vehicle_data.dart';
import 'theme.dart';

class LiveDataScreen extends ConsumerStatefulWidget {
  const LiveDataScreen({super.key});

  @override
  ConsumerState<LiveDataScreen> createState() => _LiveDataScreenState();
}

class _LiveDataScreenState extends ConsumerState<LiveDataScreen> {
  bool _isMonitoring = false;
  StreamSubscription? _liveDataSubscription;
  final Map<OBDPid, List<FlSpot>> _chartData = {};
  int _dataPointIndex = 0;

  static const int maxDataPoints = 50;

  @override
  void dispose() {
    _stopMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPids = ref.watch(selectedPidsProvider);
    final currentReadings = ref.watch(currentReadingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Data'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showPidSelector,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildControlBar(),
          Expanded(
            child: selectedPids.isEmpty
                ? _buildEmptyState()
                : _buildDataView(selectedPids, currentReadings),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _isMonitoring ? _stopMonitoring : _startMonitoring,
              icon: Icon(_isMonitoring ? Icons.stop : Icons.play_arrow),
              label: Text(_isMonitoring ? 'Stop' : 'Start Monitoring'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isMonitoring ? AppTheme.errorColor : AppTheme.successColor,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearData,
            tooltip: 'Clear Data',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.show_chart,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No PIDs Selected',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the tune icon to select parameters',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _showPidSelector,
            child: const Text('Select Parameters'),
          ),
        ],
      ),
    );
  }

  Widget _buildDataView(List<OBDPid> pids, Map<OBDPid, LiveDataReading> readings) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pids.length,
      itemBuilder: (context, index) {
        final pid = pids[index];
        final reading = readings[pid];
        return _buildPidCard(pid, reading);
      },
    );
  }

  Widget _buildPidCard(OBDPid pid, LiveDataReading? reading) {
    final chartSpots = _chartData[pid] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pid.description,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reading?.formattedValue ?? '--',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildGauge(pid, reading),
              ],
            ),
            if (chartSpots.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 80,
                child: LineChart(
                  LineChartData(
                    gridData: const FlGridData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: chartSpots,
                        isCurved: true,
                        color: AppTheme.primaryColor,
                        barWidth: 2,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppTheme.primaryColor.withOpacity(0.1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGauge(OBDPid pid, LiveDataReading? reading) {
    double? value;
    double maxValue = 100;

    if (reading?.value != null) {
      if (reading!.value is num) {
        value = (reading.value as num).toDouble();
      }
    }

    // Set appropriate max values for different PIDs
    switch (pid) {
      case OBDPid.engineRpm:
        maxValue = 8000;
        break;
      case OBDPid.vehicleSpeed:
        maxValue = 200;
        break;
      case OBDPid.coolantTemp:
      case OBDPid.intakeAirTemp:
        maxValue = 150;
        value = value != null ? value + 40 : null; // Add offset back for display
        break;
      default:
        maxValue = 100;
    }

    final percentage = value != null ? (value / maxValue).clamp(0.0, 1.0) : 0.0;

    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        children: [
          CircularProgressIndicator(
            value: percentage,
            strokeWidth: 6,
            backgroundColor: Colors.grey[200],
            color: _getGaugeColor(percentage),
          ),
          Center(
            child: Text(
              '${(percentage * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Color _getGaugeColor(double percentage) {
    if (percentage < 0.5) return AppTheme.successColor;
    if (percentage < 0.75) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }

  void _startMonitoring() {
    final selectedPids = ref.read(selectedPidsProvider);
    if (selectedPids.isEmpty) {
      _showPidSelector();
      return;
    }

    setState(() => _isMonitoring = true);

    final service = ref.read(diagnosticServiceProvider);
    service.startMonitoring(selectedPids);

    _liveDataSubscription = service.liveDataStream.listen((reading) {
      ref.read(currentReadingsProvider.notifier).updateReading(reading);

      // Update chart data
      setState(() {
        if (!_chartData.containsKey(reading.pid)) {
          _chartData[reading.pid] = [];
        }

        final spots = _chartData[reading.pid]!;
        double yValue = 0;

        if (reading.value is num) {
          yValue = (reading.value as num).toDouble();
        }

        spots.add(FlSpot(_dataPointIndex.toDouble(), yValue));

        if (spots.length > maxDataPoints) {
          spots.removeAt(0);
        }

        _dataPointIndex++;
      });
    });
  }

  void _stopMonitoring() {
    setState(() => _isMonitoring = false);

    _liveDataSubscription?.cancel();
    _liveDataSubscription = null;

    final service = ref.read(diagnosticServiceProvider);
    service.stopMonitoring();
  }

  void _clearData() {
    setState(() {
      _chartData.clear();
      _dataPointIndex = 0;
    });
    ref.read(currentReadingsProvider.notifier).clear();
  }

  void _showPidSelector() {
    final availablePids = ref.read(availablePidsProvider);
    final selectedPids = ref.read(selectedPidsProvider);

    // Get common PIDs that are likely supported
    final commonPids = [
      OBDPid.engineRpm,
      OBDPid.vehicleSpeed,
      OBDPid.coolantTemp,
      OBDPid.engineLoad,
      OBDPid.throttlePosition,
      OBDPid.intakeAirTemp,
      OBDPid.mafAirFlow,
      OBDPid.fuelTankLevel,
      OBDPid.timingAdvance,
      OBDPid.shortTermFuelBank1,
      OBDPid.longTermFuelBank1,
    ].where((pid) => availablePids.isEmpty || availablePids.contains(pid.code)).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.3,
            expand: false,
            builder: (context, scrollController) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Select Parameters',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: commonPids.length,
                      itemBuilder: (context, index) {
                        final pid = commonPids[index];
                        final isSelected = selectedPids.contains(pid);

                        return CheckboxListTile(
                          title: Text(pid.description),
                          subtitle: Text(pid.unit.isEmpty ? 'Status' : pid.unit),
                          value: isSelected,
                          onChanged: (value) {
                            setModalState(() {
                              final newSelection = List<OBDPid>.from(selectedPids);
                              if (value == true) {
                                newSelection.add(pid);
                              } else {
                                newSelection.remove(pid);
                              }
                              ref.read(selectedPidsProvider.notifier).state = newSelection;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
