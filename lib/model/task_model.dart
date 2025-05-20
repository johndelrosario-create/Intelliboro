import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
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
}
