import 'dart:developer' as developer;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// Schedules and cancels time-based alarms for tasks.
class TaskAlarmService {
  static final TaskAlarmService _instance = TaskAlarmService._internal();
  factory TaskAlarmService() => _instance;
  TaskAlarmService._internal();

  /// Compute a stable notification id from the task id to allow update/cancel.
  int _notifIdForTaskId(int taskId) => 100000 + taskId;

  /// Build the scheduled DateTime for a task based on its taskDate and taskTime.
  /// Returns null if the computed time is in the past (and task is not recurring).
  DateTime? _scheduledDateTimeFor(TaskModel task) {
    final dt = DateTime(
      task.taskDate.year,
      task.taskDate.month,
      task.taskDate.day,
      task.taskTime.hour,
      task.taskTime.minute,
    );
    if (task.isRecurring && task.recurringPattern != null) {
      // For recurring tasks, if time is in the past for the selected date, compute next occurrence.
      if (dt.isAfter(DateTime.now())) return dt;
      final nextDate = task.recurringPattern!.getNextOccurrence(DateTime.now());
      if (nextDate == null) return null;
      return DateTime(
        nextDate.year, nextDate.month, nextDate.day, task.taskTime.hour, task.taskTime.minute,
      );
    } else {
      // One-time task: schedule only if in the future
      return dt.isAfter(DateTime.now()) ? dt : null;
    }
  }

  NotificationDetails _alarmNotificationDetails() {
    const android = AndroidNotificationDetails(
      'task_alarms',
      'Task Alarms',
      channelDescription: 'Time-based task alarms',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      category: AndroidNotificationCategory.reminder,
      styleInformation: BigTextStyleInformation(''),
    );
    const iOS = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );
    return const NotificationDetails(android: android, iOS: iOS);
  }

  /// Schedule (or reschedule) the alarm for a task. If the task time is in the past
  /// and not recurring, existing alarm is cancelled.
  Future<void> scheduleForTask(TaskModel task) async {
    if (task.id == null) {
      developer.log('[TaskAlarmService] Cannot schedule alarm for task with null id');
      return;
    }
    try {
      final plugin = notificationPlugin;
      final scheduled = _scheduledDateTimeFor(task);
      final notifId = _notifIdForTaskId(task.id!);

      // Cancel any existing scheduled alarm for this task before rescheduling
      try { await plugin.cancel(notifId); } catch (_) {}

      if (scheduled == null) {
        developer.log('[TaskAlarmService] No future time to schedule for task id=${task.id}');
        return;
      }

      final tzTime = tz.TZDateTime.from(scheduled, tz.local);

      final details = _alarmNotificationDetails();
      final title = 'Task Reminder';
      final body = '${task.taskName} at ${task.taskTime.hour.toString().padLeft(2, '0')}:${task.taskTime.minute.toString().padLeft(2, '0')}';

      await plugin.zonedSchedule(
        notifId,
        title,
        body,
        tzTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: task.isRecurring ? DateTimeComponents.time : null,
        payload: '${task.id}',
      );

      developer.log('[TaskAlarmService] Scheduled alarm for task id=${task.id} at $scheduled');
    } catch (e, st) {
      developer.log('[TaskAlarmService] Failed to schedule alarm for task id=${task.id}: $e', error: e, stackTrace: st);
    }
  }

  /// Cancel the alarm for a task by id
  Future<void> cancelForTaskId(int taskId) async {
    try {
      final plugin = notificationPlugin;
      await plugin.cancel(_notifIdForTaskId(taskId));
      developer.log('[TaskAlarmService] Canceled alarm for task id=$taskId');
    } catch (e) {
      developer.log('[TaskAlarmService] Failed to cancel alarm for task id=$taskId: $e');
    }
  }
}