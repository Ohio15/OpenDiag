import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/vci_simulator.dart';
import '../platform/vci_factory.dart';
import '../platform/vci_interface.dart';
import '../providers/diagnostic_providers.dart';
import 'theme.dart';

/// Provider for the simulator instance
final simulatorProvider = StateProvider<VciSimulator?>((ref) => null);

/// Screen for controlling the VCI simulator
class SimulatorScreen extends ConsumerStatefulWidget {
  const SimulatorScreen({super.key});

  @override
  ConsumerState<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends ConsumerState<SimulatorScreen> {
  VciSimulator? _simulator;
  bool _isConnected = false;
  String _dtcInput = '';

  @override
  void initState() {
    super.initState();
    _initSimulator();
  }

  void _initSimulator() {
    _simulator = VciFactory.createSimulator();
    ref.read(simulatorProvider.notifier).state = _simulator;

    _simulator!.connectionStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isConnected = state == VciConnectionState.connected;
        });
      }
    });
  }

  @override
  void dispose() {
    _simulator?.dispose();
    super.dispose();
  }

  Future<void> _connectSimulator() async {
    if (_simulator == null) return;

    try {
      final devices = await _simulator!.scanForDevices();
      if (devices.isNotEmpty) {
        await _simulator!.connect(devices.first);

        // Update the diagnostic service to use the simulator
        final vciManager = ref.read(vciManagerProvider);
        await vciManager.setVci(_simulator!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Simulator connected'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _disconnectSimulator() async {
    if (_simulator == null) return;

    await _simulator!.disconnect();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Simulator disconnected')),
      );
    }
  }

  void _setScenario(SimulatorScenario scenario) {
    if (_simulator == null) return;
    _simulator!.scenario = scenario;
    setState(() {});
  }

  void _addDTC(String code, {bool isPending = false}) {
    if (_simulator == null || code.isEmpty) return;

    // Validate DTC format (P0XXX, C0XXX, B0XXX, U0XXX)
    final dtcRegex = RegExp(r'^[PCBU][0-3][0-9A-F]{3}$', caseSensitive: false);
    if (!dtcRegex.hasMatch(code.toUpperCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid DTC format. Use format like P0420, C0101, etc.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _simulator!.addDTC(code.toUpperCase(), isPending: isPending);
    setState(() {
      _dtcInput = '';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added DTC: ${code.toUpperCase()} (${isPending ? "Pending" : "Stored"})'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _clearDTCs() {
    if (_simulator == null) return;
    _simulator!.clearDTCs();
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('DTCs cleared'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = _simulator?.vehicle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VCI Simulator'),
        actions: [
          if (_isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 4),
                  Text('Connected', style: TextStyle(color: Colors.green)),
                ],
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connection',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isConnected ? null : _connectSimulator,
                            icon: const Icon(Icons.link),
                            label: const Text('Connect'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isConnected ? _disconnectSimulator : null,
                            icon: const Icon(Icons.link_off),
                            label: const Text('Disconnect'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Scenario selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Simulation Scenario',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: SimulatorScenario.values.map((scenario) {
                        final isSelected = _simulator?.scenario == scenario;
                        return ChoiceChip(
                          label: Text(_scenarioLabel(scenario)),
                          selected: isSelected,
                          onSelected: _isConnected
                              ? (_) => _setScenario(scenario)
                              : null,
                          selectedColor: AppTheme.primaryColor.withOpacity(0.3),
                          avatar: Icon(
                            _scenarioIcon(scenario),
                            size: 18,
                            color: isSelected ? AppTheme.primaryColor : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _scenarioDescription(_simulator?.scenario ?? SimulatorScenario.idle),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // DTC simulation
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Diagnostic Trouble Codes',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_simulator?.milOn ?? false)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning, color: Colors.orange, size: 16),
                                SizedBox(width: 4),
                                Text('MIL ON', style: TextStyle(color: Colors.orange, fontSize: 12)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'DTC Code',
                              hintText: 'e.g., P0420',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            textCapitalization: TextCapitalization.characters,
                            onChanged: (value) => _dtcInput = value,
                            enabled: _isConnected,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          children: [
                            ElevatedButton(
                              onPressed: _isConnected
                                  ? () => _addDTC(_dtcInput, isPending: false)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(80, 36),
                              ),
                              child: const Text('Stored'),
                            ),
                            const SizedBox(height: 4),
                            OutlinedButton(
                              onPressed: _isConnected
                                  ? () => _addDTC(_dtcInput, isPending: true)
                                  : null,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(80, 36),
                              ),
                              child: const Text('Pending'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Quick add common DTCs
                    Text(
                      'Quick Add:',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildQuickDTCChip('P0420', 'Catalyst Efficiency'),
                        _buildQuickDTCChip('P0171', 'System Lean'),
                        _buildQuickDTCChip('P0300', 'Random Misfire'),
                        _buildQuickDTCChip('P0442', 'EVAP Small Leak'),
                        _buildQuickDTCChip('P0128', 'Coolant Temp Low'),
                      ],
                    ),

                    if ((_simulator?.activeDTCs.length ?? 0) > 0) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Active DTCs (${_simulator!.activeDTCs.length})',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _isConnected ? _clearDTCs : null,
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Clear All'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _simulator!.activeDTCs.map((dtc) {
                          return Chip(
                            label: Text(dtc.code),
                            backgroundColor: dtc.isPending
                                ? Colors.yellow.withOpacity(0.3)
                                : Colors.red.withOpacity(0.2),
                            side: BorderSide(
                              color: dtc.isPending ? Colors.orange : Colors.red,
                            ),
                            avatar: Icon(
                              dtc.isPending ? Icons.pending : Icons.error,
                              size: 16,
                              color: dtc.isPending ? Colors.orange : Colors.red,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Live vehicle state
            if (_isConnected && vehicle != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Simulated Vehicle State',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'VIN: ${vehicle.vin}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildStateGrid(vehicle),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Instructions
            Card(
              color: Colors.blue.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'How to Use',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '1. Connect the simulator to start generating data\n'
                      '2. Select a scenario to simulate different driving conditions\n'
                      '3. Add DTCs to test diagnostic code features\n'
                      '4. Navigate to Dashboard or DTC screens to see live data\n'
                      '5. The simulator provides realistic OBD-II responses',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickDTCChip(String code, String description) {
    return ActionChip(
      label: Text(code),
      avatar: const Icon(Icons.add, size: 16),
      tooltip: description,
      onPressed: _isConnected ? () => _addDTC(code) : null,
    );
  }

  Widget _buildStateGrid(SimulatorVehicle vehicle) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 2.0,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        _buildStateItem('RPM', vehicle.rpm.toStringAsFixed(0)),
        _buildStateItem('Speed', '${vehicle.speed.toStringAsFixed(0)} km/h'),
        _buildStateItem('Coolant', '${vehicle.coolantTemp.toStringAsFixed(0)}°C'),
        _buildStateItem('Throttle', '${vehicle.throttlePosition.toStringAsFixed(0)}%'),
        _buildStateItem('Load', '${vehicle.engineLoad.toStringAsFixed(0)}%'),
        _buildStateItem('Fuel', '${vehicle.fuelLevel.toStringAsFixed(0)}%'),
        _buildStateItem('Oil Temp', '${vehicle.oilTemp.toStringAsFixed(0)}°C'),
        _buildStateItem('Voltage', '${vehicle.batteryVoltage.toStringAsFixed(1)}V'),
        _buildStateItem('MAF', '${vehicle.mafRate.toStringAsFixed(1)} g/s'),
      ],
    );
  }

  Widget _buildStateItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _scenarioLabel(SimulatorScenario scenario) {
    switch (scenario) {
      case SimulatorScenario.off: return 'Off';
      case SimulatorScenario.idle: return 'Idle';
      case SimulatorScenario.cityDriving: return 'City';
      case SimulatorScenario.highway: return 'Highway';
      case SimulatorScenario.aggressive: return 'Sport';
      case SimulatorScenario.coldStart: return 'Cold Start';
      case SimulatorScenario.engineProblem: return 'Problem';
      case SimulatorScenario.overheating: return 'Overheat';
    }
  }

  IconData _scenarioIcon(SimulatorScenario scenario) {
    switch (scenario) {
      case SimulatorScenario.off: return Icons.power_settings_new;
      case SimulatorScenario.idle: return Icons.pause_circle_outline;
      case SimulatorScenario.cityDriving: return Icons.location_city;
      case SimulatorScenario.highway: return Icons.speed;
      case SimulatorScenario.aggressive: return Icons.sports_score;
      case SimulatorScenario.coldStart: return Icons.ac_unit;
      case SimulatorScenario.engineProblem: return Icons.warning_amber;
      case SimulatorScenario.overheating: return Icons.thermostat;
    }
  }

  String _scenarioDescription(SimulatorScenario scenario) {
    switch (scenario) {
      case SimulatorScenario.off:
        return 'Engine off, all systems at rest';
      case SimulatorScenario.idle:
        return 'Engine running at idle (~800 RPM), stationary';
      case SimulatorScenario.cityDriving:
        return 'Stop-and-go traffic, varying speeds 0-50 km/h';
      case SimulatorScenario.highway:
        return 'Steady cruising at ~110 km/h';
      case SimulatorScenario.aggressive:
        return 'High RPM, high throttle, spirited driving';
      case SimulatorScenario.coldStart:
        return 'Cold engine warming up, elevated idle';
      case SimulatorScenario.engineProblem:
        return 'Rough idle, abnormal fuel trims';
      case SimulatorScenario.overheating:
        return 'Rising coolant temperature, warning state';
    }
  }
}
