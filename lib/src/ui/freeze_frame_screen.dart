import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/diagnostic_providers.dart';
import '../models/vehicle_data.dart';
import '../obd/obd_protocol.dart';
import 'theme.dart';

class FreezeFrameScreen extends ConsumerStatefulWidget {
  const FreezeFrameScreen({super.key});

  @override
  ConsumerState<FreezeFrameScreen> createState() => _FreezeFrameScreenState();
}

class _FreezeFrameScreenState extends ConsumerState<FreezeFrameScreen> {
  FreezeFrame? _freezeFrame;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFreezeFrame();
  }

  Future<void> _loadFreezeFrame() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(diagnosticServiceProvider);
      final freezeFrame = await service.readFreezeFrame();

      setState(() {
        _freezeFrame = freezeFrame;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Freeze Frame Data'),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadFreezeFrame,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Error: $_errorMessage'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFreezeFrame,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_freezeFrame == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.ac_unit,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Freeze Frame Data',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Freeze frame data is captured when a DTC is set',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return _buildFreezeFrameContent(_freezeFrame!);
  }

  Widget _buildFreezeFrameContent(FreezeFrame frame) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDTCCard(frame.dtc),
          const SizedBox(height: 16),
          _buildTimestampCard(frame.timestamp),
          const SizedBox(height: 16),
          _buildReadingsCard(frame.readings),
        ],
      ),
    );
  }

  Widget _buildDTCCard(DTC dtc) {
    final categoryColor = _getCategoryColor(dtc.category);

    return Card(
      color: categoryColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: categoryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  dtc.category.prefix,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: categoryColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Triggering DTC',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: categoryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dtc.code,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    dtc.category.description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimestampCard(DateTime timestamp) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.access_time),
        title: const Text('Captured'),
        subtitle: Text(
          '${timestamp.day}/${timestamp.month}/${timestamp.year} '
          '${timestamp.hour.toString().padLeft(2, '0')}:'
          '${timestamp.minute.toString().padLeft(2, '0')}:'
          '${timestamp.second.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }

  Widget _buildReadingsCard(Map<OBDPid, dynamic> readings) {
    if (readings.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No parameter data available',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Captured Parameters',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          ...readings.entries.map((entry) => _buildReadingItem(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildReadingItem(OBDPid pid, dynamic value) {
    String formattedValue;

    if (value == null) {
      formattedValue = 'N/A';
    } else if (value is double) {
      formattedValue = '${value.toStringAsFixed(1)} ${pid.unit}';
    } else if (value is int) {
      formattedValue = '$value ${pid.unit}'.trim();
    } else {
      formattedValue = value.toString();
    }

    return ListTile(
      title: Text(pid.description),
      trailing: Text(
        formattedValue,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }

  Color _getCategoryColor(DTCCategory category) {
    switch (category) {
      case DTCCategory.powertrain:
        return AppTheme.errorColor;
      case DTCCategory.chassis:
        return AppTheme.warningColor;
      case DTCCategory.body:
        return AppTheme.primaryColor;
      case DTCCategory.network:
        return Colors.purple;
    }
  }
}
