import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../obd/enhanced_pids.dart';
import 'theme.dart';

// Settings providers
final unitsProvider = StateProvider<UnitSystem>((ref) => UnitSystem.metric);
final autoConnectProvider = StateProvider<bool>((ref) => false);
final keepScreenOnProvider = StateProvider<bool>((ref) => true);
final loggingEnabledProvider = StateProvider<bool>((ref) => false);

enum UnitSystem { metric, imperial }

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final unitSystem = prefs.getString('units') == 'imperial'
        ? UnitSystem.imperial
        : UnitSystem.metric;
    ref.read(unitsProvider.notifier).state = unitSystem;

    ref.read(autoConnectProvider.notifier).state =
        prefs.getBool('autoConnect') ?? false;
    ref.read(keepScreenOnProvider.notifier).state =
        prefs.getBool('keepScreenOn') ?? true;
    ref.read(loggingEnabledProvider.notifier).state =
        prefs.getBool('logging') ?? false;
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('units',
        ref.read(unitsProvider) == UnitSystem.imperial ? 'imperial' : 'metric');
    await prefs.setBool('autoConnect', ref.read(autoConnectProvider));
    await prefs.setBool('keepScreenOn', ref.read(keepScreenOnProvider));
    await prefs.setBool('logging', ref.read(loggingEnabledProvider));
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitsProvider);
    final autoConnect = ref.watch(autoConnectProvider);
    final keepScreenOn = ref.watch(keepScreenOnProvider);
    final loggingEnabled = ref.watch(loggingEnabledProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          _buildSectionHeader('Units'),
          _buildRadioTile(
            title: 'Metric',
            subtitle: 'km/h, °C, kPa, L',
            value: UnitSystem.metric,
            groupValue: units,
            onChanged: (value) {
              ref.read(unitsProvider.notifier).state = value!;
              _saveSettings();
            },
          ),
          _buildRadioTile(
            title: 'Imperial',
            subtitle: 'mph, °F, psi, gal',
            value: UnitSystem.imperial,
            groupValue: units,
            onChanged: (value) {
              ref.read(unitsProvider.notifier).state = value!;
              _saveSettings();
            },
          ),
          const Divider(),
          _buildSectionHeader('Connection'),
          SwitchListTile(
            title: const Text('Auto-connect'),
            subtitle: const Text('Automatically connect to last used device'),
            value: autoConnect,
            onChanged: (value) {
              ref.read(autoConnectProvider.notifier).state = value;
              _saveSettings();
            },
          ),
          const Divider(),
          _buildSectionHeader('Display'),
          SwitchListTile(
            title: const Text('Keep Screen On'),
            subtitle: const Text('Prevent screen from turning off during diagnostics'),
            value: keepScreenOn,
            onChanged: (value) {
              ref.read(keepScreenOnProvider.notifier).state = value;
              _saveSettings();
            },
          ),
          const Divider(),
          _buildSectionHeader('Data'),
          SwitchListTile(
            title: const Text('Enable Logging'),
            subtitle: const Text('Log diagnostic data to file'),
            value: loggingEnabled,
            onChanged: (value) {
              ref.read(loggingEnabledProvider.notifier).state = value;
              _saveSettings();
            },
          ),
          ListTile(
            title: const Text('Clear Diagnostic History'),
            subtitle: const Text('Delete all saved diagnostic sessions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showClearHistoryDialog,
          ),
          const Divider(),
          _buildSectionHeader('About'),
          ListTile(
            title: const Text('OpenDiag'),
            subtitle: const Text('Version 1.0.0'),
            trailing: const Icon(Icons.info_outline),
            onTap: _showAboutDialog,
          ),
          ListTile(
            title: const Text('Supported Protocols'),
            subtitle: const Text('View OBD-II protocol information'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showProtocolInfo,
          ),
          ListTile(
            title: const Text('DTC Database'),
            subtitle: const Text('View supported trouble codes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showDTCDatabase,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppTheme.primaryColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRadioTile<T>({
    required String title,
    required String subtitle,
    required T value,
    required T groupValue,
    required ValueChanged<T?> onChanged,
  }) {
    return RadioListTile<T>(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
    );
  }

  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text(
          'This will delete all saved diagnostic sessions and data. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _clearHistory();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearHistory() async {
    // Clear local database
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('History cleared')),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'OpenDiag',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.build, size: 48),
      children: [
        const Text(
          'Open-source vehicle diagnostic application using OBD-II protocols.\n\n'
          'Supports Autel VCI dongles and ELM327 adapters.',
        ),
      ],
    );
  }

  void _showProtocolInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Supported Protocols',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: CANProtocols.protocolNames.length,
                  itemBuilder: (context, index) {
                    final entry = CANProtocols.protocolNames.entries.elementAt(index);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                        child: Text('${entry.key}'),
                      ),
                      title: Text(entry.value),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDTCDatabase() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          final dtcEntries = DTCDatabase.genericPowertrain.entries.toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'DTC Database',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dtcEntries.length} codes',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: dtcEntries.length,
                  itemBuilder: (context, index) {
                    final entry = dtcEntries[index];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.errorColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.errorColor,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      title: Text(
                        entry.value,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
