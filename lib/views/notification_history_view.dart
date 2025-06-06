import 'package:flutter/material.dart';
import 'package:intelliboro/viewModel/notification_history_viewmodel.dart';
import 'package:timeago/timeago.dart' as timeago;

class NotificationHistoryView extends StatefulWidget {
  const NotificationHistoryView({Key? key}) : super(key: key);

  @override
  _NotificationHistoryViewState createState() =>
      _NotificationHistoryViewState();
}

class _NotificationHistoryViewState extends State<NotificationHistoryView> {
  late final NotificationHistoryViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = NotificationHistoryViewModel();
    _viewModel.addListener(_onViewModelChanged);
    _viewModel.loadHistory();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _confirmClearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Clear History?'),
            content: const Text(
              'Are you sure you want to delete all notification history? This action cannot be undone.',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              TextButton(
                child: const Text('Clear', style: TextStyle(color: Colors.red)),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
    );
    if (confirm == true) {
      await _viewModel.clearHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear History',
            onPressed: _viewModel.history.isEmpty ? null : _confirmClearHistory,
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_viewModel.isLoading && _viewModel.history.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_viewModel.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Error: ${_viewModel.errorMessage}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _viewModel.loadHistory(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (_viewModel.history.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No notification history yet.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _viewModel.loadHistory(),
                    child: const Text('Refresh'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _viewModel.loadHistory,
            child: ListView.builder(
              itemCount: _viewModel.history.length,
              itemBuilder: (context, index) {
                final record = _viewModel.history[index];
                final eventIcon =
                    record.eventType == 'enter'
                        ? const Icon(Icons.login, color: Colors.green)
                        : const Icon(Icons.logout, color: Colors.orange);
                final formattedTime = timeago.format(record.timestamp);

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    leading: eventIcon,
                    title: Text(
                      record.taskName ?? 'Geofence Alert',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(record.body),
                    trailing: Text(
                      formattedTime,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
