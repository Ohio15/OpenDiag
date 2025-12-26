import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/diagnostic_providers.dart';
import '../providers/module_providers.dart';
import '../uds/module_scanner.dart';
import 'theme.dart';
import 'module_detail_screen.dart';

class ModuleListScreen extends ConsumerStatefulWidget {
  const ModuleListScreen({super.key});

  @override
  ConsumerState<ModuleListScreen> createState() => _ModuleListScreenState();
}

class _ModuleListScreenState extends ConsumerState<ModuleListScreen> {
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final isConnected = connectionState == ConnectionStatus.connected;
    final modules = ref.watch(discoveredModulesProvider);
    final scanProgress = ref.watch(moduleScanProgressProvider);
    final scanMessage = ref.watch(moduleScanMessageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Modules'),
        actions: [
          if (modules.isNotEmpty)
            IconButton(
              icon: const Icon(AppIcons.refresh),
              onPressed: isConnected && !_isScanning ? _startScan : null,
              tooltip: 'Rescan Modules',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isScanning) _buildScanProgress(scanProgress, scanMessage),
          if (!isConnected)
            _buildNotConnectedBanner()
          else if (modules.isEmpty && !_isScanning)
            _buildEmptyState()
          else
            Expanded(child: _buildModuleList(modules)),
        ],
      ),
      floatingActionButton: isConnected && modules.isEmpty && !_isScanning
          ? FloatingActionButton.extended(
              onPressed: _startScan,
              icon: const Icon(AppIcons.scan),
              label: const Text('Scan Modules'),
            )
          : null,
    );
  }

  Widget _buildScanProgress(double progress, String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scanning for modules...',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _cancelScan,
                child: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }

  Widget _buildNotConnectedBanner() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.disconnect,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Not Connected',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Connect to a VCI device to scan for vehicle modules',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.modules,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No Modules Found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to scan for ECU modules',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleList(List<VehicleModule> modules) {
    // Group modules by category
    final groupedModules = <ModuleCategory, List<VehicleModule>>{};
    for (final module in modules) {
      groupedModules.putIfAbsent(module.category, () => []).add(module);
    }

    // Sort categories
    final sortedCategories = groupedModules.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedCategories.length,
      itemBuilder: (context, index) {
        final category = sortedCategories[index];
        final categoryModules = groupedModules[category]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _getCategoryName(category),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            ...categoryModules.map((module) => _buildModuleCard(module)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildModuleCard(VehicleModule module) {
    final hasErrors = module.dtcCount > 0;
    final isSecurityLocked = !module.isSecurityUnlocked && module.requiresSecurityAccess;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _navigateToModuleDetail(module),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildModuleIcon(module, hasErrors),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            module.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (isSecurityLocked)
                          Icon(
                            AppIcons.locked,
                            size: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${module.shortName} - 0x${module.address.toRadixString(16).toUpperCase().padLeft(3, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (module.partNumber != null || module.softwareVersion != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          [module.partNumber, module.softwareVersion]
                              .where((s) => s != null)
                              .join(' - '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (hasErrors)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.dtc, size: 16, color: AppTheme.errorColor),
                      const SizedBox(width: 4),
                      Text(
                        '${module.dtcCount}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppTheme.errorColor,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Icon(
                  Icons.check_circle_outline,
                  color: AppTheme.successColor,
                ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModuleIcon(VehicleModule module, bool hasErrors) {
    final icon = _getModuleIcon(module.category);
    final color = hasErrors ? AppTheme.errorColor : AppTheme.primaryColor;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    );
  }

  IconData _getModuleIcon(ModuleCategory category) {
    switch (category) {
      case ModuleCategory.powertrain:
        return AppIcons.engine;
      case ModuleCategory.chassis:
        return AppIcons.abs;
      case ModuleCategory.body:
        return AppIcons.bcm;
      case ModuleCategory.network:
        return AppIcons.modules;
      case ModuleCategory.safety:
        return AppIcons.airbag;
      case ModuleCategory.climate:
        return AppIcons.hvac;
      case ModuleCategory.infotainment:
        return AppIcons.instrument;
      case ModuleCategory.comfort:
        return AppIcons.bcm;
      case ModuleCategory.lighting:
        return AppIcons.bcm;
      case ModuleCategory.unknown:
        return AppIcons.unknown;
    }
  }

  String _getCategoryName(ModuleCategory category) {
    switch (category) {
      case ModuleCategory.powertrain:
        return 'Powertrain';
      case ModuleCategory.chassis:
        return 'Chassis';
      case ModuleCategory.body:
        return 'Body';
      case ModuleCategory.network:
        return 'Network';
      case ModuleCategory.safety:
        return 'Safety';
      case ModuleCategory.climate:
        return 'Climate Control';
      case ModuleCategory.infotainment:
        return 'Infotainment';
      case ModuleCategory.comfort:
        return 'Comfort';
      case ModuleCategory.lighting:
        return 'Lighting';
      case ModuleCategory.unknown:
        return 'Other';
    }
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    ref.read(moduleScanProgressProvider.notifier).state = 0.0;
    ref.read(moduleScanMessageProvider.notifier).state = 'Initializing...';

    try {
      final scanner = ref.read(moduleScannerProvider);

      final modules = await scanner.scanAllModules(
        onProgress: (progress) {
          ref.read(moduleScanProgressProvider.notifier).state = progress.progress;
          ref.read(moduleScanMessageProvider.notifier).state = progress.status;
        },
      );

      ref.read(discoveredModulesProvider.notifier).state = modules;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found ${modules.length} modules'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  void _cancelScan() {
    setState(() => _isScanning = false);
  }

  void _navigateToModuleDetail(VehicleModule module) {
    ref.read(selectedModuleProvider.notifier).state = module;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModuleDetailScreen(module: module),
      ),
    );
  }
}
