import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:intelliboro/model/recurring_pattern.dart';

class TaskModel {
  final int? id;
  //TaskName
  final String taskName;
  final int taskPriority; // 1-5 scale (1=low, 5=high)
  // Stores selected time
  final TimeOfDay taskTime;
  // Stores selected date
  final DateTime taskDate;

  final bool isRecurring;
  final RecurringPattern? recurringPattern;
  final String? geofenceId;
  final bool isCompleted;

  // Task notification type?

  //Geofence location of task?

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
  }) : assert(taskPriority >= 1 && taskPriority <= 5, 'Priority must be between 1 and 5');

  // Convert TaskModel to Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'taskName': taskName,
      'taskPriority': taskPriority,
      'taskTime': '${taskTime.hour}:${taskTime.minute}',
      'taskDate': DateFormat('yyyy-MM-dd').format(taskDate),
      'isRecurring': isRecurring ? 1 : 0,
      'recurring_pattern': recurringPattern?.toJson(),
      'isCompleted': isCompleted ? 1 : 0,
      'geofence_id': geofenceId,
    };
  }

  factory TaskModel.fromMap(Map<String, dynamic> map) {
    return TaskModel(
      id: map['id'] as int?,
      taskName: map['taskName'] as String,
      taskPriority: map['taskPriority'] as int,
      taskTime: TimeOfDay(
        // Ensure robust parsing
        hour: int.parse((map['taskTime'] as String).split(':')[0]),
        minute: int.parse((map['taskTime'] as String).split(':')[1]),
      ),
      taskDate: DateTime.parse(map['taskDate'] as String),
      isRecurring: (map['isRecurring'] as int) == 1,
      recurringPattern: map['recurring_pattern'] != null 
        ? RecurringPattern.fromJson(map['recurring_pattern'] as String)
        : null,
      isCompleted: (map['isCompleted'] as int) == 1,
      geofenceId: map['geofence_id'] as String?,
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
    final now = DateTime.now();
    final taskDateTime = DateTime(
      taskDate.year,
      taskDate.month,
      taskDate.day,
      taskTime.hour,
      taskTime.minute,
    );
    
    // Calculate hours until task
    final hoursUntilTask = taskDateTime.difference(now).inHours;
    
    // Base priority from user (1-5 scale)
    double effectivePriority = taskPriority.toDouble();
    
    // Add urgency multiplier based on time proximity
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
      return taskDate.year == date.year && 
             taskDate.month == date.month && 
             taskDate.day == date.day;
    }
    return recurringPattern!.shouldOccurOn(date);
  }

  /// Get the next occurrence of this task after the given date
  DateTime? getNextOccurrence(DateTime after) {
    if (!isRecurring || recurringPattern == null) {
      // For one-time tasks, return the task date if it's after the given date
      final taskDateTime = DateTime(
        taskDate.year, taskDate.month, taskDate.day,
        taskTime.hour, taskTime.minute,
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
    );
  }

  @override
  String toString() {
    return 'TaskModel{taskName: $taskName, taskPriority: $taskPriority ($priorityString), taskTime: $taskTime, taskDate: $taskDate, isRecurring: $isRecurring, recurringPattern: $recurringPattern, isCompleted: $isCompleted}';
  }
}