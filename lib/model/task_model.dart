import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:intelliboro/model/recurring_pattern.dart';

class TaskModel {
  final int? id;
  //TaskName
  final String taskName;
  final int taskPriority; // 1-5 scale (1=low, 5=high)
  // Stores selected time (null means no specific time set)
  final TimeOfDay? taskTime;
  // Stores selected date (null means no specific date set)
  final DateTime? taskDate;

  final bool isRecurring;
  final RecurringPattern? recurringPattern;
  final String? geofenceId;
  final bool isCompleted;

  // Notification sound for this specific task (overrides app default)
  final String? notificationSound;

  // Enable text-to-speech for this task (defaults to true if null for backward compatibility)
  final bool? enableTts;

  // Task notification type?

  //Geofence location of task?

  /// Optional creation timestamp (Unix seconds) from the database.
  final int? createdAt;

  const TaskModel({
    this.id,
    required this.taskName,
    required this.taskPriority,
    required this.taskTime,
    required this.taskDate,
    required this.isRecurring,
    this.recurringPattern,
    required this.isCompleted,
    this.geofenceId,
    this.createdAt,
    this.notificationSound,
    this.enableTts,
  }) : assert(
         taskPriority >= 1 && taskPriority <= 5,
         'Priority must be between 1 and 5',
       );

