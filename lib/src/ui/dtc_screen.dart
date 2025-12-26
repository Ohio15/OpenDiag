import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/diagnostic_providers.dart';
import '../obd/obd_protocol.dart';
import 'theme.dart';

class DTCScreen extends ConsumerStatefulWidget {
  const DTCScreen({super.key});

  @override
  ConsumerState<DTCScreen> createState() => _DTCScreenState();
}

class _DTCScreenState extends ConsumerState<DTCScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isClearing = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic Trouble Codes'),
        actions: [
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refresh,
          ),
          IconButton(
            icon: _isClearing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.clearDtc),
            onPressed: _isClearing ? null : _showClearDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Stored'),
            Tab(text: 'Pending'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDTCList(ref.watch(storedDTCsProvider)),
          _buildDTCList(ref.watch(pendingDTCsProvider)),
        ],
      ),
    );
  }

  Widget _buildDTCList(AsyncValue<List<DTC>> dtcsAsync) {
    return dtcsAsync.when(
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
              onPressed: _refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (dtcs) {
        if (dtcs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: AppTheme.successColor.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No DTCs Found',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Vehicle has no trouble codes',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: dtcs.length,
          itemBuilder: (context, index) {
            final dtc = dtcs[index];
            return _buildDTCCard(dtc);
          },
        );
      },
    );
  }

  Widget _buildDTCCard(DTC dtc) {
    final categoryColor = _getCategoryColor(dtc.category);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showDTCDetails(dtc),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    dtc.category.prefix,
                    style: TextStyle(
                      fontSize: 20,
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
                      dtc.code,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dtc.category.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: categoryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
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

  void _showDTCDetails(DTC dtc) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  dtc.code,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Category', dtc.category.description),
            _buildDetailRow('Type', _getDTCType(dtc.code)),
            _buildDetailRow('Raw Value', '0x${dtc.rawValue.toRadixString(16).toUpperCase()}'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // TODO: Implement DTC lookup
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.search),
                label: const Text('Look Up Code'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
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
            ),
          ),
        ],
      ),
    );
  }

  String _getDTCType(String code) {
    if (code.length < 2) return 'Unknown';

    final digit = code[1];
    switch (digit) {
      case '0':
        return 'Generic (SAE)';
      case '1':
        return 'Manufacturer Specific';
      case '2':
        return 'Generic (SAE)';
      case '3':
        return 'Manufacturer Specific';
      default:
        return 'Unknown';
    }
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);

    ref.invalidate(storedDTCsProvider);
    ref.invalidate(pendingDTCsProvider);

    await Future.delayed(const Duration(milliseconds: 500));

    setState(() => _isRefreshing = false);
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear DTCs'),
        content: const Text(
          'This will clear all stored diagnostic trouble codes and reset emission monitors. '
          'This action cannot be undone.\n\n'
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _clearDTCs();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text('Clear DTCs'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearDTCs() async {
    setState(() => _isClearing = true);

    try {
      final service = ref.read(diagnosticServiceProvider);
      final success = await service.clearDTCs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'DTCs cleared successfully' : 'Failed to clear DTCs'),
            backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );

        if (success) {
          _refresh();
        }
      }
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
      setState(() => _isClearing = false);
    }
  }
}
