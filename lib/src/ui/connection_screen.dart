import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/diagnostic_providers.dart';
import '../platform/platform.dart';
import 'theme.dart';

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  bool _isScanning = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Set default to Bluetooth Classic on Android if not already set
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentType = ref.read(selectedVciTypeProvider);
        if (currentType == null) {
          ref.read(selectedVciTypeProvider.notifier).state = VciDeviceType.elm327Bluetooth;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final devices = ref.watch(scannedDevicesProvider);
    final connectedDevice = ref.watch(connectedDeviceProvider);
    final selectedVciType = ref.watch(selectedVciTypeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to VCI'),
        actions: [
          if (VciFactory.isSerialPlatform)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isScanning ? null : _startScan,
              tooltip: 'Refresh Ports',
            ),
        ],
      ),
      body: Column(
        children: [
          // Connection type selector for Android
          if (Platform.isAndroid)
            _buildConnectionTypeSelector(selectedVciType),
          // Platform-specific help text
          _buildHelpBanner(selectedVciType),
          if (connectionState == ConnectionStatus.connected && connectedDevice != null)
            _buildConnectedCard(connectedDevice),
          if (_errorMessage != null)
            _buildErrorBanner(),
          Expanded(
            child: _buildDeviceList(devices),
          ),
        ],
      ),
      floatingActionButton: connectionState != ConnectionStatus.connected
          ? FloatingActionButton.extended(
              onPressed: _isScanning ? null : _startScan,
              icon: _isScanning
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_getScanIcon(selectedVciType)),
              label: Text(_isScanning
                  ? 'Scanning...'
                  : _getScanButtonText(selectedVciType)),
            )
          : null,
    );
  }

  IconData _getScanIcon(VciDeviceType? type) {
    if (VciFactory.isSerialPlatform) return Icons.usb;
    if (type == VciDeviceType.elm327Bluetooth) return Icons.bluetooth;
    return AppIcons.scan;
  }

  String _getScanButtonText(VciDeviceType? type) {
    if (VciFactory.isSerialPlatform) return 'Scan Ports';
    if (type == VciDeviceType.elm327Bluetooth) return 'Scan Paired Devices';
    return 'Scan for Devices';
  }

  Widget _buildConnectionTypeSelector(VciDeviceType? selectedType) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connection Type',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<VciDeviceType>(
            segments: [
              ButtonSegment<VciDeviceType>(
                value: VciDeviceType.elm327Bluetooth,
                label: const Text('Bluetooth'),
                icon: const Icon(Icons.bluetooth, size: 18),
              ),
              ButtonSegment<VciDeviceType>(
                value: VciDeviceType.elm327,
                label: const Text('BLE'),
                icon: const Icon(Icons.bluetooth_searching, size: 18),
              ),
            ],
            selected: {selectedType ?? VciDeviceType.elm327Bluetooth},
            onSelectionChanged: (Set<VciDeviceType> newSelection) {
              ref.read(selectedVciTypeProvider.notifier).state = newSelection.first;
              // Clear scanned devices when switching types
              ref.read(scannedDevicesProvider.notifier).state = [];
            },
          ),
          const SizedBox(height: 4),
          Text(
            selectedType == VciDeviceType.elm327Bluetooth
                ? 'For standard ELM327 adapters. Pair in Android Settings first.'
                : 'For modern BLE OBD adapters.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpBanner(VciDeviceType? selectedType) {
    String helpText;
    IconData icon;

    if (VciFactory.isSerialPlatform) {
      helpText = VciFactory.connectionHelpText;
      icon = Icons.usb;
    } else if (selectedType == VciDeviceType.elm327Bluetooth) {
      helpText = 'Make sure your ELM327 adapter is paired in Android Settings. '
                 'Only paired devices will appear below.';
      icon = Icons.bluetooth;
    } else {
      helpText = 'Scanning for nearby BLE OBD adapters...';
      icon = Icons.bluetooth_searching;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
      child: Row(
        children: [
          Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              helpText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedCard(VciDeviceInfo device) {
    return Card(
      margin: const EdgeInsets.all(16),
      color: AppTheme.successColor.withOpacity(0.1),
      child: ListTile(
        leading: const Icon(AppIcons.connected, color: AppTheme.successColor),
        title: Text(device.displayName),
        subtitle: Text('Connected - ${device.typeDescription}'),
        trailing: TextButton(
          onPressed: _disconnect,
          child: const Text('Disconnect'),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: AppTheme.errorColor.withOpacity(0.1),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.errorColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: AppTheme.errorColor),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(List<VciDeviceInfo> devices) {
    final selectedType = ref.watch(selectedVciTypeProvider);

    if (devices.isEmpty && !_isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getEmptyIcon(selectedType),
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _getEmptyMessage(selectedType),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getEmptyHint(selectedType),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        return _buildDeviceCard(device);
      },
    );
  }

  IconData _getEmptyIcon(VciDeviceType? type) {
    if (VciFactory.isSerialPlatform) return Icons.usb_off;
    if (type == VciDeviceType.elm327Bluetooth) return Icons.bluetooth_disabled;
    return AppIcons.connect;
  }

  String _getEmptyMessage(VciDeviceType? type) {
    if (VciFactory.isSerialPlatform) return 'No COM ports found';
    if (type == VciDeviceType.elm327Bluetooth) return 'No paired devices found';
    return 'No devices found';
  }

  String _getEmptyHint(VciDeviceType? type) {
    if (VciFactory.isSerialPlatform) {
      return 'Connect your OBD adapter and tap "Scan Ports"';
    }
    if (type == VciDeviceType.elm327Bluetooth) {
      return 'Pair your ELM327 adapter in Android Settings first,\n'
             'then tap "Scan Paired Devices"';
    }
    return 'Tap "Scan for Devices" to search';
  }

  Widget _buildDeviceCard(VciDeviceInfo device) {
    final connectionState = ref.watch(connectionStateProvider);
    final isConnecting = connectionState == ConnectionStatus.connecting;

    // Choose icon based on device type
    IconData deviceIcon;
    Color iconColor;

    switch (device.type) {
      case VciDeviceType.elm327Bluetooth:
        deviceIcon = Icons.bluetooth;
        iconColor = Colors.blue;
        break;
      case VciDeviceType.elm327:
        deviceIcon = Icons.bluetooth_searching;
        iconColor = Colors.indigo;
        break;
      case VciDeviceType.autelVci:
        deviceIcon = Icons.build;
        iconColor = AppTheme.primaryColor;
        break;
      case VciDeviceType.serialPort:
        deviceIcon = Icons.usb;
        iconColor = Colors.green;
        if (device.name.toUpperCase().contains('BLUETOOTH')) {
          deviceIcon = Icons.bluetooth;
          iconColor = Colors.blue;
        }
        break;
      case VciDeviceType.unknown:
        deviceIcon = Icons.device_unknown;
        iconColor = Colors.grey;
        break;
    }

    // Build subtitle
    String subtitle;
    if (VciFactory.isSerialPlatform) {
      subtitle = device.description ?? device.typeDescription;
    } else if (device.type == VciDeviceType.elm327Bluetooth) {
      subtitle = device.description ?? 'Bluetooth Classic';
    } else {
      subtitle = '${device.typeDescription} - Signal: ${device.signalStrength} dBm';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(deviceIcon, color: iconColor),
        title: Text(device.displayName),
        subtitle: Text(subtitle),
        trailing: isConnecting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : ElevatedButton(
                onPressed: () => _connectToDevice(device),
                child: const Text('Connect'),
              ),
      ),
    );
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    // Request permissions only on mobile platforms
    if (VciFactory.isBluetoothPlatform) {
      final permissions = await _requestBluetoothPermissions();
      if (!permissions) {
        setState(() {
          _isScanning = false;
          _errorMessage = 'Bluetooth permissions required';
        });
        return;
      }
    }

    try {
      final connection = ref.read(vciConnectionProvider);
      final devices = await connection.scanForDevices();

      ref.read(scannedDevicesProvider.notifier).state = devices;

      if (devices.isEmpty) {
        final selectedType = ref.read(selectedVciTypeProvider);
        setState(() {
          if (VciFactory.isSerialPlatform) {
            _errorMessage = 'No COM ports found. Make sure your adapter is connected.';
          } else if (selectedType == VciDeviceType.elm327Bluetooth) {
            _errorMessage = 'No paired Bluetooth devices found. '
                           'Go to Android Settings > Bluetooth and pair your ELM327 first.';
          } else {
            _errorMessage = 'No BLE devices found nearby.';
          }
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  Future<bool> _requestBluetoothPermissions() async {
    // Skip permissions on desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return true;
    }

    final selectedType = ref.read(selectedVciTypeProvider);

    // Bluetooth Classic requires these permissions
    final bluetoothScan = await Permission.bluetoothScan.request();
    final bluetoothConnect = await Permission.bluetoothConnect.request();

    // Location is typically required for BLE scanning
    if (selectedType != VciDeviceType.elm327Bluetooth) {
      final location = await Permission.locationWhenInUse.request();
      return bluetoothScan.isGranted &&
          bluetoothConnect.isGranted &&
          location.isGranted;
    }

    return bluetoothScan.isGranted && bluetoothConnect.isGranted;
  }

  Future<void> _connectToDevice(VciDeviceInfo device) async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final connection = ref.read(vciConnectionProvider);
      await connection.connect(device);

      ref.read(connectedDeviceProvider.notifier).state = device;

      // Initialize diagnostic service
      final diagnosticService = ref.read(diagnosticServiceProvider);
      diagnosticService.setConnectedDevice(device);
      await diagnosticService.initialize();

      // Update available PIDs
      ref.read(availablePidsProvider.notifier).state = diagnosticService.supportedPids;

      // Update VIN if available
      if (diagnosticService.vin != null) {
        ref.read(vinProvider.notifier).state = diagnosticService.vin;
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection failed: $e';
      });
    }
  }

  Future<void> _disconnect() async {
    try {
      final connection = ref.read(vciConnectionProvider);
      await connection.disconnect();

      ref.read(connectedDeviceProvider.notifier).state = null;
      ref.read(availablePidsProvider.notifier).state = {};
      ref.read(vinProvider.notifier).state = null;
    } catch (e) {
      setState(() {
        _errorMessage = 'Disconnect failed: $e';
      });
    }
  }
}
