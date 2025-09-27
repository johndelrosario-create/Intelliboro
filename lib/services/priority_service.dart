import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:sqflite/sqflite.dart';

/// Service responsible for handling task priority logic
/// Determines which task to show when multiple tasks are associated with the same geofence
class PriorityService {
  static final PriorityService _instance = PriorityService._internal();
  factory PriorityService() => _instance;
  PriorityService._internal();

  /// Gets all tasks associated with a specific geofence
  /// Returns the highest priority task based on effective priority calculation
  Future<TaskModel?> getHighestPriorityTaskForGeofence(
    Database db,
    String geofenceId,
  ) async {
    try {
      developer.log(
        '[PriorityService] Finding highest priority task for geofence: $geofenceId',
      );

      // Get geofence details to find associated task name
      final geofenceStorage = GeofenceStorage(db: db);
      final geofenceData = await geofenceStorage.getGeofenceById(geofenceId);

      if (geofenceData == null) {
        developer.log(
          '[PriorityService] No geofence found with ID: $geofenceId',
        );
        return null;
      }

      final taskName = geofenceData.task;
      if (taskName == null || taskName.isEmpty) {
        developer.log(
          '[PriorityService] No task associated with geofence: $geofenceId',
        );
        return null;
      }

      // Get all tasks with this name (there might be multiple instances)
      final allTasks = await _getTasksByName(db, taskName);

      if (allTasks.isEmpty) {
        developer.log('[PriorityService] No tasks found with name: $taskName');
        return null;
      }

      // Filter to only include non-completed tasks
      final activeTasks = allTasks.where((task) => !task.isCompleted).toList();

      if (activeTasks.isEmpty) {
        developer.log(
          '[PriorityService] All tasks with name "$taskName" are completed',
        );
        return null;
      }

      // Sort by effective priority (descending - highest first)
      activeTasks.sort(TaskModel.compareByEffectivePriority);

      final selectedTask = activeTasks.first;
      developer.log(
        '[PriorityService] Selected highest priority task: ${selectedTask.taskName} '
        '(priority: ${selectedTask.taskPriority}, effective: ${selectedTask.getEffectivePriority().toStringAsFixed(2)})',
      );

      return selectedTask;
    } catch (e, stackTrace) {
      developer.log(
        '[PriorityService] Error getting highest priority task for geofence',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Gets multiple tasks that might be triggered at the same location
  /// Returns them sorted by effective priority
  Future<List<TaskModel>> getTasksForLocation(
    Database db,
    List<String> geofenceIds,
  ) async {
    try {
      developer.log(
        '[PriorityService] Finding tasks for ${geofenceIds.length} geofences',
      );

      final Map<String, TaskModel> uniqueTasks = {};

      for (final geofenceId in geofenceIds) {
        final task = await getHighestPriorityTaskForGeofence(db, geofenceId);
        if (task != null) {
          // Use task name + date/time as unique key to avoid duplicates
          final taskKey = '${task.taskName}_${task.taskDate}_${task.taskTime}';
          if (!uniqueTasks.containsKey(taskKey)) {
            uniqueTasks[taskKey] = task;
          } else {
            // If we have the same task, keep the one with higher effective priority
            final existingTask = uniqueTasks[taskKey]!;
            if (task.getEffectivePriority() >
                existingTask.getEffectivePriority()) {
              uniqueTasks[taskKey] = task;
            }
          }
        }
      }

      final taskList = uniqueTasks.values.toList();
      taskList.sort(TaskModel.compareByEffectivePriority);

      developer.log(
        '[PriorityService] Found ${taskList.length} unique tasks for location',
      );

      return taskList;
    } catch (e, stackTrace) {
      developer.log(
        '[PriorityService] Error getting tasks for location',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Helper method to get tasks by name
  Future<List<TaskModel>> _getTasksByName(Database db, String taskName) async {
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'tasks',
        where: 'taskName = ?',
        whereArgs: [taskName],
      );

      return maps.map((map) {
        return TaskModel(
          id: map['id'] as int?,
          taskName: map['taskName'] as String,
          taskPriority: map['taskPriority'] as int,
          taskTime: TimeOfDay(
            hour: int.parse((map['taskTime'] as String).split(':')[0]),
            minute: int.parse((map['taskTime'] as String).split(':')[1]),
          ),
          taskDate: DateTime.parse(map['taskDate'] as String),
          isRecurring: (map['isRecurring'] as int) == 1,
          isCompleted: (map['isCompleted'] as int) == 1,
        );
      }).toList();
    } catch (e, stackTrace) {
      developer.log(
        '[PriorityService] Error getting tasks by name: $taskName',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get priority-based notification title and body
  Map<String, String> generatePriorityNotification(TaskModel task) {
    final priorityEmoji = _getPriorityEmoji(task.taskPriority);
    final urgencyText = _getUrgencyText(task);

    return {
      'title': '$priorityEmoji ${task.priorityString} Priority Task',
      'body': '$urgencyText: ${task.taskName}',
    };
  }

  String _getPriorityEmoji(int priority) {
    switch (priority) {
      case 1:
        return '🟢'; // Green circle for low priority
      case 2:
        return '🟡'; // Yellow circle for low-medium priority
      case 3:
        return '🟠'; // Orange circle for medium priority
      case 4:
        return '🔴'; // Red circle for high priority
      case 5:
        return '🚨'; // Emergency siren for very high priority
      default:
        return '📋'; // Clipboard for unknown
    }
  }

  String _getUrgencyText(TaskModel task) {
    final now = DateTime.now();
    final taskDateTime = DateTime(
      task.taskDate.year,
      task.taskDate.month,
      task.taskDate.day,
      task.taskTime.hour,
      task.taskTime.minute,
    );

    final hoursUntilTask = taskDateTime.difference(now).inHours;

    if (hoursUntilTask <= 0) {
      return 'OVERDUE';
    } else if (hoursUntilTask <= 1) {
      return 'DUE NOW';
    } else if (hoursUntilTask <= 3) {
      return 'DUE SOON';
    } else if (hoursUntilTask <= 24) {
      return 'DUE TODAY';
    } else {
      return 'UPCOMING';
    }
  }
}