  // Convert TaskModel to Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'taskName': taskName,
      'taskPriority': taskPriority,
      'taskTime':
          taskTime != null ? '${taskTime!.hour}:${taskTime!.minute}' : null,
      'taskDate':
          taskDate != null ? DateFormat('yyyy-MM-dd').format(taskDate!) : null,
      'isRecurring': isRecurring ? 1 : 0,
      'recurring_pattern': recurringPattern?.toJson(),
      'isCompleted': isCompleted ? 1 : 0,
      'geofence_id': geofenceId,
      'notification_sound': notificationSound,
      'enable_tts': enableTts == null ? null : (enableTts! ? 1 : 0),
      // 'created_at' is intentionally omitted; DB sets it by default.
    };
  }

  factory TaskModel.fromMap(Map<String, dynamic> map) {
    final timeStr = map['taskTime'] as String?;
    final dateStr = map['taskDate'] as String?;

    return TaskModel(
      id: map['id'] as int?,
      taskName: map['taskName'] as String,
      taskPriority: map['taskPriority'] as int,
      taskTime:
          timeStr != null
              ? TimeOfDay(
                hour: int.parse(timeStr.split(':')[0]),
                minute: int.parse(timeStr.split(':')[1]),
              )
              : null,
      taskDate: dateStr != null ? DateTime.parse(dateStr) : null,
      isRecurring: (map['isRecurring'] as int) == 1,
      recurringPattern:
          map['recurring_pattern'] != null
              ? RecurringPattern.fromJson(map['recurring_pattern'] as String)
              : null,
      isCompleted: (map['isCompleted'] as int) == 1,
      geofenceId: map['geofence_id'] as String?,
      notificationSound: map['notification_sound'] as String?,
      enableTts:
          map['enable_tts'] == null ? null : ((map['enable_tts'] as int) == 1),
      createdAt: map['created_at'] as int?,
    );
  }

  /// Get priority as human-readable string
  String get priorityString {
    switch (taskPriority) {
      case 1:
        return 'Very Low';
      case 2:
        return 'Low';
      case 3:
        return 'Medium';
      case 4:
        return 'High';
      case 5:
        return 'Very High';
      default:
        return 'Unknown';
    }
  }

  /// Calculate effective priority based on user priority and urgency
  /// Urgency is calculated based on how close the task time is to now
  double getEffectivePriority() {
    // Base priority from user (1-5 scale)
    double effectivePriority = taskPriority.toDouble();

    // Time-based alarm tasks (without geofences) use base priority only
    // since the alarm itself indicates when to do them - no urgency bonus needed
    if (geofenceId == null || geofenceId!.isEmpty) {
      return effectivePriority;
    }

    // For geofenced tasks: add urgency based on time proximity
    // This helps prioritize location-based tasks that are also time-sensitive

    // If no time is set, return base priority only
    if (taskTime == null || taskDate == null) {
      return effectivePriority;
    }

    final now = DateTime.now();
    final taskDateTime = DateTime(
      taskDate!.year,
      taskDate!.month,
      taskDate!.day,
      taskTime!.hour,
      taskTime!.minute,
    );

    // Calculate hours until task
    final hoursUntilTask = taskDateTime.difference(now).inHours;

    // Add urgency multiplier based on time proximity (geofenced tasks only)
    if (hoursUntilTask <= 0) {
      // Task is overdue or happening now - maximum urgency
      effectivePriority += 2.0;
    } else if (hoursUntilTask <= 1) {
      // Task is within 1 hour - high urgency
      effectivePriority += 1.5;
    } else if (hoursUntilTask <= 3) {
      // Task is within 3 hours - medium urgency
      effectivePriority += 1.0;
    } else if (hoursUntilTask <= 24) {
      // Task is within 24 hours - low urgency
      effectivePriority += 0.5;
    }
    // Tasks more than 24 hours away get no urgency bonus

    return effectivePriority;
  }

  /// Compare tasks by effective priority (higher is more important)
  static int compareByEffectivePriority(TaskModel a, TaskModel b) {
    return b.getEffectivePriority().compareTo(a.getEffectivePriority());
  }

  /// Compare tasks alphabetically by name (A-Z, case-insensitive)
  static int compareByName(TaskModel a, TaskModel b) {
    return a.taskName.toLowerCase().compareTo(b.taskName.toLowerCase());
  }

  /// Compare tasks by creation timestamp (newest first). Fallback to id desc.
  static int compareByCreatedAt(TaskModel a, TaskModel b) {
    final aTs = a.createdAt ?? a.id ?? 0;
    final bTs = b.createdAt ?? b.id ?? 0;
    return bTs.compareTo(aTs);
  }

  /// Get a user-friendly description of the recurring pattern
  String get recurringDescription {
    if (!isRecurring || recurringPattern == null) {
      return 'One-time task';
    }
    return recurringPattern!.description;
  }

  /// Get a short description of the recurring pattern for UI
  String get recurringShortDescription {
    if (!isRecurring || recurringPattern == null) {
      return 'Once';
    }
    return recurringPattern!.shortDescription;
  }

  /// Check if this task should occur on a specific date
  bool shouldOccurOn(DateTime date) {
    if (!isRecurring || recurringPattern == null) {
      // For one-time tasks, check if it matches the exact date
      if (taskDate == null) return false;
      return taskDate!.year == date.year &&
          taskDate!.month == date.month &&
          taskDate!.day == date.day;
    }
    return recurringPattern!.shouldOccurOn(date);
  }

  /// Get the next occurrence of this task after the given date
  DateTime? getNextOccurrence(DateTime after) {
    if (!isRecurring || recurringPattern == null) {
      // For one-time tasks, return the task date if it's after the given date
      if (taskDate == null || taskTime == null) return null;
      final taskDateTime = DateTime(
        taskDate!.year,
        taskDate!.month,
        taskDate!.day,
        taskTime!.hour,
        taskTime!.minute,
      );
      return taskDateTime.isAfter(after) ? taskDate : null;
    }
    return recurringPattern!.getNextOccurrence(after);
  }

  /// Create a copy of this task with a new date (for recurring task instances)
  TaskModel copyWithDate(DateTime newDate) {
    return TaskModel(
      id: null, // New instance gets a new ID
      taskName: taskName,
      taskPriority: taskPriority,
      taskTime: taskTime,
      taskDate: newDate,
      isRecurring: isRecurring,
      recurringPattern: recurringPattern,
      isCompleted: false, // New instances start as incomplete
      geofenceId: geofenceId,
      createdAt: createdAt,
      notificationSound: notificationSound,
      enableTts: enableTts,
    );
  }

  /// Create a copy with modified values
  TaskModel copyWith({
    int? id,
    String? taskName,
    int? taskPriority,
    TimeOfDay? taskTime,
    DateTime? taskDate,
    bool? isRecurring,
    RecurringPattern? recurringPattern,
    bool? isCompleted,
    String? geofenceId,
    int? createdAt,
    String? notificationSound,
    bool? enableTts,
  }) {
    return TaskModel(
      id: id ?? this.id,
      taskName: taskName ?? this.taskName,
      taskPriority: taskPriority ?? this.taskPriority,
      taskTime: taskTime ?? this.taskTime,
      taskDate: taskDate ?? this.taskDate,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringPattern: recurringPattern ?? this.recurringPattern,
      isCompleted: isCompleted ?? this.isCompleted,
      geofenceId: geofenceId ?? this.geofenceId,
      createdAt: createdAt ?? this.createdAt,
      notificationSound: notificationSound ?? this.notificationSound,
      enableTts: enableTts ?? this.enableTts,
    );
  }

  @override
  String toString() {
    return 'TaskModel{taskName: $taskName, taskPriority: $taskPriority ($priorityString), taskTime: $taskTime, taskDate: $taskDate, isRecurring: $isRecurring, recurringPattern: $recurringPattern, isCompleted: $isCompleted, createdAt: $createdAt}';
  }
}
