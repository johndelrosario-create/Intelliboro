import 'package:flutter/material.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/views/create_task_view.dart';
import 'package:intelliboro/viewModel/task_list_viewmodel.dart';
import 'dart:developer' as developer;

// Placeholder for EditTaskView - will be created later
import 'edit_task_view.dart';

class TaskListView extends StatefulWidget {
  const TaskListView({Key? key}) : super(key: key);

  @override
  _TaskListViewState createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView> {
  late final TaskListViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = TaskListViewModel();
    _viewModel.addListener(_onViewModelChanged);
    _viewModel.loadTasks(); // Initial load
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {}); // Rebuild the widget when view model changes
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks & Geofences')),
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
