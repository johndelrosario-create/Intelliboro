import 'package:flutter/material.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'package:intelliboro/repository/task_history_repository.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:intelliboro/views/notification_history_view.dart';
import 'package:intelliboro/views/create_task_view.dart';
import 'package:intelliboro/views/active_task_view.dart';
import 'package:intelliboro/views/task_statistics_view.dart';
import 'package:intelliboro/viewmodel/notification_history_viewmodel.dart';
import 'package:intelliboro/widgets/task_timer_widget.dart';
import 'dart:developer' as developer;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// Sorting modes for the task list
enum TaskSortMode {
  priority, // Effective priority (existing default)
  alphabetical, // A-Z by task name
  creationDate, // Newest first
}

class TaskListView extends StatefulWidget {
  const TaskListView({Key? key}) : super(key: key);

  @override
  _TaskListViewState createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView>
    with TickerProviderStateMixin {
  List<TaskModel> _tasks = [];
  bool _isLoading = false;
  String? _errorMessage;
  final TaskRepository _taskRepository = TaskRepository();
  final TaskHistoryRepository _taskHistoryRepository = TaskHistoryRepository();
  final TaskTimerService _taskTimerService = TaskTimerService();
  late final NotificationHistoryViewModel _notificationHistoryViewModel;
  late AnimationController _fabAnimationController;
  late Animation<double> _fabAnimation;
  final Map<int, String> _taskTimeCache = {}; // Cache for task time strings
  Timer? _pendingRefreshTimer;
  StreamSubscription? _switchSubscription;
  TaskSortMode _sortMode = TaskSortMode.priority;
  static const _prefsSortKey = 'task_sort_mode';

  @override
  void initState() {
    super.initState();
    _loadSortMode();
    _loadTasks();

    _notificationHistoryViewModel = NotificationHistoryViewModel();
    _notificationHistoryViewModel.addListener(
      _onNotificationHistoryViewModelChanged,
    );
    developer.log(
      '[_TaskListViewState.initState] Calling _notificationHistoryViewModel.loadHistory()',
    );
    _notificationHistoryViewModel.loadHistory();

    // Listen to task timer service for UI updates
    _taskTimerService.addListener(_onTaskTimerChanged);
    // Listen for persisted task changes and refresh list
    _taskTimerService.tasksChanged.addListener(_onTasksChanged);

    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fabAnimationController, curve: Curves.easeInOut),
    );
    _fabAnimationController.forward();

