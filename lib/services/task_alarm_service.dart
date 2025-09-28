import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intelliboro/services/notification_preferences_service.dart';

/// Schedules and cancels time-based alarms for tasks.
class TaskAlarmService {
  static final TaskAlarmService _instance = TaskAlarmService._internal();
  factory TaskAlarmService() => _instance;
  TaskAlarmService._internal();

  // Cached local timezone location to avoid relying on global tz.local which
  // may be mutated or not reflect the intended timezone in some contexts.
  tz.Location? _localTz;

  /// Compute a stable notification id from the task id to allow update/cancel.
  int _notifIdForTaskId(int taskId) => 100000 + taskId;

  /// Check if exact alarms can be scheduled using AlarmManager.canScheduleExactAlarms()
  Future<bool> _canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true; // iOS doesn't have this restriction

    try {
      const platform = MethodChannel('exact_alarms');
      final bool canSchedule = await platform.invokeMethod(
        'canScheduleExactAlarms',
      );
      return canSchedule;
    } catch (e) {
      developer.log(
        '[TaskAlarmService] Error checking exact alarm capability: $e',
      );
      return false;
    }
  }

  /// Request user to enable exact alarms by opening settings
  Future<bool> _requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return true; // iOS doesn't have this restriction

    try {
      const platform = MethodChannel('exact_alarms');
      final bool success = await platform.invokeMethod(
        'requestExactAlarmPermission',
      );
      return success;
    } catch (e) {
      developer.log(
        '[TaskAlarmService] Error requesting exact alarm permission: $e',
      );
      return false;
    }
  }

  Future<void> _scheduleSystemAlarm(
    int notifId,
    tz.TZDateTime tzTime,
    String title,
    String body,
    int? taskId,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      const platform = MethodChannel('exact_alarms');
      final args = {
        'id': notifId,
        'taskId': taskId,
        'triggerAtMillis': tzTime.millisecondsSinceEpoch,
        'title': title,
        'body': body,
      };
      developer.log(
        '[TaskAlarmService] Invoking platform.scheduleAlarm with args=$args',
      );
      await platform.invokeMethod('scheduleAlarm', args);
      developer.log(
        '[TaskAlarmService] Scheduled system alarm via platform for id=$notifId at $tzTime',
      );
    } catch (e) {
      developer.log(
        '[TaskAlarmService] Failed to schedule system alarm via platform: $e',
      );
    }
  }

  Future<void> _cancelSystemAlarm(int notifId) async {
    if (!Platform.isAndroid) return;
    try {
      const platform = MethodChannel('exact_alarms');
      await platform.invokeMethod('cancelAlarm', {'id': notifId});
      developer.log(
        '[TaskAlarmService] Requested cancel of system alarm id=$notifId',
      );
    } catch (e) {
      developer.log(
        '[TaskAlarmService] Failed to cancel system alarm via platform: $e',
      );
    }
  }

  /// Show dialog to guide user to enable exact alarms
  Future<void> _showExactAlarmDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Exact Alarms Required'),
          content: const Text(
            'For precise task reminders, please enable "Allow exact alarms" for this app.\n\n'
            'This ensures your task reminders fire at the exact time you set.\n\n'
            '1. Tap "Open Settings" below\n'
            '2. Find "Alarms & reminders" or "Special app access"\n'
            '3. Enable "Allow exact alarms"',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () {
                Navigator.of(context).pop();
                _requestExactAlarmPermission();
              },
            ),
            TextButton(
              child: const Text('Continue with Approximate Alarms'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Build the scheduled TZDateTime for a task based on its taskDate and taskTime.
  /// Returns null if the computed time is in the past (and task is not recurring).
  tz.TZDateTime? _scheduledDateTimeFor(TaskModel task) {
    if (task.taskTime == null || task.taskDate == null) {
      developer.log(
        '[TaskAlarmService] _scheduledDateTimeFor: task has no time/date set',
      );
      return null;
    }

    // Ensure timezones are initialized; defensive in case called early
    try {
      tzdata.initializeTimeZones();
    } catch (_) {}

    tz.TZDateTime tzNow;
    final useLoc = _localTz ?? tz.local;
    try {
      tzNow = tz.TZDateTime.now(useLoc);
    } catch (e) {
      // If tz.local isn't available for some reason, fall back to system local
      final sysNow = DateTime.now();
      tzNow = tz.TZDateTime.from(sysNow, tz.UTC);
    }

    // taskDate and taskTime are guaranteed non-null by the check at the start of this method
    final candidate = tz.TZDateTime(
      useLoc,
      task.taskDate!.year,
      task.taskDate!.month,
      task.taskDate!.day,
      task.taskTime!.hour,
      task.taskTime!.minute,
    );

    if (task.isRecurring && task.recurringPattern != null) {
      // For recurring tasks, if time is in the past for the selected date, compute next occurrence.
      if (candidate.isAfter(tzNow)) return candidate;
      final nextDate = task.recurringPattern!.getNextOccurrence(tzNow);
      if (nextDate == null) return null;
      return tz.TZDateTime(
        tz.local,
        nextDate.year,
        nextDate.month,
        nextDate.day,
        task.taskTime!.hour,
        task.taskTime!.minute,
      );
    } else {
      // One-time task: schedule only if in the future
      // Use a small tolerance (120 seconds) and compare in seconds to avoid
      // truncation caused by minute-level rounding.
      const tolerance = Duration(seconds: 120);
      return candidate.isAfter(tzNow.subtract(tolerance)) ? candidate : null;
    }
  }

  Future<NotificationDetails> _alarmNotificationDetailsFromPrefs() async {
    final prefs = NotificationPreferencesService();
    final soundKey = await prefs.getDefaultSound();

    // Android configuration based on selected default
    AndroidNotificationDetails androidDetails;
    if (soundKey == NotificationPreferencesService.soundSilent) {
      androidDetails = const AndroidNotificationDetails(
        'task_alarms',
        'Task Alarms',
        channelDescription: 'Time-based task alarms',
        importance: Importance.max,
        priority: Priority.high,
        playSound: false,
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(''),
      );
    } else if (soundKey == NotificationPreferencesService.soundAlarm) {
      androidDetails = const AndroidNotificationDetails(
        'task_alarms',
        'Task Alarms',
        channelDescription: 'Time-based task alarms',
        importance: Importance.max,
        priority: Priority.high,
        playSound: false, // Disabled to prevent conflicts with alarm package
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        // Request full-screen intent so the notification behaves like a real alarm
        // (requires device to allow full-screen intents and DND settings may still block sound).
        fullScreenIntent: true,
        styleInformation: BigTextStyleInformation(''),
      );
    } else if (soundKey == NotificationPreferencesService.soundRingtone) {
      androidDetails = const AndroidNotificationDetails(
        'task_alarms',
        'Task Alarms',
        channelDescription: 'Time-based task alarms',
        importance: Importance.max,
        priority: Priority.high,
        playSound: false, // Disabled to prevent conflicts with alarm package
        category: AndroidNotificationCategory.reminder,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        styleInformation: BigTextStyleInformation(''),
      );
    } else {
      // Default Android notification sound (no explicit sound set)
      androidDetails = const AndroidNotificationDetails(
        'task_alarms',
        'Task Alarms',
        channelDescription: 'Time-based task alarms',
        importance: Importance.max,
        priority: Priority.high,
        playSound: false, // Disabled to prevent conflicts with alarm package
        category: AndroidNotificationCategory.reminder,
        // For default/regular reminders we do not request full screen
        styleInformation: BigTextStyleInformation(''),
      );
    }

    const iOS = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );
    return NotificationDetails(android: androidDetails, iOS: iOS);
  }

  /// Schedule (or reschedule) the alarm for a task. If no time is set or the time is in the past
  /// and not recurring, existing alarm is cancelled.
  /// This version is for use in repositories and services where context is not available.
  Future<void> scheduleForTask(TaskModel task) async {
    // Don't schedule alarms for tasks without an explicit time set
    if (task.taskTime == null || task.taskDate == null) {
      developer.log(
        '[TaskAlarmService] No time set for task id=${task.id}, skipping alarm',
      );
      // Cancel any existing alarms for this task
      if (task.id != null) {
        await cancelForTaskId(task.id!);
      }
      return;
    }
    await _scheduleForTaskInternal(task, null);
  }

  /// Schedule (or reschedule) the alarm for a task with context for permission dialogs.
  /// This version is for use in UI components where context is available.
  Future<void> scheduleForTaskWithContext(
    TaskModel task,
    BuildContext context,
  ) async {
    await _scheduleForTaskInternal(task, context);
  }

  /// Internal method that handles the actual scheduling logic
  Future<void> _scheduleForTaskInternal(
    TaskModel task,
    BuildContext? context,
  ) async {
    if (task.id == null) {
      developer.log(
        '[TaskAlarmService] Cannot schedule alarm for task with null id',
      );
      return;
    }
    try {
      // Ensure timezone data and local zone are initialized. Scheduling may be
      // invoked before app-wide initialization (main.dart) completes, so do a
      // defensive initialization here to guarantee tz.local is usable.
      try {
        tzdata.initializeTimeZones();
        final String tzName = await FlutterTimezone.getLocalTimezone();
        final loc = tz.getLocation(tzName);
        tz.setLocalLocation(loc);
        _localTz = loc;
        developer.log('[TaskAlarmService] Timezone set to $tzName');
      } catch (e) {
        developer.log(
          '[TaskAlarmService] Warning: failed to initialize timezone: $e',
        );
        // Continue — tz may still work with system default
      }

      final plugin = notificationPlugin;
      // Ensure we have notification permission (Android 13+ requires runtime permission)
      try {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          developer.log(
            '[TaskAlarmService] Notification permission not granted. Requesting...',
          );
          final res = await Permission.notification.request();
          if (!res.isGranted) {
            developer.log(
              '[TaskAlarmService] Notification permission denied by user. Will not schedule alarm.',
            );
            return;
          }
          developer.log(
            '[TaskAlarmService] Notification permission granted after request.',
          );
        }
      } catch (e) {
        developer.log(
          '[TaskAlarmService] Could not check/request notification permission: $e',
        );
      }
      // Verify both time and date are set before scheduling
      if (task.taskTime == null || task.taskDate == null) {
        developer.log(
          '[TaskAlarmService] Cannot schedule alarm - task has no time or date set',
        );
        // Cancel any existing alarms for this task
        if (task.id != null) {
          await plugin.cancel(_notifIdForTaskId(task.id!));
        }
        return;
      }

      final scheduled = _scheduledDateTimeFor(task);
      final notifId = _notifIdForTaskId(task.id!);
      // Debug time comparison (use tz-aware values)
      tz.TZDateTime? tzScheduled = scheduled;
      final useLoc = _localTz ?? tz.local;
      tz.TZDateTime tzNow;
      try {
        tzNow = tz.TZDateTime.now(useLoc);
      } catch (e) {
        tzNow = tz.TZDateTime.from(DateTime.now(), tz.UTC);
      }

      developer.log(
        '[TaskAlarmService] scheduleForTask: task.id=${task.id}, computed scheduled=$tzScheduled, notifId=$notifId',
      );
      developer.log('[TaskAlarmService] tzNow: $tzNow');
      developer.log('[TaskAlarmService] tzScheduled: $tzScheduled');
      if (tzScheduled != null) {
        developer.log(
          '[TaskAlarmService] Time difference (seconds): ${tzScheduled.difference(tzNow).inSeconds}',
        );
      }
      try {
        final localName = (_localTz ?? tz.local).name;
        developer.log('[TaskAlarmService] tz.local: $localName');
      } catch (e) {
        developer.log('[TaskAlarmService] tz.local not available: $e');
      }

      // Cancel any existing scheduled alarm for this task before rescheduling
      try {
        await plugin.cancel(notifId);
      } catch (_) {}

      if (scheduled == null) {
        developer.log(
          '[TaskAlarmService] No future time to schedule for task id=${task.id}',
        );
        return;
      }

      final tzTime = scheduled; // scheduled is tz.TZDateTime by new helper

      final details = await _alarmNotificationDetailsFromPrefs();
      final title = 'Task Reminder';
      // Format time if set
      final timeStr =
          task.taskTime != null
              ? ' at ${task.taskTime!.hour.toString().padLeft(2, '0')}:${task.taskTime!.minute.toString().padLeft(2, '0')}'
              : '';
      final body = '${task.taskName}$timeStr';

      // Check if exact alarms can be scheduled using AlarmManager API
      bool exactScheduled = false;
      final canScheduleExact = await _canScheduleExactAlarms();

      developer.log(
        '[TaskAlarmService] Can schedule exact alarms: $canScheduleExact',
      );

      if (canScheduleExact) {
        // Try exact scheduling if allowed
        try {
          // First try to schedule a true system alarm (AlarmManager.setAlarmClock)
          await _scheduleSystemAlarm(notifId, tzTime, title, body, task.id);
          // Also schedule plugin notification as a backup
          await plugin.zonedSchedule(
            notifId,
            title,
            body,
            tzTime,
            details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents:
                task.isRecurring ? DateTimeComponents.time : null,
            payload: '${task.id}',
          );
          exactScheduled = true;
          developer.log(
            '[TaskAlarmService] Exact alarm scheduled successfully for task id=${task.id}',
          );
        } catch (e) {
          developer.log(
            '[TaskAlarmService] Exact alarm failed despite permission: $e',
          );
        }
      } else {
        developer.log(
          '[TaskAlarmService] Exact alarms not allowed, requesting permission',
        );

        if (context != null) {
          await _showExactAlarmDialog(context);
        } else {
          // No UI context available (scheduling from background/service). Try
          // to trigger the system intent that requests exact alarm permission
          // so the user can grant it from system settings.
          developer.log(
            '[TaskAlarmService] No BuildContext available; attempting platform request for exact alarm permission',
          );
          final requested = await _requestExactAlarmPermission();
          developer.log(
            '[TaskAlarmService] Platform requestExactAlarmPermission returned: $requested',
          );
        }
      }

      // If exact scheduling failed, use multi-notification approach
      if (!exactScheduled) {
        developer.log(
          '[TaskAlarmService] Using multi-notification approach for reliable minute-level precision',
        );

        try {
          // Compare tz-aware now to tzTime
          tz.TZDateTime tzNow2;
          try {
            tzNow2 = tz.TZDateTime.now(tz.local);
          } catch (e) {
            tzNow2 = tz.TZDateTime.from(DateTime.now(), tz.UTC);
          }

          final timeDiff = tzTime.difference(tzNow2);

          if (timeDiff.inSeconds > 0) {
            // Schedule multiple notifications around the target time for better precision
            final targetMinute = tzTime.minute;
            final targetHour = tzTime.hour;

            // Schedule notifications at: target-2min, target-1min, target, target+1min
            final notificationTimes = [
              tz.TZDateTime(
                useLoc,
                tzTime.year,
                tzTime.month,
                tzTime.day,
                tzTime.hour,
                tzTime.minute,
              ).subtract(const Duration(minutes: 2)),
              tz.TZDateTime(
                useLoc,
                tzTime.year,
                tzTime.month,
                tzTime.day,
                tzTime.hour,
                tzTime.minute,
              ).subtract(const Duration(minutes: 1)),
              tzTime, // Exact target time
              tz.TZDateTime(
                useLoc,
                tzTime.year,
                tzTime.month,
                tzTime.day,
                tzTime.hour,
                tzTime.minute,
              ).add(const Duration(minutes: 1)),
            ];

            int notificationCount = 0;
            for (int i = 0; i < notificationTimes.length; i++) {
              final notificationTime = notificationTimes[i];
              final notificationId = notifId + i;

              // Skip past times (tz-aware)
              if (notificationTime.isAfter(tzNow2)) {
                await plugin.zonedSchedule(
                  notificationId,
                  i == 2 ? title : '$title (${i < 2 ? 'Early' : 'Late'})',
                  body,
                  notificationTime,
                  details,
                  androidScheduleMode:
                      AndroidScheduleMode.inexactAllowWhileIdle,
                  matchDateTimeComponents:
                      task.isRecurring ? DateTimeComponents.time : null,
                  payload: '${task.id}_${i}',
                );
                notificationCount++;
              }
            }

            developer.log(
              '[TaskAlarmService] Scheduled $notificationCount notifications around target time for task id=${task.id}',
            );
            developer.log(
              '[TaskAlarmService] Target: ${targetHour.toString().padLeft(2, '0')}:${targetMinute.toString().padLeft(2, '0')}',
            );
            developer.log(
              '[TaskAlarmService] Notifications will fire between 2 minutes before and 1 minute after target time.',
            );
          } else {
            developer.log(
              '[TaskAlarmService] Task time is in the past, cannot schedule alarm',
            );
          }
        } catch (e) {
          developer.log(
            '[TaskAlarmService] Multi-notification scheduling failed: $e',
          );
        }
      }

      // Diagnostic: print pending notifications the plugin currently knows about
      try {
        final pending = await plugin.pendingNotificationRequests();
        developer.log(
          '[TaskAlarmService] pendingNotificationRequests count=${pending.length}',
        );
        for (final p in pending) {
          developer.log(
            '[TaskAlarmService] pending: id=${p.id}, title=${p.title}, body=${p.body}, payload=${p.payload}',
          );
        }
      } catch (e) {
        developer.log(
          '[TaskAlarmService] Could not read pendingNotificationRequests: $e',
        );
      }

      developer.log(
        '[TaskAlarmService] Scheduled alarm for task id=${task.id} at $scheduled',
      );
    } catch (e, st) {
      developer.log(
        '[TaskAlarmService] Failed to schedule alarm for task id=${task.id}: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Cancel the alarm for a task by id
  Future<void> cancelForTaskId(int taskId) async {
    try {
      final plugin = notificationPlugin;
      final notifId = _notifIdForTaskId(taskId);

      // Cancel all notifications for this task (main + 3 additional ones)
      for (int i = 0; i < 4; i++) {
        await plugin.cancel(notifId + i);
      }
      // Also cancel any system alarm scheduled via AlarmManager
      await _cancelSystemAlarm(notifId);

      developer.log(
        '[TaskAlarmService] Canceled all notifications for task id=$taskId',
      );
    } catch (e) {
      developer.log(
        '[TaskAlarmService] Failed to cancel alarm for task id=$taskId: $e',
      );
    }
  }
}