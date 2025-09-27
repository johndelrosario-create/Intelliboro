import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intelliboro/model/task_model.dart';

/// Service to manage active task timers and handle task interruptions
class TaskTimerService {
  static final TaskTimerService _instance = TaskTimerService._internal();
  factory TaskTimerService() => _instance;
  TaskTimerService._internal();

  Timer? _activeTaskTimer;
  TaskModel? _currentActiveTask;
  DateTime? _taskStartTime;
  Duration _accumulatedTime = Duration.zero;
  
  // Callback for when a task is completed or interrupted
  Function(TaskModel task, Duration duration, bool wasInterrupted)? onTaskStopped;
  
  // Callback for task interruption notifications
  Function(TaskModel interruptedTask, TaskModel newTask, Duration timeSpent)? onTaskInterrupted;

  /// Get the currently active task
  TaskModel? get currentActiveTask => _currentActiveTask;
  
  /// Get the time the current task has been active
  Duration get currentTaskDuration {
    if (_taskStartTime == null) return _accumulatedTime;
    return _accumulatedTime + DateTime.now().difference(_taskStartTime!);
  }
  
  /// Check if there's an active task
  bool get hasActiveTask => _currentActiveTask != null;

  /// Start a timer for a specific task
  Future<void> startTask(TaskModel task) async {
    developer.log('[TaskTimerService] Starting task: ${task.taskName}');
    
    // If there's already an active task, handle it
    if (_currentActiveTask != null) {
      await _handleTaskInterruption(task);
      return;
    }
    
    _currentActiveTask = task;
    _taskStartTime = DateTime.now();
    _accumulatedTime = Duration.zero;
    
    // Start the timer (update every second for accurate tracking)
    _activeTaskTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // This timer just tracks time - we could use it for UI updates if needed
      developer.log('[TaskTimerService] Task "${task.taskName}" active for: ${currentTaskDuration.inMinutes} minutes');
    });
    
    developer.log('[TaskTimerService] Task timer started successfully');
  }

  /// Stop the currently active task
  Future<void> stopTask({required bool completed}) async {
    if (_currentActiveTask == null) return;
    
    final task = _currentActiveTask!;
    final duration = currentTaskDuration;
    
    developer.log('[TaskTimerService] Stopping task: ${task.taskName}, Duration: ${duration.inMinutes} minutes, Completed: $completed');
    
    _activeTaskTimer?.cancel();
    _activeTaskTimer = null;
    
    // Notify listeners about task completion
    onTaskStopped?.call(task, duration, !completed);
    
    _currentActiveTask = null;
    _taskStartTime = null;
    _accumulatedTime = Duration.zero;
  }

  /// Handle task interruption when a higher priority task comes in
  Future<void> _handleTaskInterruption(TaskModel newTask) async {
    if (_currentActiveTask == null) return;
    
    final currentTask = _currentActiveTask!;
    final timeSpent = currentTaskDuration;
    
    developer.log('[TaskTimerService] Task interruption: ${currentTask.taskName} -> ${newTask.taskName}');
    developer.log('[TaskTimerService] Time spent on interrupted task: ${timeSpent.inMinutes} minutes');
    
    // Check if the new task has higher priority
    if (newTask.getEffectivePriority() > currentTask.getEffectivePriority()) {
      developer.log('[TaskTimerService] New task has higher priority, interrupting current task');
      
      // Stop current task
      await stopTask(completed: false);
      
      // Notify about the interruption
      onTaskInterrupted?.call(currentTask, newTask, timeSpent);
      
      // Start new task
      await startTask(newTask);
    } else {
      developer.log('[TaskTimerService] New task has lower priority, handling reschedule');
      // Handle lower priority task - we'll implement rescheduling logic
      await _handleLowerPriorityTask(newTask);
    }
  }

  /// Handle a lower priority task when there's already an active task
  Future<void> _handleLowerPriorityTask(TaskModel lowerPriorityTask) async {
    developer.log('[TaskTimerService] Handling lower priority task: ${lowerPriorityTask.taskName}');
    
    // Strategy: Automatically reschedule the lower priority task for later
    // This could be enhanced with user preferences
    final suggestedTime = _calculateRescheduleTime(lowerPriorityTask);
    
    developer.log('[TaskTimerService] Suggesting reschedule time: $suggestedTime');
    
    // Show a subtle notification about the rescheduled task
    await _showRescheduleNotification(lowerPriorityTask, suggestedTime);
  }

  /// Calculate a good reschedule time for a lower priority task
  DateTime _calculateRescheduleTime(TaskModel task) {
    // Strategy: Reschedule for 30 minutes after the current task's estimated completion
    // This is a simple heuristic - could be made more sophisticated
    
    final estimatedCurrentTaskDuration = Duration(hours: 1); // Default estimation
    final rescheduleTime = DateTime.now().add(estimatedCurrentTaskDuration).add(Duration(minutes: 30));
    
    return rescheduleTime;
  }

  /// Show a notification about a rescheduled task
  Future<void> _showRescheduleNotification(TaskModel task, DateTime newTime) async {
    // This would integrate with the notification system
    developer.log('[TaskTimerService] Would show reschedule notification for: ${task.taskName} at $newTime');
    // Implementation would depend on the notification system structure
  }

  /// Pause the current task (accumulate time but stop timer)
  void pauseTask() {
    if (_currentActiveTask == null || _taskStartTime == null) return;
    
    _accumulatedTime += DateTime.now().difference(_taskStartTime!);
    _taskStartTime = null;
    _activeTaskTimer?.cancel();
    _activeTaskTimer = null;
    
    developer.log('[TaskTimerService] Task paused. Accumulated time: ${_accumulatedTime.inMinutes} minutes');
  }

  /// Resume the current task
  void resumeTask() {
    if (_currentActiveTask == null || _taskStartTime != null) return;
    
    _taskStartTime = DateTime.now();
    
    // Restart the timer
    _activeTaskTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Timer for tracking - could be used for UI updates
    });
    
    developer.log('[TaskTimerService] Task resumed');
  }

  /// Clean up resources
  void dispose() {
    _activeTaskTimer?.cancel();
    _activeTaskTimer = null;
    _currentActiveTask = null;
    _taskStartTime = null;
    _accumulatedTime = Duration.zero;
  }
}