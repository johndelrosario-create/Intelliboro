import 'package:flutter/material.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'package:intelliboro/repository/task_history_repository.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:intelliboro/views/notification_history_view.dart';
import 'package:intelliboro/views/create_task_view.dart';
import 'package:intelliboro/viewModel/notification_history_viewmodel.dart';
import 'package:intelliboro/widgets/task_timer_widget.dart';
import 'dart:developer' as developer;

class TaskListView extends StatefulWidget {
  const TaskListView({Key? key}) : super(key: key);

  @override
  _TaskListViewState createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView> with TickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
    _loadTasks();

    _notificationHistoryViewModel = NotificationHistoryViewModel();
    _notificationHistoryViewModel.addListener(_onNotificationHistoryViewModelChanged);
    developer.log('[_TaskListViewState.initState] Calling _notificationHistoryViewModel.loadHistory()');
    _notificationHistoryViewModel.loadHistory();

    // Listen to task timer service for UI updates
    _taskTimerService.addListener(_onTaskTimerChanged);

    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fabAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _fabAnimationController.forward();
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
        _tasks.sort(TaskModel.compareByEffectivePriority);
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
          final timeString = await _taskHistoryRepository.getFormattedTotalTime(task.id!);
          _taskTimeCache[task.id!] = timeString;
        }
      }
      
      if (mounted) {
        setState(() {}); // Refresh UI with loaded time data
      }
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
    _notificationHistoryViewModel.removeListener(_onNotificationHistoryViewModelChanged);
    _notificationHistoryViewModel.dispose();
    _taskTimerService.removeListener(_onTaskTimerChanged);
    _fabAnimationController.dispose();
    super.dispose();
  }

  Color _getPriorityColor(int priority) {
    final theme = Theme.of(context);
    switch (priority) {
      case 1:
        return theme.colorScheme.secondary;
      case 2:
        return theme.colorScheme.tertiary;
      case 3:
        return theme.colorScheme.primary;
      case 4:
        return theme.colorScheme.error;
      case 5:
        return theme.colorScheme.errorContainer;
      default:
        return theme.colorScheme.outline;
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
    final theme = Theme.of(context);
    final priorityColor = _getPriorityColor(task.taskPriority);
    final priorityIcon = _getPriorityIcon(task.taskPriority);
    final timeUntil = _getTimeUntilTask(task);
    final effectivePriority = task.getEffectivePriority();
    
    // Check if this task is currently active in the timer
    final isActiveTimer = _taskTimerService.hasActiveTask && 
                          _taskTimerService.activeTask?.id == task.id;
    
    return Card.filled(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Container(
        decoration: isActiveTimer ? BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ) : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // TODO: Navigate to task details/edit
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Edit "${task.taskName}" - Coming soon!'),
                behavior: SnackBarBehavior.floating,
              ),
            );
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
                      color: priorityColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: priorityColor.withOpacity(0.3)),
                    ),
                    child: Icon(
                      priorityIcon,
                      color: priorityColor,
                      size: 20,
                    ),
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
                                  decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Show active timer indicator
                            if (isActiveTimer) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onPrimary,
                                        fontSize: 8,
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
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: priorityColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (task.isRecurring)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${task.taskTime.format(context)} • ${task.taskDate.day}/${task.taskDate.month}/${task.taskDate.year}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: priorityColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: priorityColor.withOpacity(0.3)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: task.isCompleted 
                          ? theme.colorScheme.tertiaryContainer
                          : theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: task.isCompleted 
                            ? theme.colorScheme.tertiary.withOpacity(0.3)
                            : theme.colorScheme.secondary.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: task.isCompleted 
                              ? theme.colorScheme.onTertiaryContainer
                              : theme.colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _taskTimeCache[task.id!]!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: task.isCompleted 
                                ? theme.colorScheme.onTertiaryContainer
                                : theme.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  IconButton.filledTonal(
                    onPressed: () {
                      // TODO: Toggle completion status
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            task.isCompleted 
                              ? 'Mark as incomplete - Coming soon!' 
                              : 'Mark as complete - Coming soon!',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: Icon(
                      task.isCompleted 
                        ? Icons.check_circle_rounded 
                        : Icons.radio_button_unchecked_rounded,
                      color: task.isCompleted 
                        ? theme.colorScheme.primary 
                        : theme.colorScheme.outline,
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
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
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

          if (_tasks.isEmpty) {
            return _buildEmptyState();
          }

          final activeTasks = _tasks.where((t) => !t.isCompleted).toList();
          final completedTasks = _tasks.where((t) => t.isCompleted).toList();

          return RefreshIndicator(
            onRefresh: _loadTasks,
            child: CustomScrollView(
              slivers: [
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Priority sorted',
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
                      (context, index) => _buildTaskCard(activeTasks[index]),
                      childCount: activeTasks.length,
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
                      (context, index) => _buildTaskCard(completedTasks[index]),
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

