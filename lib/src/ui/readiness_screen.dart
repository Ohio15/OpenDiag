import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/diagnostic_providers.dart';
import '../models/vehicle_data.dart';
import 'theme.dart';

class ReadinessScreen extends ConsumerStatefulWidget {
  const ReadinessScreen({super.key});

  @override
  ConsumerState<ReadinessScreen> createState() => _ReadinessScreenState();
}

class _ReadinessScreenState extends ConsumerState<ReadinessScreen> {
  @override
  Widget build(BuildContext context) {
    final monitorsAsync = ref.watch(readinessMonitorsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Readiness Monitors'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(readinessMonitorsProvider),
          ),
        ],
      ),
      body: monitorsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(readinessMonitorsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (monitors) {
          if (monitors == null) {
            return const Center(
              child: Text('Unable to read readiness monitors'),
            );
          }
          return _buildContent(monitors);
        },
      ),
    );
  }

  Widget _buildContent(ReadinessMonitors monitors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusCard(monitors),
          const SizedBox(height: 16),
          _buildSummaryCard(monitors),
          const SizedBox(height: 16),
          _buildMonitorsList(monitors),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ReadinessMonitors monitors) {
    final statusColor = monitors.milOn ? AppTheme.errorColor : AppTheme.successColor;
    final statusIcon = monitors.milOn ? Icons.warning : Icons.check_circle;
    final statusText = monitors.milOn ? 'MIL ON' : 'MIL OFF';

    return Card(
      color: statusColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(statusIcon, size: 48, color: statusColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (monitors.dtcCount > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${monitors.dtcCount} DTC${monitors.dtcCount > 1 ? 's' : ''} stored',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(ReadinessMonitors monitors) {
    final completedColor = AppTheme.successColor;
    final incompleteColor = AppTheme.warningColor;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monitor Summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'Completed',
                    monitors.completedCount.toString(),
                    completedColor,
                    Icons.check_circle,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    'Incomplete',
                    monitors.incompleteCount.toString(),
                    incompleteColor,
                    Icons.hourglass_empty,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    'Total',
                    monitors.supportedCount.toString(),
                    AppTheme.primaryColor,
                    Icons.list,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: monitors.supportedCount > 0
                  ? monitors.completedCount / monitors.supportedCount
                  : 0,
              backgroundColor: incompleteColor.withOpacity(0.2),
              color: completedColor,
            ),
            const SizedBox(height: 8),
            Text(
              monitors.allComplete
                  ? 'All monitors complete - Ready for inspection'
                  : 'Some monitors incomplete - Drive cycle required',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: monitors.allComplete ? completedColor : incompleteColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildMonitorsList(ReadinessMonitors monitors) {
    final sortedMonitors = monitors.monitors.entries.toList()
      ..sort((a, b) {
        // Sort by supported first, then by status
        if (a.value.supported != b.value.supported) {
          return a.value.supported ? -1 : 1;
        }
        if (a.value.complete != b.value.complete) {
          return a.value.complete ? -1 : 1;
        }
        return a.key.compareTo(b.key);
      });

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Individual Monitors',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          ...sortedMonitors.map((entry) => _buildMonitorItem(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildMonitorItem(String name, MonitorStatus status) {
    Color statusColor;
    IconData statusIcon;

    if (!status.supported) {
      statusColor = Colors.grey;
      statusIcon = Icons.remove_circle_outline;
    } else if (status.complete) {
      statusColor = AppTheme.successColor;
      statusIcon = Icons.check_circle;
    } else {
      statusColor = AppTheme.warningColor;
      statusIcon = Icons.hourglass_empty;
    }

    return ListTile(
      leading: Icon(statusIcon, color: statusColor),
      title: Text(name),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          status.statusText,
          style: TextStyle(
            color: statusColor,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
