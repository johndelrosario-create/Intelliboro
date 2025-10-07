import 'dart:developer' as developer;
import 'package:alarm/alarm.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter_timezone/flutter_timezone.dart';

class FlutterAlarmService {
  static final FlutterAlarmService _instance = FlutterAlarmService._internal();
  factory FlutterAlarmService() => _instance;
  FlutterAlarmService._internal();

  bool _isInitialized = false;

  /// Initialize the alarm service
  Future<void> initialize() async {
    if (_isInitialized) {
      developer.log('[FlutterAlarmService] Already initialized, skipping');
      return;
    }

    developer.log('[FlutterAlarmService] Starting initialization...');
    try {
      await Alarm.init();
      developer.log('[FlutterAlarmService] Alarm.init() completed');

      // Initialize timezone data
      try {
        tzdata.initializeTimeZones();
        final String tzName = await FlutterTimezone.getLocalTimezone();
        final loc = tz.getLocation(tzName);
        tz.setLocalLocation(loc);
        developer.log('[FlutterAlarmService] Timezone set to $tzName');
      } catch (e) {
        developer.log(
          '[FlutterAlarmService] Warning: failed to initialize timezone: $e',
        );
      }

      _isInitialized = true;
      developer.log('[FlutterAlarmService] Initialized successfully');
    } catch (e) {
      developer.log('[FlutterAlarmService] Failed to initialize: $e');
      rethrow;
    }
  }

  /// Compute a stable alarm id from the task id
  int _alarmIdForTaskId(int taskId) => 100000 + taskId;

  /// Build the scheduled DateTime for a task
  DateTime? _scheduledDateTimeFor(TaskModel task) {
    if (task.taskTime == null || task.taskDate == null) {
      developer.log(
        '[FlutterAlarmService] _scheduledDateTimeFor: task has no time/date set',
      );
      return null;
    }

    final now = DateTime.now();
    final candidate = DateTime(
      task.taskDate!.year,
      task.taskDate!.month,
      task.taskDate!.day,
      task.taskTime!.hour,
      task.taskTime!.minute,
    );

    if (task.isRecurring && task.recurringPattern != null) {
      // For recurring tasks, if time is in the past for the selected date, compute next occurrence
      if (candidate.isAfter(now)) return candidate;
      final nextDate = task.recurringPattern!.getNextOccurrence(now);
      if (nextDate == null) return null;
      return DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        task.taskTime!.hour,
        task.taskTime!.minute,
      );
    } else {
      // One-time task: schedule only if in the future
      const tolerance = Duration(seconds: 120);
      return candidate.isAfter(now.subtract(tolerance)) ? candidate : null;
    }
  }

  /// Schedule an alarm for a task
  Future<void> scheduleForTask(TaskModel task) async {
    developer.log(
      '[FlutterAlarmService] scheduleForTask called for task id=${task.id}, name="${task.taskName}"',
    );

    if (!_isInitialized) {
      developer.log(
        '[FlutterAlarmService] Not initialized, initializing now...',
      );
      await initialize();
    }

    if (task.id == null) {
      developer.log(
        '[FlutterAlarmService] Cannot schedule alarm for task with null id',
      );
      return;
    }

    if (task.taskTime == null || task.taskDate == null) {
      developer.log(
        '[FlutterAlarmService] No time set for task id=${task.id}, canceling any existing alarm',
      );
      await cancelForTaskId(task.id!);
      return;
    }

    try {
      final scheduled = _scheduledDateTimeFor(task);
      if (scheduled == null) {
        developer.log(
          '[FlutterAlarmService] No future time to schedule for task id=${task.id}',
        );
        await cancelForTaskId(task.id!);
        return;
      }

      final alarmId = _alarmIdForTaskId(task.id!);
      developer.log(
        '[FlutterAlarmService] Computed alarm time: $scheduled for task id=${task.id}',
      );

      // Format time if set
      final timeStr =
          task.taskTime != null
              ? ' at ${task.taskTime!.hour.toString().padLeft(2, '0')}:${task.taskTime!.minute.toString().padLeft(2, '0')}'
              : '';

      final alarmSettings = AlarmSettings(
        id: alarmId,
        dateTime: scheduled,
        assetAudioPath: 'assets/audio/alarm.mp3',
        loopAudio: true,
        vibrate: true,
        volumeSettings: VolumeSettings.fixed(
          volume: 0.8,
        ), // Set explicit volume
        warningNotificationOnKill: true,
        androidFullScreenIntent: true,
        notificationSettings: NotificationSettings(
          title: 'Task Reminder',
          body: '${task.taskName}$timeStr',
          stopButton: 'Stop',
          icon: 'notification_icon',
        ),
      );

      developer.log(
        '[FlutterAlarmService] Calling Alarm.set with alarmId=$alarmId, dateTime=$scheduled',
      );
      await Alarm.set(alarmSettings: alarmSettings);
      developer.log(
        '[FlutterAlarmService] ✅ Successfully scheduled alarm for task id=${task.id} at $scheduled (alarmId=$alarmId)',
      );

      // Verify the alarm was set
      final allAlarms = await Alarm.getAlarms();
      final isSet = allAlarms.any((a) => a.id == alarmId);
      developer.log(
        '[FlutterAlarmService] Verification: Alarm $alarmId is ${isSet ? "CONFIRMED" : "NOT FOUND"} in alarm list',
      );
      developer.log(
        '[FlutterAlarmService] Total alarms currently set: ${allAlarms.length}',
      );
    } catch (e, st) {
      developer.log(
        '[FlutterAlarmService] Failed to schedule alarm for task id=${task.id}: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Cancel alarm for a task by id
  Future<void> cancelForTaskId(int taskId) async {
    developer.log(
      '[FlutterAlarmService] cancelForTaskId called for task id=$taskId',
    );

    if (!_isInitialized) {
      await initialize();
    }

    try {
      final alarmId = _alarmIdForTaskId(taskId);
      developer.log(
        '[FlutterAlarmService] Calling Alarm.stop for alarmId=$alarmId',
      );
      await Alarm.stop(alarmId);
      developer.log(
        '[FlutterAlarmService] ✅ Canceled alarm for task id=$taskId (alarmId=$alarmId)',
      );
    } catch (e) {
      developer.log(
        '[FlutterAlarmService] Failed to cancel alarm for task id=$taskId: $e',
      );
    }
  }

  /// Cancel all alarms
  Future<void> cancelAll() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      await Alarm.stopAll();
      developer.log('[FlutterAlarmService] Canceled all alarms');
    } catch (e) {
      developer.log('[FlutterAlarmService] Failed to cancel all alarms: $e');
    }
  }

  /// Get all currently scheduled alarms
  Future<List<AlarmSettings>> get alarms async => await Alarm.getAlarms();

  /// Check if a specific alarm is set
  Future<bool> isAlarmSet(int taskId) async {
    final alarmId = _alarmIdForTaskId(taskId);
    final allAlarms = await Alarm.getAlarms();
    return allAlarms.any((alarm) => alarm.id == alarmId);
  }

  /// Get the scheduled time for a task's alarm
  Future<DateTime?> getAlarmTime(int taskId) async {
    final alarmId = _alarmIdForTaskId(taskId);
    final allAlarms = await Alarm.getAlarms();
    final alarmSettings =
        allAlarms.where((alarm) => alarm.id == alarmId).firstOrNull;
    return alarmSettings?.dateTime;
  }
}
