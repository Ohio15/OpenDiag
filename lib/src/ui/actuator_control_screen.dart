import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/module_providers.dart';
import '../uds/module_scanner.dart';
import '../uds/bidirectional.dart';
import '../uds/uds_protocol.dart';
import 'theme.dart';

class ActuatorControlScreen extends ConsumerStatefulWidget {
  final VehicleModule module;
  final List<ActuatorControl> actuators;

  const ActuatorControlScreen({
    super.key,
    required this.module,
    required this.actuators,
  });

  @override
  ConsumerState<ActuatorControlScreen> createState() => _ActuatorControlScreenState();
}

class _ActuatorControlScreenState extends ConsumerState<ActuatorControlScreen> {
  String? _activeActuatorId;
  Map<String, double> _actuatorValues = {};
  Set<String> _runningActuators = {};

  String _getActuatorId(ActuatorControl actuator) => actuator.did.toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.module.shortName} Controls'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.reset),
            onPressed: _stopAllActuators,
            tooltip: 'Stop All',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildWarningBanner(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.actuators.length,
              itemBuilder: (context, index) {
                final actuator = widget.actuators[index];
                return _buildActuatorCard(actuator);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppTheme.warningColor.withOpacity(0.1),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: AppTheme.warningColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Actuator tests may cause vehicle components to move or operate. '
              'Ensure vehicle is in a safe condition before testing.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.warningColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActuatorCard(ActuatorControl actuator) {
    final actuatorId = _getActuatorId(actuator);
    final isRunning = _runningActuators.contains(actuatorId);
    final isActive = _activeActuatorId == actuatorId;
    final testState = ref.watch(actuatorTestStateProvider)[actuatorId] ?? ActuatorTestState.idle;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: _buildActuatorIcon(actuator, testState),
        title: Text(actuator.name),
        subtitle: Text(actuator.description),
        trailing: _buildActuatorTrailing(actuator, isRunning, testState),
        initiallyExpanded: isActive,
        onExpansionChanged: (expanded) {
          setState(() => _activeActuatorId = expanded ? actuatorId : null);
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildActuatorControls(actuator, isRunning),
          ),
        ],
      ),
    );
  }

  Widget _buildActuatorIcon(ActuatorControl actuator, ActuatorTestState state) {
    Color bgColor;
    Color iconColor;
    IconData icon;

    switch (state) {
      case ActuatorTestState.running:
        bgColor = AppTheme.primaryColor.withOpacity(0.1);
        iconColor = AppTheme.primaryColor;
        icon = Icons.sync;
        break;
      case ActuatorTestState.success:
        bgColor = AppTheme.successColor.withOpacity(0.1);
        iconColor = AppTheme.successColor;
        icon = Icons.check;
        break;
      case ActuatorTestState.failed:
        bgColor = AppTheme.errorColor.withOpacity(0.1);
        iconColor = AppTheme.errorColor;
        icon = Icons.close;
        break;
      default:
        bgColor = Theme.of(context).colorScheme.surfaceContainerHighest;
        iconColor = Theme.of(context).colorScheme.onSurface;
        icon = _getActuatorIcon(actuator.type);
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: state == ActuatorTestState.running
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(iconColor),
              ),
            )
          : Icon(icon, color: iconColor),
    );
  }

  IconData _getActuatorIcon(ActuatorType type) {
    switch (type) {
      case ActuatorType.onOff:
        return Icons.toggle_on;
      case ActuatorType.momentary:
        return Icons.touch_app;
      case ActuatorType.variable:
        return Icons.tune;
      case ActuatorType.multiState:
        return Icons.list;
      case ActuatorType.continuous:
        return Icons.all_inclusive;
    }
  }

  Widget _buildActuatorTrailing(ActuatorControl actuator, bool isRunning, ActuatorTestState state) {
    if (isRunning) {
      return TextButton(
        onPressed: () => _stopActuator(actuator),
        style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
        child: const Text('STOP'),
      );
    }

    return ElevatedButton(
      onPressed: state == ActuatorTestState.running ? null : () => _runActuator(actuator),
      child: const Text('Test'),
    );
  }

  Widget _buildActuatorControls(ActuatorControl actuator, bool isRunning) {
    switch (actuator.type) {
      case ActuatorType.onOff:
        return _buildOnOffControl(actuator, isRunning);
      case ActuatorType.variable:
        return _buildVariableControl(actuator, isRunning);
      case ActuatorType.momentary:
        return _buildMomentaryControl(actuator, isRunning);
      case ActuatorType.multiState:
        return _buildMultiStateControl(actuator, isRunning);
      case ActuatorType.continuous:
        return _buildContinuousControl(actuator, isRunning);
    }
  }

  Widget _buildOnOffControl(ActuatorControl actuator, bool isRunning) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'On/Off Control',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'This actuator supports simple on/off control. '
          'Press Test to activate for the default duration.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isRunning ? null : () => _setActuatorState(actuator, false),
                icon: const Icon(Icons.toggle_off),
                label: const Text('Off'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isRunning ? null : () => _setActuatorState(actuator, true),
                icon: const Icon(Icons.toggle_on),
                label: const Text('On'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMomentaryControl(ActuatorControl actuator, bool isRunning) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Momentary Activation',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'This actuator activates briefly when triggered. Hold button for extended activation.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isRunning ? null : () => _runActuator(actuator),
            icon: const Icon(Icons.touch_app),
            label: const Text('Activate'),
          ),
        ),
      ],
    );
  }

  Widget _buildVariableControl(ActuatorControl actuator, bool isRunning) {
    final actuatorId = _getActuatorId(actuator);
    final currentValue = _actuatorValues[actuatorId] ?? 50.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Variable Control',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              '${currentValue.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Slider(
          value: currentValue,
          min: 0,
          max: 100,
          divisions: 20,
          label: '${currentValue.toStringAsFixed(0)}%',
          onChanged: isRunning ? null : (value) {
            setState(() => _actuatorValues[actuatorId] = value);
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('0%'),
            Text('100%'),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isRunning ? null : () => _applyVariableValue(actuator, currentValue),
            icon: const Icon(Icons.send),
            label: const Text('Apply Value'),
          ),
        ),
      ],
    );
  }

  Widget _buildMultiStateControl(ActuatorControl actuator, bool isRunning) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Multi-State Control',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Select a state to activate:',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: actuator.states.map((state) => ElevatedButton(
            onPressed: isRunning ? null : () => _setActuatorMultiState(actuator, state),
            child: Text(state.name),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildContinuousControl(ActuatorControl actuator, bool isRunning) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Continuous Control',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'This actuator runs continuously until stopped.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isRunning ? () => _stopActuator(actuator) : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isRunning ? null : () => _runActuator(actuator),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _runActuator(ActuatorControl actuator) async {
    final actuatorId = _getActuatorId(actuator);
    ref.read(actuatorTestStateProvider.notifier).setTestState(actuatorId, ActuatorTestState.running);
    setState(() => _runningActuators.add(actuatorId));

    try {
      final bidirectional = ref.read(bidirectionalServiceProvider);

      final result = await bidirectional.executeActuatorTest(widget.module, actuator);

      ref.read(actuatorTestStateProvider.notifier).setTestState(
        actuatorId,
        result.success ? ActuatorTestState.success : ActuatorTestState.failed,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success
                ? '${actuator.name} test completed'
                : '${actuator.name} failed: ${result.errorMessage}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: result.success ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }

      // Auto reset after delay
      await Future.delayed(const Duration(seconds: 2));
      ref.read(actuatorTestStateProvider.notifier).setTestState(actuatorId, ActuatorTestState.idle);
    } catch (e) {
      ref.read(actuatorTestStateProvider.notifier).setTestState(actuatorId, ActuatorTestState.failed);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      setState(() => _runningActuators.remove(actuatorId));
    }
  }

  Future<void> _stopActuator(ActuatorControl actuator) async {
    final actuatorId = _getActuatorId(actuator);
    try {
      final bidirectional = ref.read(bidirectionalServiceProvider);
      await bidirectional.stopActuator(widget.module, actuator);

      setState(() => _runningActuators.remove(actuatorId));
      ref.read(actuatorTestStateProvider.notifier).setTestState(actuatorId, ActuatorTestState.idle);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${actuator.name} stopped'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to stop: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _stopAllActuators() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop All Actuators?'),
        content: const Text('This will return all actuators to ECU control.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Stop All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    for (final actuator in widget.actuators) {
      final actuatorId = _getActuatorId(actuator);
      if (_runningActuators.contains(actuatorId)) {
        await _stopActuator(actuator);
      }
    }
  }

  Future<void> _setActuatorState(ActuatorControl actuator, bool on) async {
    final actuatorId = _getActuatorId(actuator);
    ref.read(actuatorTestStateProvider.notifier).setTestState(actuatorId, ActuatorTestState.running);

    try {
      final bidirectional = ref.read(bidirectionalServiceProvider);

      final result = await bidirectional.setActuatorState(
        widget.module,
        actuator,
        on ? IOControlParameter.shortTermAdjustment : IOControlParameter.returnControlToECU,
        on ? [0xFF] : [0x00],
      );

      ref.read(actuatorTestStateProvider.notifier).setTestState(
        actuatorId,
        result.success ? ActuatorTestState.success : ActuatorTestState.failed,
      );

      if (on) {
        setState(() => _runningActuators.add(actuatorId));
      } else {
        setState(() => _runningActuators.remove(actuatorId));
      }
    } catch (e) {
      ref.read(actuatorTestStateProvider.notifier).setTestState(actuatorId, ActuatorTestState.failed);
    }
  }

  Future<void> _applyVariableValue(ActuatorControl actuator, double value) async {
    final actuatorId = _getActuatorId(actuator);
    ref.read(actuatorTestStateProvider.notifier).setTestState(actuatorId, ActuatorTestState.running);

    try {
      final bidirectional = ref.read(bidirectionalServiceProvider);

      // Convert percentage to byte value
      final byteValue = ((value / 100.0) * 255).round().clamp(0, 255);

      final result = await bidirectional.setActuatorState(
        widget.module,
        actuator,
        IOControlParameter.shortTermAdjustment,
        [byteValue],
      );

      ref.read(actuatorTestStateProvider.notifier).setTestState(
        actuatorId,
        result.success ? ActuatorTestState.success : ActuatorTestState.failed,
      );

      if (result.success) {
        setState(() => _runningActuators.add(actuatorId));
      }
    } catch (e) {
      ref.read(actuatorTestStateProvider.notifier).setTestState(actuatorId, ActuatorTestState.failed);
    }
  }

  Future<void> _setActuatorMultiState(ActuatorControl actuator, ActuatorState state) async {
    final actuatorId = _getActuatorId(actuator);
    ref.read(actuatorTestStateProvider.notifier).setTestState(actuatorId, ActuatorTestState.running);

    try {
      final bidirectional = ref.read(bidirectionalServiceProvider);

      final result = await bidirectional.setActuatorState(
        widget.module,
        actuator,
        IOControlParameter.shortTermAdjustment,
        state.controlBytes,
      );

      ref.read(actuatorTestStateProvider.notifier).setTestState(
        actuatorId,
        result.success ? ActuatorTestState.success : ActuatorTestState.failed,
      );

      if (result.success) {
        setState(() => _runningActuators.add(actuatorId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${actuator.name} set to ${state.name}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      }
    } catch (e) {
      ref.read(actuatorTestStateProvider.notifier).setTestState(actuatorId, ActuatorTestState.failed);
    }
  }
}
