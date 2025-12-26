import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/diagnostic_providers.dart';
import '../providers/module_providers.dart';
import '../uds/module_scanner.dart';
import '../uds/uds_protocol.dart';
import '../uds/security_access.dart';
import '../uds/bidirectional.dart';
import 'theme.dart';
import 'actuator_control_screen.dart';

class ModuleDetailScreen extends ConsumerStatefulWidget {
  final VehicleModule module;

  const ModuleDetailScreen({super.key, required this.module});

  @override
  ConsumerState<ModuleDetailScreen> createState() => _ModuleDetailScreenState();
}

class _ModuleDetailScreenState extends ConsumerState<ModuleDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoadingDTCs = false;
  bool _isUnlockingSecurity = false;
  bool _isClearingDTCs = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadModuleDTCs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final dtcs = ref.watch(moduleDTCsProvider)[module.address] ?? [];
    final isUnlocked = ref.watch(securityAccessStateProvider)[module.address] ?? module.isSecurityUnlocked;

    return Scaffold(
      appBar: AppBar(
        title: Text(module.shortName),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(AppIcons.info),
              text: 'Info',
            ),
            Tab(
              icon: Badge(
                label: dtcs.isNotEmpty ? Text('${dtcs.length}') : null,
                isLabelVisible: dtcs.isNotEmpty,
                child: const Icon(AppIcons.dtc),
              ),
              text: 'DTCs',
            ),
            Tab(
              icon: Icon(isUnlocked ? AppIcons.actuator : AppIcons.locked),
              text: 'Controls',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInfoTab(module),
          _buildDTCsTab(module, dtcs),
          _buildControlsTab(module, isUnlocked),
        ],
      ),
    );
  }

  // ==================== INFO TAB ====================

  Widget _buildInfoTab(VehicleModule module) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard(module),
        const SizedBox(height: 16),
        _buildSessionCard(module),
        const SizedBox(height: 16),
        _buildSecurityCard(module),
      ],
    );
  }

  Widget _buildInfoCard(VehicleModule module) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Module Information',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            _buildInfoRow('Name', module.name),
            _buildInfoRow('Short Name', module.shortName),
            _buildInfoRow('Address', '0x${module.address.toRadixString(16).toUpperCase().padLeft(3, '0')}'),
            _buildInfoRow('Category', module.category.name.toUpperCase()),
            if (module.partNumber != null)
              _buildInfoRow('Part Number', module.partNumber!),
            if (module.softwareVersion != null)
              _buildInfoRow('Software Version', module.softwareVersion!),
            if (module.hardwareVersion != null)
              _buildInfoRow('Hardware Version', module.hardwareVersion!),
            if (module.manufacturer != null)
              _buildInfoRow('Manufacturer', module.manufacturer!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          )),
        ],
      ),
    );
  }

  Widget _buildSessionCard(VehicleModule module) {
    final sessionName = _getSessionName(module.currentSession);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Diagnostic Session',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Current Session', style: Theme.of(context).textTheme.bodyMedium),
                Chip(
                  label: Text(sessionName),
                  backgroundColor: _getSessionColor(module.currentSession).withOpacity(0.2),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _switchSession(module, DiagnosticSession.defaultSession),
                    child: const Text('Default'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _switchSession(module, DiagnosticSession.extendedDiagnosticSession),
                    child: const Text('Extended'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCard(VehicleModule module) {
    final isUnlocked = ref.watch(securityAccessStateProvider)[module.address] ?? module.isSecurityUnlocked;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Security Access',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Icon(
                  isUnlocked ? AppIcons.security : AppIcons.locked,
                  color: isUnlocked ? AppTheme.successColor : AppTheme.warningColor,
                ),
              ],
            ),
            const Divider(),
            Text(
              isUnlocked
                  ? 'Module is unlocked for bi-directional control'
                  : 'Security access required for some functions',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUnlockingSecurity ? null : () => _requestSecurityAccess(module),
                icon: _isUnlockingSecurity
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(isUnlocked ? AppIcons.security : AppIcons.locked),
                label: Text(isUnlocked ? 'Refresh Access' : 'Unlock Security'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== DTCs TAB ====================

  Widget _buildDTCsTab(VehicleModule module, List<ModuleDTC> dtcs) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoadingDTCs ? null : () => _loadModuleDTCs(),
                  icon: _isLoadingDTCs
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AppIcons.refresh),
                  label: const Text('Read DTCs'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: dtcs.isEmpty || _isClearingDTCs ? null : () => _clearDTCs(module),
                  icon: _isClearingDTCs
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AppIcons.clearDtc),
                  label: const Text('Clear DTCs'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.errorColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: dtcs.isEmpty
              ? _buildNoDTCsState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: dtcs.length,
                  itemBuilder: (context, index) => _buildDTCCard(dtcs[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildNoDTCsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle,
            size: 64,
            color: AppTheme.successColor,
          ),
          const SizedBox(height: 16),
          Text(
            'No DTCs Found',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'This module has no stored trouble codes',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildDTCCard(ModuleDTC dtc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    dtc.code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    dtc.status.displayStatus,
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: _getDTCStatusColor(dtc.status).withOpacity(0.2),
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                if (dtc.status.warningIndicatorRequested)
                  const Icon(Icons.warning, color: AppTheme.warningColor, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              dtc.description ?? 'Unknown DTC',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (dtc.status.testFailed)
                  _buildStatusChip('Test Failed', AppTheme.errorColor),
                if (dtc.status.pendingDTC)
                  _buildStatusChip('Pending', AppTheme.warningColor),
                if (dtc.status.confirmedDTC)
                  _buildStatusChip('Confirmed', AppTheme.errorColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }

  // ==================== CONTROLS TAB ====================

  Widget _buildControlsTab(VehicleModule module, bool isUnlocked) {
    if (!isUnlocked && module.requiresSecurityAccess) {
      return _buildSecurityRequiredState(module);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildActuatorTestsSection(module),
        const SizedBox(height: 16),
        _buildRoutineControlsSection(module),
        const SizedBox(height: 16),
        _buildIOControlsSection(module),
      ],
    );
  }

  Widget _buildSecurityRequiredState(VehicleModule module) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.locked,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Security Access Required',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'This module requires security access to enable bi-directional controls',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isUnlockingSecurity ? null : () => _requestSecurityAccess(module),
              icon: _isUnlockingSecurity
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.security),
              label: const Text('Unlock Module'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActuatorTestsSection(VehicleModule module) {
    final actuators = ActuatorDatabase.getActuatorsForModule(module.category);
    if (actuators.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(AppIcons.actuator),
                  const SizedBox(width: 8),
                  Text(
                    'Actuator Tests',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'No actuator tests available for this module',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(AppIcons.actuator),
                    const SizedBox(width: 8),
                    Text(
                      'Actuator Tests',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => _navigateToActuatorTests(module, actuators),
                  child: const Text('View All'),
                ),
              ],
            ),
            const Divider(),
            ...actuators.take(3).map((actuator) => _buildActuatorRow(module, actuator)),
            if (actuators.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+ ${actuators.length - 3} more tests',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActuatorRow(VehicleModule module, ActuatorControl actuator) {
    final testState = ref.watch(actuatorTestStateProvider)[actuator.did.toString()] ?? ActuatorTestState.idle;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _buildActuatorTestIcon(testState),
      title: Text(actuator.name),
      subtitle: Text(actuator.description),
      trailing: ElevatedButton(
        onPressed: testState == ActuatorTestState.running
            ? null
            : () => _runActuatorTest(module, actuator),
        child: testState == ActuatorTestState.running
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Test'),
      ),
    );
  }

  Widget _buildActuatorTestIcon(ActuatorTestState state) {
    switch (state) {
      case ActuatorTestState.idle:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(AppIcons.ioControl),
        );
      case ActuatorTestState.running:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case ActuatorTestState.success:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.successColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.check, color: AppTheme.successColor),
        );
      case ActuatorTestState.failed:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.errorColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.close, color: AppTheme.errorColor),
        );
    }
  }

  Widget _buildRoutineControlsSection(VehicleModule module) {
    final routines = RoutineDatabase.getRoutinesForModule(module.category);
    if (routines.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AppIcons.routine),
                const SizedBox(width: 8),
                Text(
                  'Routine Controls',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            ...routines.map((routine) => _buildRoutineRow(module, routine)),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutineRow(VehicleModule module, RoutineDefinition routine) {
    final result = ref.watch(routineResultsProvider)[routine.routineId.toString()];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(routine.type == RoutineType.reset
            ? AppIcons.reset
            : AppIcons.routine),
      ),
      title: Text(routine.name),
      subtitle: Text(routine.description),
      trailing: ElevatedButton(
        onPressed: () => _runRoutine(module, routine),
        child: const Text('Run'),
      ),
    );
  }

  Widget _buildIOControlsSection(VehicleModule module) {
    // I/O Controls specific to module type
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AppIcons.ioControl),
                const SizedBox(width: 8),
                Text(
                  'I/O Control',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            Text(
              'Advanced I/O control allows direct control of actuators and sensors. '
              'Use with caution.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _navigateToActuatorTests(module, ActuatorDatabase.getActuatorsForModule(module.category)),
                icon: const Icon(AppIcons.actuator),
                label: const Text('Open I/O Control Panel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== HELPER METHODS ====================

  String _getSessionName(int session) {
    switch (session) {
      case DiagnosticSession.defaultSession:
        return 'Default';
      case DiagnosticSession.programmingSession:
        return 'Programming';
      case DiagnosticSession.extendedDiagnosticSession:
        return 'Extended';
      default:
        return 'Unknown';
    }
  }

  Color _getSessionColor(int session) {
    switch (session) {
      case DiagnosticSession.defaultSession:
        return Colors.grey;
      case DiagnosticSession.extendedDiagnosticSession:
        return AppTheme.primaryColor;
      case DiagnosticSession.programmingSession:
        return AppTheme.warningColor;
      default:
        return Colors.grey;
    }
  }

  Color _getDTCStatusColor(DTCStatus status) {
    if (status.confirmedDTC) return AppTheme.errorColor;
    if (status.pendingDTC) return AppTheme.warningColor;
    return Colors.grey;
  }

  Future<void> _loadModuleDTCs() async {
    setState(() => _isLoadingDTCs = true);

    try {
      final connection = ref.read(vciConnectionProvider);
      final module = widget.module;

      // Read DTCs by status mask (0xFF = all DTCs)
      final response = await connection.sendUDSCommand(
        module.address,
        [UDSService.readDTCInformation, 0x02, 0xFF], // reportDTCByStatusMask
      );

      if (response.isNotEmpty && response[0] == (UDSService.readDTCInformation + 0x40)) {
        final dtcs = <ModuleDTC>[];

        // Parse DTC records (3 bytes per DTC + 1 byte status)
        for (var i = 3; i < response.length - 3; i += 4) {
          final dtcBytes = response.sublist(i, i + 4);
          dtcs.add(ModuleDTC.fromBytes(dtcBytes));
        }

        ref.read(moduleDTCsProvider.notifier).setDTCs(module.address, dtcs);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to read DTCs: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingDTCs = false);
      }
    }
  }

  Future<void> _clearDTCs(VehicleModule module) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear DTCs?'),
        content: const Text(
          'This will clear all stored diagnostic trouble codes. '
          'Make sure to diagnose any issues before clearing.',
        ),
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
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isClearingDTCs = true);

    try {
      final connection = ref.read(vciConnectionProvider);

      // Clear DTCs (Service 0x14)
      final response = await connection.sendUDSCommand(
        module.address,
        [UDSService.clearDiagnosticInformation, 0xFF, 0xFF, 0xFF], // Clear all groups
      );

      if (response.isNotEmpty && response[0] == (UDSService.clearDiagnosticInformation + 0x40)) {
        ref.read(moduleDTCsProvider.notifier).clearDTCs(module.address);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('DTCs cleared successfully'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear DTCs: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClearingDTCs = false);
      }
    }
  }

  Future<void> _switchSession(VehicleModule module, int sessionType) async {
    try {
      final securityManager = ref.read(securityAccessProvider);

      bool success;
      if (sessionType == DiagnosticSession.extendedDiagnosticSession) {
        success = await securityManager.switchToExtendedSession(module);
      } else {
        success = await securityManager.switchToDefaultSession(module);
      }

      if (success && mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switched to ${_getSessionName(sessionType)} session'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session switch failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _requestSecurityAccess(VehicleModule module) async {
    setState(() => _isUnlockingSecurity = true);

    try {
      final securityManager = ref.read(securityAccessProvider);

      // First switch to extended session
      await securityManager.switchToExtendedSession(module);

      // Request security access level 1
      final result = await securityManager.requestSecurityAccess(
        module,
        SecurityLevel.ioControl,
      );

      if (result.success) {
        ref.read(securityAccessStateProvider.notifier).setUnlocked(module.address, true);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Security access granted'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Security access denied: ${result.errorMessage}'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Security access failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUnlockingSecurity = false);
      }
    }
  }

  Future<void> _runActuatorTest(VehicleModule module, ActuatorControl actuator) async {
    ref.read(actuatorTestStateProvider.notifier).setTestState(actuator.did.toString(), ActuatorTestState.running);

    try {
      final bidirectional = ref.read(bidirectionalServiceProvider);

      final result = await bidirectional.executeActuatorTest(module, actuator);

      ref.read(actuatorTestStateProvider.notifier).setTestState(
        actuator.did.toString(),
        result.success ? ActuatorTestState.success : ActuatorTestState.failed,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success
                ? '${actuator.name} test completed'
                : '${actuator.name} test failed: ${result.errorMessage}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: result.success ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }

      // Reset to idle after a delay
      await Future.delayed(const Duration(seconds: 3));
      ref.read(actuatorTestStateProvider.notifier).setTestState(actuator.did.toString(), ActuatorTestState.idle);
    } catch (e) {
      ref.read(actuatorTestStateProvider.notifier).setTestState(actuator.did.toString(), ActuatorTestState.failed);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Actuator test error: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _runRoutine(VehicleModule module, RoutineDefinition routine) async {
    try {
      final bidirectional = ref.read(bidirectionalServiceProvider);

      final result = await bidirectional.executeRoutine(module, routine);

      ref.read(routineResultsProvider.notifier).setResult(routine.routineId.toString(), result);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.success
                ? '${routine.name} completed successfully'
                : '${routine.name} failed: ${result.errorMessage}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: result.success ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Routine error: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _navigateToActuatorTests(VehicleModule module, List<ActuatorControl> actuators) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActuatorControlScreen(module: module, actuators: actuators),
      ),
    );
  }
}
