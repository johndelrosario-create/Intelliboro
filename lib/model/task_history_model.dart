import 'package:flutter/material.dart';

/// Model representing a completed task with timing information
class TaskHistoryModel {
  final int? id;
  final int? taskId;
  final String taskName;
  final int taskPriority;
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final DateTime completionDate;
  final String? geofenceId;
  final DateTime? createdAt;

  const TaskHistoryModel({
    this.id,
    this.taskId,
    required this.taskName,
    required this.taskPriority,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.completionDate,
    this.geofenceId,
    this.createdAt,
  }) : assert(taskPriority >= 1 && taskPriority <= 5, 'Priority must be between 1 and 5');

  /// Convert TaskHistoryModel to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'task_id': taskId,
      'task_name': taskName,
      'task_priority': taskPriority,
      'start_time': startTime.millisecondsSinceEpoch ~/ 1000, // Store as seconds
      'end_time': endTime.millisecondsSinceEpoch ~/ 1000,
      'duration_seconds': duration.inSeconds,
      'completion_date': completionDate.toIso8601String().split('T')[0], // YYYY-MM-DD format
      'geofence_id': geofenceId,
      'created_at': createdAt?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };
  }

  /// Create TaskHistoryModel from database Map
  factory TaskHistoryModel.fromMap(Map<String, dynamic> map) {
    final startTimeSeconds = map['start_time'] as int;
    final endTimeSeconds = map['end_time'] as int;
    final durationSeconds = map['duration_seconds'] as int;
    final completionDateString = map['completion_date'] as String;
    final createdAtSeconds = map['created_at'] as int?;

    return TaskHistoryModel(
      id: map['id'] as int?,
      taskId: map['task_id'] as int?,
      taskName: map['task_name'] as String,
      taskPriority: map['task_priority'] as int,
      startTime: DateTime.fromMillisecondsSinceEpoch(startTimeSeconds * 1000),
      endTime: DateTime.fromMillisecondsSinceEpoch(endTimeSeconds * 1000),
      duration: Duration(seconds: durationSeconds),
      completionDate: DateTime.parse(completionDateString),
      geofenceId: map['geofence_id'] as String?,
      createdAt: createdAtSeconds != null 
          ? DateTime.fromMillisecondsSinceEpoch(createdAtSeconds * 1000)
          : null,
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

  /// Get priority color
  Color get priorityColor {
    switch (taskPriority) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.lightGreen;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.deepOrange;
      case 5:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Get priority icon
  IconData get priorityIcon {
    switch (taskPriority) {
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

  /// Format duration to human readable string
  String get formattedDuration {
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

  /// Format completion date to readable string
  String get formattedCompletionDate {
    return '${completionDate.day}/${completionDate.month}/${completionDate.year}';
  }

  /// Format start time to readable string
  String get formattedStartTime {
    return '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
  }

  /// Format end time to readable string
  String get formattedEndTime {
    return '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
  }

  /// Get efficiency rating based on task priority and duration
  String get efficiencyRating {
    // This is a simple heuristic - can be improved based on user preferences
    final expectedMinutes = taskPriority * 30; // Higher priority = more expected time
    final actualMinutes = duration.inMinutes;
    
    if (actualMinutes <= expectedMinutes * 0.8) {
      return 'Excellent';
    } else if (actualMinutes <= expectedMinutes) {
      return 'Good';
    } else if (actualMinutes <= expectedMinutes * 1.5) {
      return 'Average';
    } else {
      return 'Slow';
    }
  }

  /// Get efficiency color
  Color get efficiencyColor {
    switch (efficiencyRating) {
      case 'Excellent':
        return Colors.green;
      case 'Good':
        return Colors.lightGreen;
      case 'Average':
        return Colors.orange;
      case 'Slow':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  String toString() {
    return 'TaskHistoryModel{taskName: $taskName, taskPriority: $taskPriority ($priorityString), duration: $formattedDuration, completionDate: $formattedCompletionDate}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TaskHistoryModel &&
        other.id == id &&
        other.taskId == taskId &&
        other.taskName == taskName &&
        other.taskPriority == taskPriority &&
        other.startTime == startTime &&
        other.endTime == endTime &&
        other.geofenceId == geofenceId;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      taskId,
      taskName,
      taskPriority,
      startTime,
      endTime,
      geofenceId,
    );
  }

  /// Create a copy of this model with updated fields
  TaskHistoryModel copyWith({
    int? id,
    int? taskId,
    String? taskName,
    int? taskPriority,
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
    DateTime? completionDate,
    String? geofenceId,
    DateTime? createdAt,
  }) {
    return TaskHistoryModel(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      taskName: taskName ?? this.taskName,
      taskPriority: taskPriority ?? this.taskPriority,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      completionDate: completionDate ?? this.completionDate,
      geofenceId: geofenceId ?? this.geofenceId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