    // Start a lightweight timer to refresh UI while any task is pending so remaining snooze labels update
    _pendingRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // If there are any pending tasks, trigger a rebuild
      if (_tasks.any(
        (t) => t.id != null && _taskTimerService.isPending(t.id!),
      )) {
        if (mounted) setState(() {});
      }
    });

    // Subscribe to switch requests coming from TaskTimerService
    _switchSubscription = _taskTimerService.switchRequests.listen((req) {
      if (!mounted) return;
      _showSwitchDialog(req);
    });
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tasks = await _taskRepository.getTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _applySorting();
      });

      // Load time data for all tasks
      await _loadTaskTimes();

      developer.log('[TaskListView] Loaded ${_tasks.length} tasks.');
    } catch (e, stackTrace) {
      developer.log(
        '[TaskListView] Error loading tasks',
        error: e,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _errorMessage = "Failed to load tasks: ${e.toString()}";
        _tasks = [];
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Load time tracking data for all tasks
  Future<void> _loadTaskTimes() async {
    try {
      _taskTimeCache.clear();

      // Collect all task IDs
      final taskIds =
          _tasks
              .where((task) => task.id != null)
              .map((task) => task.id!)
              .toList();

      if (taskIds.isEmpty) return;

      // Batch load all times in a single query
      final times = await _taskHistoryRepository.getBatchFormattedTotalTimes(
        taskIds,
      );
      _taskTimeCache.addAll(times);

      if (mounted) {
        setState(() {}); // Refresh UI with loaded time data
      }

      developer.log(
        '[TaskListView] Batch loaded times for ${taskIds.length} tasks',
      );
    } catch (e) {
      developer.log('[TaskListView] Error loading task times: $e');
    }
  }

  void _onNotificationHistoryViewModelChanged() {
    if (mounted) {
      developer.log(
        '[_TaskListViewState._onNotificationHistoryViewModelChanged] setState called. Notification count: ${_notificationHistoryViewModel.history.length}',
      );
      setState(() {});
    }
  }

  void _onTaskTimerChanged() {
    if (mounted) {
      developer.log(
        '[_TaskListViewState._onTaskTimerChanged] Task timer state changed. Active task: ${_taskTimerService.activeTask?.taskName}',
      );
      setState(() {}); // Rebuild UI to reflect timer state changes
    }
  }

  @override
  void dispose() {
    _notificationHistoryViewModel.removeListener(
      _onNotificationHistoryViewModelChanged,
    );
    _notificationHistoryViewModel.dispose();
    _taskTimerService.removeListener(_onTaskTimerChanged);
    _taskTimerService.tasksChanged.removeListener(_onTasksChanged);
    _pendingRefreshTimer?.cancel();
    _switchSubscription?.cancel();
    _fabAnimationController.dispose();
    super.dispose();
  }

  void _onTasksChanged() {
    if (_taskTimerService.tasksChanged.value) {
      _loadTasks();
      _taskTimerService.tasksChanged.value = false;
    }
  }

  Future<void> _showSwitchDialog(dynamic reqDynamic) async {
    // Accept TaskSwitchRequest or any object implementing newTask & respond
    try {
      final req =
          reqDynamic as dynamic; // keep loose typing to avoid import cycles
      final newTask = req.newTask as TaskModel;
      final active = _taskTimerService.activeTask;

      final choice = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: Text('Switch to "${newTask.taskName}"?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (active != null)
                  Text(
                    'Current: ${active.taskName} (priority ${active.taskPriority})',
                  ),
                const SizedBox(height: 8),
                Text(
                  'Incoming: ${newTask.taskName} (priority ${newTask.taskPriority})',
                ),
                const SizedBox(height: 12),
                Text(
                  'Do you want to start the incoming task now or snooze it?',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Snooze'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Start Now'),
              ),
            ],
          );
        },
      );

      final startNow = choice == true;
      // Respond to the request
      try {
        req.respond(startNow);
      } catch (e) {
        developer.log('[TaskListView] Failed to respond to switch request: $e');
      }

      if (startNow) {
        try {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ActiveTaskView()),
            (r) => false,
          );
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Switched to "${newTask.taskName}"')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Snoozed "${newTask.taskName}" for ${_taskTimerService.defaultSnoozeDuration.inMinutes} minutes',
              ),
            ),
          );
        }
      }
    } catch (e, st) {
      developer.log(
        '[TaskListView] _showSwitchDialog error: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  Color _getPriorityColor(int priority) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    switch (priority) {
      case 1:
        return const Color(0xFF1B5E20); // Very Low - Darker green 900 (better contrast)
      case 2:
        return const Color(0xFF827717); // Low - Darker lime 900 (better contrast)
      case 3:
        return const Color(0xFFFFCA28); // Medium - Lighter amber 400 (brighter yellow)
      case 4:
        return const Color(0xFFFF6F00); // High - Bright orange 900
      case 5:
        return const Color(0xFFB71C1C); // Very High - Red 900 (better contrast)
      default:
        return colorScheme.outline;
    }
  }

  IconData _getPriorityIcon(int priority) {
    switch (priority) {
      case 1:
        return Icons.low_priority_rounded;
      case 2:
        return Icons.expand_more_rounded;
      case 3:
        return Icons.radio_button_unchecked_rounded;
      case 4:
        return Icons.expand_less_rounded;
      case 5:
        return Icons.priority_high_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  IconData _getTaskTriggerIcon(TaskModel task) {
    final hasTime = task.taskTime != null && task.taskDate != null;
    final hasGeofence = task.geofenceId != null;

    if (hasTime && hasGeofence) {
      // Both time and location triggers - use a hybrid icon
      return Icons
          .schedule_rounded; // Show time icon as primary, location is indicated in text
    } else if (hasGeofence) {
      // Only location trigger
      return Icons.place_rounded;
    } else if (hasTime) {
      // Only time trigger
      return Icons.schedule_rounded;
    } else {
      return Icons.help_outline_rounded;
    }
  }

  String _getTaskTriggerText(TaskModel task) {
    final hasTime = task.taskTime != null && task.taskDate != null;
    final hasGeofence = task.geofenceId != null;

    if (hasTime && hasGeofence) {
      // Both time and location triggers
      return '${task.taskTime!.format(context)} • ${task.taskDate!.day}/${task.taskDate!.month}/${task.taskDate!.year} + Location';
    } else if (hasGeofence) {
      // Only location trigger
      return 'Location-based task';
    } else if (hasTime) {
      // Only time trigger
      return '${task.taskTime!.format(context)} • ${task.taskDate!.day}/${task.taskDate!.month}/${task.taskDate!.year}';
    } else {
      return 'No trigger set';
    }
  }

  String _getTimeUntilTask(TaskModel task) {
    final hasTime = task.taskTime != null && task.taskDate != null;
    final hasGeofence = task.geofenceId != null;

    // For time-based tasks (with or without geofence), show time countdown
    if (hasTime) {
      final now = DateTime.now();
      final taskDateTime = DateTime(
        task.taskDate!.year,
        task.taskDate!.month,
        task.taskDate!.day,
        task.taskTime!.hour,
        task.taskTime!.minute,
      );

      final difference = taskDateTime.difference(now);

      String timeText;
      if (difference.isNegative) {
        final overdue = -difference.inHours;
        if (overdue < 24) {
          timeText = 'Overdue by ${overdue}h';
        } else {
          timeText = 'Overdue by ${overdue ~/ 24}d';
        }
      } else if (difference.inHours < 1) {
        timeText = 'Due in ${difference.inMinutes}m';
      } else if (difference.inHours < 24) {
        timeText = 'Due in ${difference.inHours}h';
      } else {
        timeText = 'Due in ${difference.inDays}d';
      }

      // Add location indicator if it also has geofence
      return hasGeofence ? '$timeText + 📍' : timeText;
    }

    // Handle geofence-only tasks
    if (hasGeofence) {
      return 'Location-based';
    }

    return 'No schedule';
  }

  Widget _buildTaskCard(TaskModel task) {
    final theme = Theme.of(context);
    final priorityColor = _getPriorityColor(task.taskPriority);
    final priorityIcon = _getPriorityIcon(task.taskPriority);
    final timeUntil = _getTimeUntilTask(task);
    final effectivePriority = task.getEffectivePriority();
    // Pending state info (snoozed due to lower priority)
    final Duration? _pendingRemaining =
        (task.id != null)
            ? _taskTimerService.getPendingRemaining(task.id!)
            : null;
    final String _pendingLabel =
        _pendingRemaining != null
            ? (_pendingRemaining.inMinutes > 0
                ? 'PENDING • ${_pendingRemaining.inMinutes}m'
                : 'PENDING • ${_pendingRemaining.inSeconds}s')
            : 'PENDING';

    // Check if this task is currently active in the timer
    final isActiveTimer =
        _taskTimerService.hasActiveTask &&
        _taskTimerService.activeTask?.id == task.id;

    return Card.filled(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Container(
        decoration:
            isActiveTimer
                ? BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                )
                : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Open editor for the task
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) => TaskCreation(showMap: true, initialTask: task),
              ),
            ).then((_) => _loadTasks());
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: priorityColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Icon(priorityIcon, color: priorityColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  task.taskName,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    decoration:
                                        task.isCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Show active timer indicator
                              if (isActiveTimer) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.timer,
                                        size: 12,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        'ACTIVE',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color:
                                                  theme.colorScheme.onPrimary,
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              // Show pending indicator when task is snoozed (and not active)
                              if (!isActiveTimer &&
                                  task.id != null &&
                                  _taskTimerService.isPending(task.id!)) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.tertiaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.pause_circle_outline,
                                        size: 12,
                                        color:
                                            theme
                                                .colorScheme
                                                .onTertiaryContainer,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _pendingLabel,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color:
                                                  theme
                                                      .colorScheme
                                                      .onTertiaryContainer,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${task.priorityString} Priority',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: priorityColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (task.isRecurring)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.repeat_rounded,
                              size: 14,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              task.recurringShortDescription,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getTaskTriggerIcon(task),
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getTaskTriggerText(task),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: priorityColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: priorityColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          timeUntil,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: priorityColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Effective Priority: ${effectivePriority.toStringAsFixed(1)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    // Display time tracking info
                    if (task.id != null && _taskTimeCache.containsKey(task.id!))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color:
                              task.isCompleted
                                  ? theme.colorScheme.tertiaryContainer
                                  : theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                task.isCompleted
                                    ? theme.colorScheme.tertiary.withValues(
                                      alpha: 0.3,
                                    )
                                    : theme.colorScheme.secondary.withValues(
                                      alpha: 0.3,
                                    ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color:
                                  task.isCompleted
                                      ? theme.colorScheme.onTertiaryContainer
                                      : theme.colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _taskTimeCache[task.id!]!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color:
                                    task.isCompleted
                                        ? theme.colorScheme.onTertiaryContainer
                                        : theme
                                            .colorScheme
                                            .onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    IconButton.filledTonal(
                      onPressed: () async {
                        // Toggle completion status with proper cleanup
                        try {
                          if (!task.isCompleted) {
                            // Mark as completed with proper alarm/notification cleanup
                            await _taskTimerService.completeTaskManually(task);
                          } else {
                            // Mark as incomplete (simple database update)
                            final updated = task.copyWith(isCompleted: false);
                            await TaskRepository().updateTask(updated);
                            _taskTimerService.tasksChanged.value = true;
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to update task: $e'),
                            ),
                          );
                        }
                      },
                      icon: Icon(
                        task.isCompleted
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color:
                            task.isCompleted
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                      ),
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      onPressed: () async {
                        // Confirm delete
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: const Text('Delete task?'),
                              content: Text(
                                'Are you sure you want to delete "${task.taskName}"? This cannot be undone.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed:
                                      () => Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed:
                                      () => Navigator.of(context).pop(true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            );
                          },
                        );

                        if (confirm == true) {
                          try {
                            // Keep a copy for undo (new insert will get a new ID)
                            final deletedCopy = task.copyWith(id: null);

                            // Stop any in-memory running timer for this task
                            if (task.id != null &&
                                _taskTimerService.isRunning(task.id!)) {
                              await _taskTimerService.stopTimerForTask(
                                task.id!,
                              );
                            }
                            if (task.id != null) {
                              await TaskRepository().deleteTask(task.id!);
                            }
                            // Notify listeners to refresh
                            _taskTimerService.tasksChanged.value = true;

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Deleted "${task.taskName}"'),
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    onPressed: () async {
                                      try {
                                        await TaskRepository().insertTask(
                                          deletedCopy,
                                        );
                                        _taskTimerService.tasksChanged.value =
                                            true;
                                      } catch (e) {
                                        developer.log(
                                          '[TaskListView] Undo insert failed: $e',
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text('Undo failed: $e'),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            developer.log(
                              '[TaskListView] Error deleting task: $e',
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to delete task: $e'),
                                ),
                              );
                            }
                          }
                        }
                      },
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: theme.colorScheme.error,
                      ),
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.task_alt_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Ready to get organized?',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first task with a priority level and location to get started with smart reminders.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TaskCreation(showMap: true),
                  ),
                ).then((_) => _loadTasks());
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create First Task'),
            ),
          ],
        ),
      ),
    );
  }

  /// Apply sorting to the in-memory _tasks list based on current _sortMode
  void _applySorting() {
    switch (_sortMode) {
      case TaskSortMode.priority:
        _tasks.sort(TaskModel.compareByEffectivePriority);
        break;
      case TaskSortMode.alphabetical:
        _tasks.sort(TaskModel.compareByName);
        break;
      case TaskSortMode.creationDate:
        _tasks.sort(TaskModel.compareByCreatedAt);
        break;
    }
  }

  /// Load the saved sort mode from SharedPreferences
  Future<void> _loadSortMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final idx = prefs.getInt(_prefsSortKey);
      if (idx != null && idx >= 0 && idx < TaskSortMode.values.length) {
        setState(() {
          _sortMode = TaskSortMode.values[idx];
        });
      }
    } catch (e) {
      developer.log('[TaskListView] Failed to load sort mode: $e');
    }
  }

  /// Persist the selected sort mode
  Future<void> _saveSortMode(TaskSortMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsSortKey, mode.index);
    } catch (e) {
      developer.log('[TaskListView] Failed to save sort mode: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    developer.log(
      '[_TaskListViewState.build] Building. Notification count: ${_notificationHistoryViewModel.history.length}, IsLoading: ${_notificationHistoryViewModel.isLoading}',
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'My Tasks',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 8,
        actions: [
          PopupMenuButton<TaskSortMode>(
            tooltip: 'Sort tasks',
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sortMode,
            onSelected: (mode) async {
              setState(() {
                _sortMode = mode;
                _applySorting();
              });
              await _saveSortMode(mode);
            },
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    value: TaskSortMode.priority,
                    child: Row(
                      children: const [
                        Icon(Icons.priority_high_rounded),
                        SizedBox(width: 8),
                        Text('By Priority'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: TaskSortMode.alphabetical,
                    child: Row(
                      children: const [
                        Icon(Icons.sort_by_alpha_rounded),
                        SizedBox(width: 8),
                        Text('Alphabetical'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: TaskSortMode.creationDate,
                    child: Row(
                      children: const [
                        Icon(Icons.schedule_rounded),
                        SizedBox(width: 8),
                        Text('Newest First'),
                      ],
                    ),
                  ),
                ],
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.notifications_rounded),
            tooltip: 'Notification History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationHistoryView(),
                ),
              ).then((_) {
                _notificationHistoryViewModel.loadHistory();
              });
            },
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Task Statistics',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TaskStatisticsView(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Builder(
            builder: (context) {
              if (_isLoading && _tasks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading your tasks...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (_errorMessage != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 64,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Oops! Something went wrong',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _loadTasks,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Show empty state only if there are truly no tasks at all
              if (_tasks.isEmpty) {
                return _buildEmptyState();
              }

              // Exclude tasks that are currently paused from the Active list
              final pausedIds =
                  _taskTimerService.pausedTasks
                      .where((t) => t.id != null)
                      .map((t) => t.id!)
                      .toSet();
              final activeTasks =
                  _tasks
                      .where(
                        (t) =>
                            !t.isCompleted &&
                            (t.id == null || !pausedIds.contains(t.id!)),
                      )
                      .toList();
              final completedTasks =
                  _tasks.where((t) => t.isCompleted).toList();

              // If we have tasks but all are completed, still show the normal layout
              return RefreshIndicator(
                onRefresh: _loadTasks,
                child: CustomScrollView(
                  slivers: [
                    // Always show some top spacing
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                    if (activeTasks.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.pending_actions_rounded,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Active Tasks (${activeTasks.length})',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _sortMode == TaskSortMode.priority
                                      ? 'Priority sorted'
                                      : _sortMode == TaskSortMode.alphabetical
                                      ? 'Alphabetical'
                                      : 'Newest first',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildTaskCard(activeTasks[index]),
                          childCount: activeTasks.length,
                        ),
                      ),
                    ],
                    // Paused tasks section
                    if (_taskTimerService.pausedTasks.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.pause_circle_outline_rounded,
                                color: theme.colorScheme.tertiary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Paused (${_taskTimerService.pausedTasks.length})',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.tertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final t = _taskTimerService.pausedTasks[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.pause_rounded),
                              title: Text(t.taskName),
                              subtitle: const Text(
                                'Paused due to interruption',
                              ),
                              trailing: FilledButton.tonalIcon(
                                onPressed: () async {
                                  final id = t.id;
                                  if (id == null) return;
                                  final ok = await _taskTimerService
                                      .resumePausedTask(id);
                                  if (ok && mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const ActiveTaskView(),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Resume'),
                              ),
                            ),
                          );
                        }, childCount: _taskTimerService.pausedTasks.length),
                      ),
                    ],
                    // Show a message when there are no active tasks
                    if (activeTasks.isEmpty && completedTasks.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.celebration_rounded,
                                  size: 48,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'All tasks completed! 🎉',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Great job! Create a new task to keep being productive.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (completedTasks.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                color: theme.colorScheme.outline,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Completed (${completedTasks.length})',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildTaskCard(completedTasks[index]),
                          childCount: completedTasks.length,
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 100), // Space for FAB
                    ),
                  ],
                ),
              );
            },
          ),
          // Floating task timer widget
          const TaskTimerWidget(),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabAnimation,
        child: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TaskCreation(showMap: true),
              ),
            ).then((_) => _loadTasks());
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('New Task'),
          tooltip: 'Create New Task',
        ),
      ),
    );
  }
}
