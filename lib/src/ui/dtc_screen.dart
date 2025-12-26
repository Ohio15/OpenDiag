import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/diagnostic_providers.dart';
import '../obd/obd_protocol.dart';
import '../data/dtc_database.dart';
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
  final _dtcDatabase = DTCDatabase();

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
            icon: const Icon(Icons.search),
            onPressed: _showSearchSheet,
            tooltip: 'Search DTC Database',
          ),
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

  void _showSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _DTCSearchSheet(
          scrollController: scrollController,
          database: _dtcDatabase,
        ),
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
            Text('Error: \$error'),
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
    final definition = _dtcDatabase.lookup(dtc.code);
    final severityColor = _getSeverityColor(definition?.severity);

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
                    Row(
                      children: [
                        Text(
                          dtc.code,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (definition != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: severityColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              definition.severity.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: severityColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      definition?.description ?? dtc.category.description,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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

  Color _getSeverityColor(DTCSeverity? severity) {
    switch (severity) {
      case DTCSeverity.critical:
        return Colors.red;
      case DTCSeverity.warning:
        return Colors.orange;
      case DTCSeverity.info:
        return Colors.blue;
      case DTCSeverity.unknown:
      case null:
        return Colors.grey;
    }
  }

  void _showDTCDetails(DTC dtc) {
    final definition = _dtcDatabase.lookup(dtc.code);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Row(
                children: [
                  Text(
                    dtc.code,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (definition != null) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getSeverityColor(definition.severity).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        definition.severity.label,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _getSeverityColor(definition.severity),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Description
              if (definition != null) ...[
                Text(
                  definition.description,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
              ],

              // Basic info
              _buildDetailRow('Category', dtc.category.description),
              _buildDetailRow('Type', _getDTCType(dtc.code)),
              _buildDetailRow('Raw Value', '0x\${dtc.rawValue.toRadixString(16).toUpperCase()}'),

              if (definition != null) ...[
                // Cause
                if (definition.cause != null) ...[
                  const SizedBox(height: 20),
                  _buildSectionHeader('Possible Cause'),
                  const SizedBox(height: 8),
                  Text(definition.cause!),
                ],

                // Symptoms
                if (definition.symptoms != null) ...[
                  const SizedBox(height: 20),
                  _buildSectionHeader('Symptoms'),
                  const SizedBox(height: 8),
                  Text(definition.symptoms!),
                ],

                // Fixes
                if (definition.possibleFixes.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _buildSectionHeader('Suggested Repairs'),
                  const SizedBox(height: 8),
                  ...definition.possibleFixes.map((fix) => _buildBulletPoint(fix)),
                ],
              ] else ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey[600]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No detailed information available for this code in the database.',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: AppTheme.primaryColor,
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 8),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[600],
            ),
          ),
          Expanded(child: Text(text)),
        ],
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
            content: Text('Error: \$e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      setState(() => _isClearing = false);
    }
  }
}

/// Search sheet for browsing DTC database
class _DTCSearchSheet extends StatefulWidget {
  final ScrollController scrollController;
  final DTCDatabase database;

  const _DTCSearchSheet({
    required this.scrollController,
    required this.database,
  });

  @override
  State<_DTCSearchSheet> createState() => _DTCSearchSheetState();
}

class _DTCSearchSheetState extends State<_DTCSearchSheet> {
  final _searchController = TextEditingController();
  List<DTCDefinition> _results = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search(String query) {
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _results = widget.database.search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'DTC Database Search',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search by code or description...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _search('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: _search,
          ),
        ),
        // Results
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        _searchController.text.isEmpty
                            ? 'Enter a code or keyword to search'
                            : 'No results found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final def = _results[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Row(
                          children: [
                            Text(
                              def.code,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getSeverityColor(def.severity).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                def.severity.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _getSeverityColor(def.severity),
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          def.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          def.category,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        onTap: () => _showDefinitionDetails(def),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _getSeverityColor(DTCSeverity severity) {
    switch (severity) {
      case DTCSeverity.critical:
        return Colors.red;
      case DTCSeverity.warning:
        return Colors.orange;
      case DTCSeverity.info:
        return Colors.blue;
      case DTCSeverity.unknown:
        return Colors.grey;
    }
  }

  void _showDefinitionDetails(DTCDefinition def) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Text(def.code),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getSeverityColor(def.severity).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                def.severity.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _getSeverityColor(def.severity),
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                def.description,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (def.cause != null) ...[
                Text('Cause:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
                Text(def.cause!),
                const SizedBox(height: 12),
              ],
              if (def.symptoms != null) ...[
                Text('Symptoms:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
                Text(def.symptoms!),
                const SizedBox(height: 12),
              ],
              if (def.possibleFixes.isNotEmpty) ...[
                Text('Possible Fixes:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[700])),
                ...def.possibleFixes.map((fix) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(fix)),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
