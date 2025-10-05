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
    if (_isInitialized) return;

    try {
      await Alarm.init();

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
    if (!_isInitialized) {
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

      // Format time if set
      final timeStr =
          task.taskTime != null
              ? ' at ${task.taskTime!.hour.toString().padLeft(2, '0')}:${task.taskTime!.minute.toString().padLeft(2, '0')}'
              : '';

      final alarmSettings = AlarmSettings(
        id: alarmId,
        dateTime: scheduled,
        // Use empty string to trigger system default alarm sound
        // This avoids needing custom audio assets
        assetAudioPath: '',
        loopAudio: true,
        vibrate: true,
        // Use null volume to let system handle alarm volume channel
        // This prevents the media volume slider from appearing
        volumeSettings: VolumeSettings.fixed(volume: null),
        warningNotificationOnKill: true,
        androidFullScreenIntent: true,
        notificationSettings: NotificationSettings(
          title: 'Task Reminder',
          body: '${task.taskName}$timeStr',
          stopButton: 'Stop',
          icon: 'notification_icon',
        ),
      );

      await Alarm.set(alarmSettings: alarmSettings);

      developer.log(
        '[FlutterAlarmService] Scheduled alarm for task id=${task.id} at $scheduled (alarmId=$alarmId)',
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
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final alarmId = _alarmIdForTaskId(taskId);
      await Alarm.stop(alarmId);
      developer.log(
        '[FlutterAlarmService] Canceled alarm for task id=$taskId (alarmId=$alarmId)',
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