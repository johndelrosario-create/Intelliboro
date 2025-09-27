import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

class TaskModel {
  final int? id;
  //TaskName
  final String taskName;
  final int taskPriority;
  // Stores selected time
  final TimeOfDay taskTime;
  // Stores selected date
  final DateTime taskDate;

  final bool isRecurring;
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
    required this.isCompleted,
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
      'taskTime': taskTime.hour.toString() + ':' + taskTime.minute.toString(),
      'taskDate': DateFormat('yyyy-MM-dd').format(taskDate),
      'isRecurring': isRecurring ? 1 : 0,
      'isCompleted': isCompleted ? 1 : 0,
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
      isCompleted: (map['isCompleted'] as int) == 1,
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

  @override
  String toString() {
    return 'TaskModel{taskName: $taskName, taskPriority: $taskPriority ($priorityString), taskTime: $taskTime, taskDate: $taskDate, isRecurring: $isRecurring, isCompleted: $isCompleted}';
  }
}
