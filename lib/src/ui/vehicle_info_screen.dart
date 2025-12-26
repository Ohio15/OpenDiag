import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/diagnostic_providers.dart';
import '../obd/obd_protocol.dart';
import 'theme.dart';

class VehicleInfoScreen extends ConsumerStatefulWidget {
  const VehicleInfoScreen({super.key});

  @override
  ConsumerState<VehicleInfoScreen> createState() => _VehicleInfoScreenState();
}

class _VehicleInfoScreenState extends ConsumerState<VehicleInfoScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final vin = ref.watch(vinProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Information'),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshVIN,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildVINCard(vin),
            if (vin != null && vin.length == 17) ...[
              const SizedBox(height: 16),
              _buildDecodedInfo(vin),
            ],
            const SizedBox(height: 16),
            _buildSupportedPIDsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildVINCard(String? vin) {
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
                  'VIN',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (vin != null)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () => _copyToClipboard(vin),
                    tooltip: 'Copy VIN',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (vin != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  vin,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              _buildVINValidation(vin),
            ] else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(Icons.directions_car, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      'VIN not available',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVINValidation(String vin) {
    final decoder = VINDecoder(vin);
    final isValid = decoder.isValid;

    return Row(
      children: [
        Icon(
          isValid ? Icons.check_circle : Icons.warning,
          size: 16,
          color: isValid ? AppTheme.successColor : AppTheme.warningColor,
        ),
        const SizedBox(width: 8),
        Text(
          isValid ? 'Valid VIN' : 'VIN checksum may be invalid',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isValid ? AppTheme.successColor : AppTheme.warningColor,
          ),
        ),
      ],
    );
  }

  Widget _buildDecodedInfo(String vin) {
    final decoder = VINDecoder(vin);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Decoded Information',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Model Year', decoder.modelYear),
            _buildInfoRow('WMI (Manufacturer)', decoder.worldManufacturerIdentifier),
            _buildInfoRow('VDS (Descriptor)', decoder.vehicleDescriptorSection),
            _buildInfoRow('Plant Code', decoder.plantCode),
            _buildInfoRow('Serial Number', decoder.serialNumber),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportedPIDsCard() {
    final supportedPids = ref.watch(availablePidsProvider);

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
                  'Supported PIDs',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${supportedPids.length}',
                    style: TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (supportedPids.isEmpty)
              Text(
                'Connect to vehicle to see supported PIDs',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: supportedPids.map((pid) {
                  final pidInfo = _getPidInfo(pid);
                  return Tooltip(
                    message: pidInfo?.description ?? 'PID 0x${pid.toRadixString(16).toUpperCase()}',
                    child: Chip(
                      label: Text(
                        '0x${pid.toRadixString(16).toUpperCase().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: pidInfo != null
                          ? AppTheme.primaryColor.withOpacity(0.1)
                          : Colors.grey[200],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  OBDPid? _getPidInfo(int pidCode) {
    try {
      return OBDPid.values.firstWhere((p) => p.code == pidCode);
    } catch (e) {
      return null;
    }
  }

  Future<void> _refreshVIN() async {
    setState(() => _isLoading = true);

    try {
      final service = ref.read(diagnosticServiceProvider);
      await service.initialize();

      if (service.vin != null) {
        ref.read(vinProvider.notifier).state = service.vin;
      }

      ref.read(availablePidsProvider.notifier).state = service.supportedPids;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('VIN copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
