import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

class TaskModel {
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
    required this.taskName,
    required this.taskPriority,
    required this.taskTime,
    required this.taskDate,
    required this.isRecurring,
    required this.isCompleted,
  });

  // Convert TaskModel to Map
  Map<String, dynamic> toMap() {
    return {
      'taskName': taskName,
      'taskPriority': taskPriority,
      'taskTime': taskTime.hour.toString() + ':' + taskTime.minute.toString(),
      'taskDate': DateFormat('yyyy-MM-dd').format(taskDate),
      'isRecurring': isRecurring ? 1 : 0,
      'isCompleted': isCompleted ? 1 : 0,
    };
  }

  @override
  String toString() {
    return 'TaskModel{taskName: $taskName, taskPriority: $taskPriority, taskTime: $taskTime, taskDate: $taskDate, isRecurring: $isRecurring, isCompleted: $isCompleted}';
  }

  
}
