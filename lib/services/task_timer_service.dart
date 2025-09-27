import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/model/task_history_model.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'package:intelliboro/services/database_service.dart';

/// Service responsible for managing task timers and active task tracking
class TaskTimerService extends ChangeNotifier {
  static final TaskTimerService _instance = TaskTimerService._internal();
  factory TaskTimerService() => _instance;
  TaskTimerService._internal();

  // Current active task and timer
  TaskModel? _activeTask;
  DateTime? _startTime;
  Timer? _timer;
  Duration _elapsedTime = Duration.zero;

  // Getters
  TaskModel? get activeTask => _activeTask;
  DateTime? get startTime => _startTime;
  Duration get elapsedTime => _elapsedTime;
  bool get hasActiveTask => _activeTask != null;

  /// Start timing a task
  Future<bool> startTask(TaskModel task) async {
    try {
      developer.log('[TaskTimerService] Attempting to start task: ${task.taskName}');
      
      // Check if there's already an active task
      if (_activeTask != null) {
        developer.log('[TaskTimerService] Active task found: ${_activeTask!.taskName}');
        
        // Compare priorities - higher effective priority wins
        final currentPriority = _activeTask!.getEffectivePriority();
        final newPriority = task.getEffectivePriority();
        
        if (newPriority > currentPriority) {
          developer.log('[TaskTimerService] New task has higher priority ($newPriority vs $currentPriority), switching tasks');
          
          // Stop current task and reschedule it
          await _stopCurrentTaskAndReschedule();
          
          // Start the new higher priority task
          return _startTaskTimer(task);
        } else {
          developer.log('[TaskTimerService] Current task has higher/equal priority ($currentPriority vs $newPriority), rescheduling new task');
          
          // Reschedule the new task and keep current one active
          await _rescheduleTask(task);
          return false; // Indicate task was rescheduled, not started
        }
      } else {
        // No active task, start this one
        return _startTaskTimer(task);
      }
    } catch (e, stackTrace) {
      developer.log(
        '[TaskTimerService] Error starting task',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Internal method to start the timer for a task
  bool _startTaskTimer(TaskModel task) {
    try {
      _activeTask = task;
      _startTime = DateTime.now();
      _elapsedTime = Duration.zero;
      
      // Start the timer that updates every second
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_startTime != null) {
          _elapsedTime = DateTime.now().difference(_startTime!);
          notifyListeners();
        }
      });
      
      developer.log('[TaskTimerService] Started timer for task: ${task.taskName}');

      // Ensure UI updates to reflect task timer start
      notifyListeners();
      return true;
    } catch (e) {
      developer.log('[TaskTimerService] Error starting task timer: $e');
      return false;
    }
  }

  /// Stop the current task and save completion time
  Future<Duration> stopTask() async {
    if (_activeTask == null || _startTime == null) {
      developer.log('[TaskTimerService] No active task to stop');
      return Duration.zero;
    }

    try {
      final finalDuration = DateTime.now().difference(_startTime!);
      final completedTask = _activeTask!;
      
      developer.log('[TaskTimerService] Stopping task: ${completedTask.taskName}, Duration: ${_formatDuration(finalDuration)}');
      
      // Mark task as completed in database
      await _markTaskCompleted(completedTask, finalDuration);
      
      // Clean up timer state
      _timer?.cancel();
      _timer = null;
      _activeTask = null;
      _startTime = null;
      _elapsedTime = Duration.zero;
      
      notifyListeners();
      return finalDuration;
    } catch (e, stackTrace) {
      developer.log(
        '[TaskTimerService] Error stopping task',
        error: e,
        stackTrace: stackTrace,
      );
      return _elapsedTime;
    }
  }

  /// Stop current task and reschedule it for later
  Future<void> _stopCurrentTaskAndReschedule() async {
    if (_activeTask == null) return;
    
    final taskToReschedule = _activeTask!;
    
    // Stop the timer
    _timer?.cancel();
    _timer = null;
    _activeTask = null;
    _startTime = null;
    _elapsedTime = Duration.zero;
    
    // Reschedule the interrupted task
    await _rescheduleTask(taskToReschedule);
  }

  /// Reschedule a task to a later time
  Future<void> _rescheduleTask(TaskModel task) async {
    try {
      // Calculate new time - add 1 hour to current time or original time, whichever is later
      final now = DateTime.now();
      final originalDateTime = DateTime(
        task.taskDate.year,
        task.taskDate.month,
        task.taskDate.day,
        task.taskTime.hour,
        task.taskTime.minute,
      );
      
      final baseTime = originalDateTime.isAfter(now) ? originalDateTime : now;
      final newDateTime = baseTime.add(const Duration(hours: 1));
      
      // Create updated task
      final rescheduledTask = TaskModel(
        id: task.id,
        taskName: task.taskName,
        taskPriority: task.taskPriority,
        taskTime: TimeOfDay(hour: newDateTime.hour, minute: newDateTime.minute),
        taskDate: DateTime(newDateTime.year, newDateTime.month, newDateTime.day),
        isRecurring: task.isRecurring,
        isCompleted: false, // Ensure it's not marked as completed
        geofenceId: task.geofenceId,
      );
      
      // Update in database
      await TaskRepository().updateTask(rescheduledTask);
      
      developer.log('[TaskTimerService] Rescheduled task "${task.taskName}" to ${_formatDateTime(newDateTime)}');
    } catch (e, stackTrace) {
      developer.log(
        '[TaskTimerService] Error rescheduling task',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Reschedule a task manually (for "Do Later" action)
  Future<void> rescheduleTaskLater(TaskModel task) async {
    await _rescheduleTask(task);
  }

  /// Mark a task as completed in the database and save to task history
  Future<void> _markTaskCompleted(TaskModel task, Duration completionTime) async {
    try {
      // Mark task as completed
      final completedTask = TaskModel(
        id: task.id,
        taskName: task.taskName,
        taskPriority: task.taskPriority,
        taskTime: task.taskTime,
        taskDate: task.taskDate,
        isRecurring: task.isRecurring,
        isCompleted: true,
        geofenceId: task.geofenceId,
      );
      
      await TaskRepository().updateTask(completedTask);
      
      // Save to task history
      await _saveTaskHistory(task, completionTime);
      
      developer.log('[TaskTimerService] Marked task as completed: ${task.taskName}, Time taken: ${_formatDuration(completionTime)}');
    } catch (e, stackTrace) {
      developer.log(
        '[TaskTimerService] Error marking task as completed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Save task completion to history
  Future<void> _saveTaskHistory(TaskModel task, Duration completionTime) async {
    try {
      final endTime = DateTime.now();
      final startTime = endTime.subtract(completionTime);
      
      final historyModel = TaskHistoryModel(
        taskId: task.id,
        taskName: task.taskName,
        taskPriority: task.taskPriority,
        startTime: startTime,
        endTime: endTime,
        duration: completionTime,
        completionDate: DateTime(
          endTime.year,
          endTime.month,
          endTime.day,
        ),
        geofenceId: task.geofenceId,
      );
      
      final db = await DatabaseService().mainDb;
      await DatabaseService().insertTaskHistory(db, historyModel.toMap());
      
      developer.log('[TaskTimerService] Saved task history for: ${task.taskName}');
    } catch (e, stackTrace) {
      developer.log(
        '[TaskTimerService] Error saving task history',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get formatted elapsed time string
  String getFormattedElapsedTime() {
    return _formatDuration(_elapsedTime);
  }

  /// Format duration to human readable string
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// Format DateTime to readable string
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Clean up resources
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}