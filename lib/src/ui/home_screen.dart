import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/diagnostic_providers.dart';
import 'connection_screen.dart';
import 'dtc_screen.dart';
import 'live_data_screen.dart';
import 'readiness_screen.dart';
import 'vehicle_info_screen.dart';
import 'freeze_frame_screen.dart';
import 'settings_screen.dart';
import 'module_list_screen.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionStateProvider);
    final isConnected = connectionState == ConnectionStatus.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenDiag'),
        actions: [
          IconButton(
            icon: Icon(
              isConnected ? AppIcons.connected : AppIcons.connect,
              color: isConnected ? AppTheme.successColor : null,
            ),
            onPressed: () => _navigateToConnection(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildConnectionStatus(context, ref, isConnected),
            const SizedBox(height: 24),
            Expanded(
              child: _buildFeatureGrid(context, isConnected),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(BuildContext context, WidgetRef ref, bool isConnected) {
    final connectedDevice = ref.watch(connectedDeviceProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? AppTheme.successColor : Colors.grey,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConnected ? 'Connected' : 'Not Connected',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (isConnected && connectedDevice != null)
                    Text(
                      connectedDevice.displayName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _navigateToConnection(context),
              child: Text(isConnected ? 'Disconnect' : 'Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureGrid(BuildContext context, bool isConnected) {
    final features = [
      _FeatureItem(
        icon: Icons.dashboard,
        title: 'Dashboard',
        subtitle: 'Live gauges & recording',
        color: Colors.teal,
        onTap: isConnected ? () => _navigateToDashboard(context) : null,
      ),
      _FeatureItem(
        icon: AppIcons.dtc,
        title: 'Read DTCs',
        subtitle: 'View diagnostic codes',
        color: AppTheme.errorColor,
        onTap: isConnected ? () => _navigateToDTC(context) : null,
      ),
      _FeatureItem(
        icon: AppIcons.liveData,
        title: 'Live Data',
        subtitle: 'Real-time sensors',
        color: AppTheme.primaryColor,
        onTap: isConnected ? () => _navigateToLiveData(context) : null,
      ),
      _FeatureItem(
        icon: AppIcons.readiness,
        title: 'Readiness',
        subtitle: 'Monitor status',
        color: AppTheme.successColor,
        onTap: isConnected ? () => _navigateToReadiness(context) : null,
      ),
      _FeatureItem(
        icon: AppIcons.vehicle,
        title: 'Vehicle Info',
        subtitle: 'VIN & details',
        color: AppTheme.secondaryColor,
        onTap: isConnected ? () => _navigateToVehicleInfo(context) : null,
      ),
      _FeatureItem(
        icon: AppIcons.freezeFrame,
        title: 'Freeze Frame',
        subtitle: 'DTC snapshot',
        color: Colors.cyan,
        onTap: isConnected ? () => _navigateToFreezeFrame(context) : null,
      ),
      _FeatureItem(
        icon: AppIcons.modules,
        title: 'Modules',
        subtitle: 'ECU control',
        color: Colors.deepPurple,
        onTap: isConnected ? () => _navigateToModules(context) : null,
      ),
      _FeatureItem(
        icon: Icons.history,
        title: 'History',
        subtitle: 'Sessions & reports',
        color: Colors.indigo,
        onTap: () => _navigateToHistory(context),
      ),
      _FeatureItem(
        icon: AppIcons.settings,
        title: 'Settings',
        subtitle: 'App preferences',
        color: Colors.grey,
        onTap: () => _navigateToSettings(context),
      ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.9,
      children: features.map((f) => _buildFeatureCard(context, f, isConnected)).toList(),
    );
  }

  Widget _buildFeatureCard(BuildContext context, _FeatureItem feature, bool isConnected) {
    final isEnabled = feature.onTap != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: feature.onTap,
        child: Opacity(
          opacity: isEnabled ? 1.0 : 0.5,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  feature.icon,
                  size: 36,
                  color: feature.color,
                ),
                const SizedBox(height: 8),
                Text(
                  feature.title,
                  style: Theme.of(context).textTheme.titleSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  feature.subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToConnection(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConnectionScreen()),
    );
  }

  void _navigateToDashboard(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  void _navigateToDTC(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DTCScreen()),
    );
  }

  void _navigateToLiveData(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LiveDataScreen()),
    );
  }

  void _navigateToReadiness(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReadinessScreen()),
    );
  }

  void _navigateToVehicleInfo(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VehicleInfoScreen()),
    );
  }

  void _navigateToFreezeFrame(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FreezeFrameScreen()),
    );
  }

  void _navigateToModules(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ModuleListScreen()),
    );
  }

  void _navigateToHistory(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  void _navigateToSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  _FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });
}
