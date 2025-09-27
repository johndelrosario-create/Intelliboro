import 'package:flutter/material.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'package:intelliboro/repository/task_history_repository.dart';
import 'package:intelliboro/views/create_task_view.dart';
import 'dart:developer' as developer;

class TaskModelListView extends StatefulWidget {
  const TaskModelListView({Key? key}) : super(key: key);

  @override
  _TaskModelListViewState createState() => _TaskModelListViewState();
}

class _TaskModelListViewState extends State<TaskModelListView> {
  List<TaskModel> _tasks = [];
  bool _isLoading = false;
  String? _errorMessage;
  final TaskRepository _taskRepository = TaskRepository();
  final TaskHistoryRepository _taskHistoryRepository = TaskHistoryRepository();
  final Map<int, String> _taskTimeCache = {}; // Cache for task time strings

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tasks = await _taskRepository.getTasks();
      setState(() {
        _tasks = tasks;
        // Sort by effective priority (highest first)
        _tasks.sort(TaskModel.compareByEffectivePriority);
      });

      // Load time data for all tasks
      await _loadTaskTimes();

      developer.log('[TaskModelListView] Loaded ${_tasks.length} tasks.');
    } catch (e, stackTrace) {
      developer.log(
        '[TaskModelListView] Error loading tasks',
        error: e,
        stackTrace: stackTrace,
      );
      setState(() {
        _errorMessage = "Failed to load tasks: ${e.toString()}";
        _tasks = [];
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Load time tracking data for all tasks
  Future<void> _loadTaskTimes() async {
    try {
      _taskTimeCache.clear();

      for (final task in _tasks) {
        if (task.id != null) {
          final timeString = await _taskHistoryRepository.getFormattedTotalTime(
            task.id!,
          );
          _taskTimeCache[task.id!] = timeString;
        }
      }

      if (mounted) {
        setState(() {}); // Refresh UI with loaded time data
      }
    } catch (e) {
      developer.log('[TaskModelListView] Error loading task times: $e');
    }
  }

  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.lightGreen;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.deepOrange;
      case 5:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getPriorityIcon(int priority) {
    switch (priority) {
      case 1:
        return Icons.low_priority;
      case 2:
        return Icons.trending_down;
      case 3:
        return Icons.trending_flat;
      case 4:
        return Icons.trending_up;
      case 5:
        return Icons.priority_high;
      default:
        return Icons.help_outline;
    }
  }

  String _getTimeUntilTask(TaskModel task) {
    final now = DateTime.now();
    final taskDateTime = DateTime(
      task.taskDate.year,
      task.taskDate.month,
      task.taskDate.day,
      task.taskTime.hour,
      task.taskTime.minute,
    );

    final difference = taskDateTime.difference(now);

    if (difference.isNegative) {
      final overdue = -difference.inHours;
      if (overdue < 24) {
        return 'Overdue by ${overdue}h';
      } else {
        return 'Overdue by ${overdue ~/ 24}d';
      }
    } else if (difference.inHours < 1) {
      return 'Due in ${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return 'Due in ${difference.inHours}h';
    } else {
      return 'Due in ${difference.inDays}d';
    }
  }

  Widget _buildTaskCard(TaskModel task) {
    final priorityColor = _getPriorityColor(task.taskPriority);
    final priorityIcon = _getPriorityIcon(task.taskPriority);
    final timeUntil = _getTimeUntilTask(task);
    final effectivePriority = task.getEffectivePriority();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: task.isCompleted ? 1 : 3,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: priorityColor, width: 3),
        ),
        child: ListTile(
          leading: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(priorityIcon, color: priorityColor, size: 24),
              Text(
                '${task.taskPriority}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: priorityColor,
                ),
              ),
            ],
          ),
          title: Text(
            task.taskName,
            style: TextStyle(
              decoration: task.isCompleted ? TextDecoration.lineThrough : null,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${task.priorityString} Priority • $timeUntil',
                style: TextStyle(
                  color: task.isCompleted ? Colors.grey : priorityColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${task.taskTime.format(context)} on ${task.taskDate.day}/${task.taskDate.month}/${task.taskDate.year}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Effective Priority: ${effectivePriority.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  // Display time tracking info
                  if (task.id != null && _taskTimeCache.containsKey(task.id!))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            task.isCompleted
                                ? Colors.green.withOpacity(0.1)
                                : Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              task.isCompleted
                                  ? Colors.green.withOpacity(0.3)
                                  : Colors.blue.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 10,
                            color:
                                task.isCompleted
                                    ? Colors.green[700]
                                    : Colors.blue[700],
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _taskTimeCache[task.id!]!,
                            style: TextStyle(
                              fontSize: 9,
                              color:
                                  task.isCompleted
                                      ? Colors.green[700]
                                      : Colors.blue[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (task.isRecurring)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.repeat, color: Colors.blue[700], size: 12),
                      const SizedBox(width: 2),
                      Text(
                        task.recurringShortDescription,
                        style: TextStyle(
                          fontSize: 8,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  task.isCompleted
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: task.isCompleted ? Colors.green : Colors.grey,
                ),
                onPressed: () {
                  // TODO: Toggle task completion
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Task completion toggle not yet implemented',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          onTap: () {
            // TODO: Edit task
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Task editing not yet implemented')),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks by Priority'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'sort_priority') {
                setState(() {
                  _tasks.sort(TaskModel.compareByEffectivePriority);
                });
              } else if (value == 'sort_name') {
                setState(() {
                  _tasks.sort((a, b) => a.taskName.compareTo(b.taskName));
                });
              } else if (value == 'sort_date') {
                setState(() {
                  _tasks.sort((a, b) {
                    final aDateTime = DateTime(
                      a.taskDate.year,
                      a.taskDate.month,
                      a.taskDate.day,
                      a.taskTime.hour,
                      a.taskTime.minute,
                    );
                    final bDateTime = DateTime(
                      b.taskDate.year,
                      b.taskDate.month,
                      b.taskDate.day,
                      b.taskTime.hour,
                      b.taskTime.minute,
                    );
                    return aDateTime.compareTo(bDateTime);
                  });
                });
              }
            },
            itemBuilder:
                (BuildContext context) => [
                  const PopupMenuItem<String>(
                    value: 'sort_priority',
                    child: Text('Sort by Priority'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'sort_name',
                    child: Text('Sort by Name'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'sort_date',
                    child: Text('Sort by Date'),
                  ),
                ],
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_isLoading && _tasks.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Error: $_errorMessage',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadTasks,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (_tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.task_alt, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No tasks yet',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a task with a priority level to get started!',
                    style: TextStyle(color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (context) => const TaskCreation(showMap: true),
                        ),
                      ).then((_) => _loadTasks());
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create First Task'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _loadTasks,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tasks sorted by effective priority (user priority + urgency)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      Text(
                        '${_tasks.where((t) => !t.isCompleted).length} active',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) {
                      final task = _tasks[index];
                      return _buildTaskCard(task);
                    },
                  ),
                ),
              ],
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
          ).then((_) => _loadTasks());
        },
        tooltip: 'Create New Task',
        child: const Icon(Icons.add),
      ),
    );
  }
}
