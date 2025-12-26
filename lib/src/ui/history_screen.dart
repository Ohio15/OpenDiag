import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../services/recording_service.dart';
import '../services/vehicle_profile_service.dart';
import '../services/report_service.dart';
import 'theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _recordingService = RecordingService();
  final _vehicleService = VehicleProfileService();
  final _reportService = ReportService();

  List<SessionSummary> _sessions = [];
  List<VehicleProfile> _vehicles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await _recordingService.getAllSessions();
      final vehicles = await _vehicleService.getAllVehicles();
      setState(() {
        _sessions = sessions;
        _vehicles = vehicles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Sessions', icon: Icon(Icons.history)),
            Tab(text: 'Vehicles', icon: Icon(Icons.directions_car)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSessionsTab(),
                _buildVehiclesTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddVehicleDialog,
        child: const Icon(Icons.add),
        tooltip: 'Add Vehicle',
      ),
    );
  }

  Widget _buildSessionsTab() {
    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No Sessions Yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Start a recording from the Dashboard',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _sessions.length,
      itemBuilder: (context, index) {
        final session = _sessions[index];
        return _buildSessionCard(session);
      },
    );
  }

  Widget _buildSessionCard(SessionSummary session) {
    final duration = session.duration;
    final durationText = duration != null
        ? '${duration.inMinutes}m ${duration.inSeconds % 60}s'
        : 'In Progress';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showSessionDetails(session),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDate(session.startTime),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: session.endTime != null
                          ? Colors.green.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      session.endTime != null ? 'Completed' : 'Active',
                      style: TextStyle(
                        fontSize: 12,
                        color: session.endTime != null ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.timer, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(durationText, style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(width: 16),
                  if (session.mileage != null) ...[
                    Icon(Icons.speed, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text('${session.mileage} km', style: TextStyle(color: Colors.grey[600])),
                  ],
                ],
              ),
              if (session.notes != null && session.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  session.notes!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehiclesTab() {
    if (_vehicles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No Vehicles',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add a vehicle profile',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _vehicles.length,
      itemBuilder: (context, index) {
        final vehicle = _vehicles[index];
        return _buildVehicleCard(vehicle);
      },
    );
  }

  Widget _buildVehicleCard(VehicleProfile vehicle) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showVehicleDetails(vehicle),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.directions_car,
                  color: AppTheme.primaryColor,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle.displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (vehicle.vin != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'VIN: ${vehicle.vin}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (vehicle.year != null || vehicle.make != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (vehicle.year != null) vehicle.year.toString(),
                          vehicle.make,
                          vehicle.model,
                        ].whereType<String>().join(' '),
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
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

  void _showSessionDetails(SessionSummary session) async {
    final details = await _recordingService.getSessionDetails(session.id);
    if (details == null || !mounted) return;

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
              Text(
                'Session Details',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildDetailRow('Start Time', _formatDateTime(session.startTime)),
              if (session.endTime != null)
                _buildDetailRow('End Time', _formatDateTime(session.endTime!)),
              if (session.duration != null)
                _buildDetailRow('Duration', _formatDuration(session.duration!)),
              if (session.mileage != null)
                _buildDetailRow('Mileage', '${session.mileage} km'),
              const SizedBox(height: 16),
              _buildDetailRow('DTCs Recorded', details.dtcs.length.toString()),
              _buildDetailRow('Data Points', details.dataPoints.length.toString()),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _exportSession(details),
                      icon: const Icon(Icons.download),
                      label: const Text('Export CSV'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _generateReport(details),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF Report'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _deleteSession(session.id),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Delete Session', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVehicleDetails(VehicleProfile vehicle) async {
    final history = await _vehicleService.getVehicleHistory(vehicle.id);

    if (!mounted) return;

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
              Text(
                vehicle.displayName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (vehicle.vin != null)
                _buildDetailRow('VIN', vehicle.vin!),
              if (vehicle.year != null)
                _buildDetailRow('Year', vehicle.year.toString()),
              if (vehicle.make != null)
                _buildDetailRow('Make', vehicle.make!),
              if (vehicle.model != null)
                _buildDetailRow('Model', vehicle.model!),
              if (vehicle.engine != null)
                _buildDetailRow('Engine', vehicle.engine!),
              if (vehicle.transmission != null)
                _buildDetailRow('Transmission', vehicle.transmission!),
              const SizedBox(height: 16),
              Text(
                'Statistics',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildDetailRow('Total Sessions', history.totalSessions.toString()),
              _buildDetailRow('Total DTCs Found', history.totalDtcs.toString()),
              _buildDetailRow('Data Points', history.totalDataPoints.toString()),
              _buildDetailRow('Total Time', history.formattedTotalTime),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _deleteVehicle(vehicle),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Delete Vehicle', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddVehicleDialog() {
    final vinController = TextEditingController();
    final nicknameController = TextEditingController();
    final makeController = TextEditingController();
    final modelController = TextEditingController();
    final yearController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Vehicle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nicknameController,
                decoration: const InputDecoration(
                  labelText: 'Nickname',
                  hintText: 'e.g., My Car',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: vinController,
                decoration: const InputDecoration(
                  labelText: 'VIN (optional)',
                  hintText: '17 characters',
                ),
                maxLength: 17,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: yearController,
                      decoration: const InputDecoration(labelText: 'Year'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: makeController,
                      decoration: const InputDecoration(labelText: 'Make'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelController,
                decoration: const InputDecoration(labelText: 'Model'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final year = int.tryParse(yearController.text);
              await _vehicleService.createVehicle(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                vin: vinController.text.isNotEmpty ? vinController.text : null,
                nickname: nicknameController.text.isNotEmpty ? nicknameController.text : null,
                make: makeController.text.isNotEmpty ? makeController.text : null,
                model: modelController.text.isNotEmpty ? modelController.text : null,
                year: year,
              );
              if (mounted) {
                Navigator.pop(context);
                _loadData();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportSession(SessionDetails details) async {
    try {
      final csv = await _recordingService.exportSessionToCsv(details.session.id);
      // For now, show the CSV in a dialog
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV exported successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _generateReport(SessionDetails details) async {
    try {
      final pdfBytes = await _reportService.generateReport(session: details);
      if (!mounted) return;
      Navigator.pop(context);

      // Show print preview
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: 'OpenDiag Report - ${_formatDate(details.session.startTime)}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report generation failed: $e')),
        );
      }
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: const Text('Are you sure you want to delete this session? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _recordingService.deleteSession(sessionId);
      if (mounted) {
        Navigator.pop(context);
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session deleted')),
        );
      }
    }
  }

  Future<void> _deleteVehicle(VehicleProfile vehicle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vehicle'),
        content: Text(
          'Are you sure you want to delete "${vehicle.displayName}"? '
          'This will also delete all associated sessions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _vehicleService.deleteVehicle(vehicle.id);
      if (mounted) {
        Navigator.pop(context);
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle deleted')),
        );
      }
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}
