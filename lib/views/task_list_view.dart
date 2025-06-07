import 'package:flutter/material.dart';
import 'package:intelliboro/viewModel/task_list_viewmodel.dart';
import 'dart:developer' as developer;
import 'package:intelliboro/views/notification_history_view.dart';
import 'package:intelliboro/views/create_task_view.dart'; // Add this import
import 'package:intelliboro/viewModel/notification_history_viewmodel.dart';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

class TaskListView extends StatefulWidget {
  const TaskListView({Key? key}) : super(key: key);

  @override
  _TaskListViewState createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView> {
  static const String _notificationUpdatePortName = 'notification_update_port';
  ReceivePort? _notificationUpdatePort;
  late final TaskListViewModel _viewModel;
  late final NotificationHistoryViewModel _notificationHistoryViewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = TaskListViewModel();
    _viewModel.addListener(_onViewModelChanged); // Keep this for TaskListViewModel
    _viewModel.loadTasks(); // Initial load

    _notificationHistoryViewModel = NotificationHistoryViewModel();
    _notificationHistoryViewModel.addListener(_onNotificationHistoryViewModelChanged); // Specific listener
    developer.log('[_TaskListViewState.initState] Calling _notificationHistoryViewModel.loadHistory()');
    _notificationHistoryViewModel.loadHistory(); // Load notification history

    // Setup ReceivePort for background updates
    _notificationUpdatePort = ReceivePort();
    final portRegistered = IsolateNameServer.registerPortWithName(
      _notificationUpdatePort!.sendPort,
      _notificationUpdatePortName,
    );
    if (portRegistered) {
      developer.log('[_TaskListViewState.initState] Notification update port registered: $_notificationUpdatePortName');
    } else {
       // If registration fails, try removing and re-registering
      IsolateNameServer.removePortNameMapping(_notificationUpdatePortName);
      final retryRegistered = IsolateNameServer.registerPortWithName(
        _notificationUpdatePort!.sendPort,
        _notificationUpdatePortName,
      );
      if (retryRegistered) {
        developer.log('[_TaskListViewState.initState] Notification update port registered on retry: $_notificationUpdatePortName');
      } else {
        developer.log('[_TaskListViewState.initState] CRITICAL: Failed to register notification update port even after retry: $_notificationUpdatePortName');
      }
    }

    _notificationUpdatePort!.listen((dynamic message) {
      developer.log('[_TaskListViewState.initState] Received message on notification update port: $message');
      if (message == 'update_history') {
        _notificationHistoryViewModel.loadHistory();
      }
    });
  }

  void _onViewModelChanged() { // This listener is for _viewModel (TaskListViewModel)
    if (mounted) {
      developer.log('[_TaskListViewState._onViewModelChanged] (for TaskList) setState called.');
      setState(() {}); // Rebuild the widget when view model changes
    }
  }

  void _onNotificationHistoryViewModelChanged() {
    if (mounted) {
      developer.log(
        '[_TaskListViewState._onNotificationHistoryViewModelChanged] setState called. Notification count: ${_notificationHistoryViewModel.history.length}',
      );
      setState(() {});
    } else {
      developer.log(
        '[_TaskListViewState._onNotificationHistoryViewModelChanged] Called but not mounted. Notification count: ${_notificationHistoryViewModel.history.length}',
      );
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();

    _notificationHistoryViewModel.removeListener(_onNotificationHistoryViewModelChanged);
    _notificationHistoryViewModel.dispose();

    // Dispose ReceivePort
    developer.log('[_TaskListViewState.dispose] Removing notification update port mapping: $_notificationUpdatePortName');
    IsolateNameServer.removePortNameMapping(_notificationUpdatePortName);
    _notificationUpdatePort?.close();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    developer.log(
      '[_TaskListViewState.build] Building. Notification count: ${_notificationHistoryViewModel.history.length}, IsLoading: ${_notificationHistoryViewModel.isLoading}',
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks & Geofences'),
        actions: [
          Stack(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.notifications),
                tooltip: 'Notification History',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationHistoryView(),
                    ),
                  ).then((_) {
                    // Refresh history count when returning from NotificationHistoryView
                    _notificationHistoryViewModel.loadHistory();
                  });
                },
              ),
              if (_notificationHistoryViewModel.history.isNotEmpty)
                Positioned(
                  right: 11,
                  top: 11,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 12,
                      minHeight: 12,
                    ),
                    child: Text(
                      _notificationHistoryViewModel.history.length > 9
                          ? '9+'
                          : _notificationHistoryViewModel.history.length.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_viewModel.isLoading && _viewModel.tasks.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_viewModel.errorMessage != null) {
            return Center(
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
                    onPressed: () => _viewModel.loadTasks(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (_viewModel.tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No tasks yet. Create one!'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _viewModel.loadTasks(),
                    child: const Text('Refresh'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _viewModel.loadTasks,
            child: ListView.builder(
              itemCount: _viewModel.tasks.length,
              itemBuilder: (context, index) {
                final task = _viewModel.tasks[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    title: Text(task.task ?? 'Untitled Task'),
                    subtitle: Text(
                      'ID: ${task.id}\nLat: ${task.latitude.toStringAsFixed(3)}, Lon: ${task.longitude.toStringAsFixed(3)}, Radius: ${task.radiusMeters}m',
                    ),
                    isThreeLine: true,
                    onTap: () {
                      developer.log('Tapped on task: ${task.id}');
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => EditTaskView(geofenceId: task.id),
                        ),
                      ).then((result) {
                        if (result == true) {
                          _viewModel.loadTasks();
                        }
                      });
                    },
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder:
                              (BuildContext dialogContext) => AlertDialog(
                                title: const Text('Delete Task?'),
                                content: Text(
                                  'Are you sure you want to delete "${task.task ?? 'this task'}"? This will also remove its geofence.',
                                ),
                                actions: <Widget>[
                                  TextButton(
                                    child: const Text('Cancel'),
                                    onPressed:
                                        () => Navigator.of(
                                          dialogContext,
                                        ).pop(false),
                                  ),
                                  TextButton(
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                    onPressed:
                                        () => Navigator.of(
                                          dialogContext,
                                        ).pop(true),
                                  ),
                                ],
                              ),
                        );
                        if (confirm == true) {
                          await _viewModel.deleteTask(task.id);
                          if (mounted && _viewModel.errorMessage != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_viewModel.errorMessage!),
                                backgroundColor: Colors.red,
                              ),
                            );
                          } else if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Task "${task.task ?? 'Untitled Task'}" deleted.',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const TaskCreation(showMap: true),
            ),
          ).then((_) {
            _viewModel.loadTasks();
          });
        },
        tooltip: 'Create New Task',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Dummy EditTaskView for now, to be replaced later
class EditTaskView extends StatelessWidget {
  final String geofenceId;
  const EditTaskView({Key? key, required this.geofenceId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit Task $geofenceId')),
      body: Center(
        child: Text(
          'Editing details for geofence ID: $geofenceId.\nImplementation pending.',
        ),
      ),
    );
  }
}
