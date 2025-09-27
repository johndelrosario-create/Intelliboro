import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/model/task_history_model.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'package:intelliboro/services/database_service.dart';
import 'package:intelliboro/repository/task_history_repository.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/services/geofencing_service.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intelliboro/services/notification_service.dart'
    show notificationPlugin;

/// Request emitted when a higher-priority task arrives and a user decision is needed.
class TaskSwitchRequest {
  final TaskModel newTask;
  final Completer<bool> _completer;
  TaskSwitchRequest(this.newTask) : _completer = Completer<bool>();

  /// Complete with true to start the new task now, false to snooze it.
  void respond(bool startNow) {
    if (!_completer.isCompleted) _completer.complete(startNow);
  }

  /// Internal future used by the service to wait for decision.
  Future<bool> get future => _completer.future;
}

/// Service responsible for managing task timers and active task tracking
class TaskTimerService extends ChangeNotifier {
  static final TaskTimerService _instance = TaskTimerService._internal();
  factory TaskTimerService() => _instance;
  TaskTimerService._internal();

  // Initialize async state (load persisted pending tasks)
  Future<void> loadPersistedPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final k in keys) {
        if (k.startsWith('pending_task_')) {
          final idStr = k.substring('pending_task_'.length);
          final parsed = int.tryParse(idStr);
          if (parsed == null) continue;
          final millis = prefs.getInt(k);
          if (millis == null) continue;
          final until = DateTime.fromMillisecondsSinceEpoch(millis);
          if (until.isAfter(DateTime.now())) {
            _pendingUntil[parsed] = until;
          } else {
            // expired - remove persisted key
            try {
              await prefs.remove(k);
            } catch (_) {}
          }
        }
      }
      if (_pendingUntil.isNotEmpty) {
        developer.log(
          '[TaskTimerService] Loaded persisted pending tasks: ${_pendingUntil.keys.toList()}',
        );
        try {
          tasksChanged.value = true;
        } catch (_) {}
        notifyListeners();
      }
    } catch (e) {
      developer.log(
        '[TaskTimerService] Failed to load persisted pending tasks: $e',
      );
    }
  }

  // Current active task and timer
  TaskModel? _activeTask;
  DateTime? _startTime;
  Timer? _timer;
  Duration _elapsedTime = Duration.zero;
  bool _isPaused = false;

  final Map<int, Stopwatch> _runningTimers = {};
  // Pending tasks mapped to a DateTime until which they are snoozed
  final Map<int, DateTime> _pendingUntil = {};

  /// Default snooze duration used when putting tasks into pending.
  /// Can be changed by the user via UI.
  Duration defaultSnoozeDuration = const Duration(minutes: 5);
  final TaskHistoryRepository _historyRepo = TaskHistoryRepository();
  // Stream controller for switch requests (broadcast so multiple listeners may observe)
  final StreamController<TaskSwitchRequest> _switchController =
      StreamController.broadcast();
  // Map of pending switch requests accessible by a generated id (for notification actions)
  final Map<String, TaskSwitchRequest> _pendingSwitchRequests = {};
  // Notifier to signal when task records change (completed/rescheduled/deleted)
  final ValueNotifier<bool> tasksChanged = ValueNotifier<bool>(false);

  // Getters
  TaskModel? get activeTask => _activeTask;
  DateTime? get startTime => _startTime;
  Duration get elapsedTime => _elapsedTime;
  bool get isPaused => _isPaused;
  bool get hasActiveTask => _activeTask != null;

  /// Stream of switch requests that UI can listen to and prompt the user.
  Stream<TaskSwitchRequest> get switchRequests => _switchController.stream;

  /// Respond to a pending switch request by id (used by notification handler).
  bool respondSwitchRequest(String id, bool startNow) {
    final req = _pendingSwitchRequests.remove(id);
    if (req == null) return false;
    try {
      req.respond(startNow);
      return true;
    } catch (e) {
      developer.log('[TaskTimerService] respondSwitchRequest error: $e');
      return false;
    }
  }

  /// Start timing a task
  Future<bool> startTask(TaskModel task, {bool strictPriority = false}) async {
    try {
      developer.log(
        '[TaskTimerService] Attempting to start task: ${task.taskName}',
      );

      // Check if there's already an active task
      if (_activeTask != null) {
        developer.log(
          '[TaskTimerService] Active task found: ${_activeTask!.taskName}',
        );

        // Compare priorities - higher effective priority wins
        final currentPriority =
            strictPriority
                ? _activeTask!.taskPriority.toDouble()
                : _activeTask!.getEffectivePriority();
        final newPriority =
            strictPriority
                ? task.taskPriority.toDouble()
                : task.getEffectivePriority();

        if (newPriority > currentPriority) {
          developer.log(
            '[TaskTimerService] New task has higher priority ($newPriority vs $currentPriority), switching tasks',
          );

          // Emit a switch request and wait for user's decision.
          try {
            final req = TaskSwitchRequest(task);
            // register request and notify UI listeners
            final switchId =
                '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';
            _pendingSwitchRequests[switchId] = req;
            _switchController.add(req);

            // Post a local notification so user can respond from background
            try {
              final plugin = notificationPlugin;
              const AndroidNotificationDetails androidDetails =
                  AndroidNotificationDetails(
                    'geofence_alerts',
                    'Geofence Alerts',
                    channelDescription: 'Switch requests for tasks',
                    importance: Importance.max,
                    priority: Priority.high,
                    playSound: true,
                    styleInformation: BigTextStyleInformation(''),
                    actions: <AndroidNotificationAction>[
                      AndroidNotificationAction(
                        'com.intelliboro.DO_NOW',
                        'Start Now',
                        showsUserInterface: true,
                        cancelNotification: true,
                      ),
                      AndroidNotificationAction(
                        'com.intelliboro.DO_LATER',
                        'Snooze',
                        showsUserInterface: false,
                        cancelNotification: false,
                      ),
                    ],
                  );
              final details = NotificationDetails(android: androidDetails);
              final payload = jsonEncode({
                'switchRequestId': switchId,
                'taskId': task.id,
              });
              await plugin.show(
                Random().nextInt(2147483647),
                'Higher priority task',
                '"${task.taskName}" is higher priority. Start now or snooze?',
                details,
                payload: payload,
              );
            } catch (e) {
              developer.log(
                '[TaskTimerService] Failed to post switch notification: $e',
              );
            }

            // Wait up to 60 seconds for user decision; default to snooze if none.
            final decision = await req.future.timeout(
              const Duration(seconds: 60),
              onTimeout: () => false,
            );
            if (decision == true) {
              // User chose to start the new task: stop current and start new
              await _stopCurrentTaskAndReschedule();
              return _startTaskTimer(task);
            } else {
              // User chose to snooze (or timed out): add to pending using default snooze
              await _addToPending(task, defaultSnoozeDuration);
              return false;
            }
          } catch (e, st) {
            developer.log(
              '[TaskTimerService] Error handling switch request: $e',
              error: e,
              stackTrace: st,
            );
            // On error: safe fallback is to snooze the incoming task
            await _addToPending(task, defaultSnoozeDuration);
            return false;
          }
        } else {
          developer.log(
            '[TaskTimerService] Current task has higher/equal priority ($currentPriority vs $newPriority), rescheduling new task',
          );

          // Add the new task to pending (snoozed) instead of rescheduling
          // Default snooze duration is 5 minutes for pending tasks
          await _addToPending(task, const Duration(minutes: 5));
          return false; // Indicate task was not started (pending)
        }
      } else {
        // No active task, start this one
        final started = _startTaskTimer(task);
        if (started) {
          // Persist active task id asynchronously
          _persistActiveTaskId(task.id);
        }
        return started;
      }
    } catch (e, stackTrace) {
      developer.log(
        '[TaskTimerService] Error starting task',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Persist the currently active task id in SharedPreferences for background isolates
  Future<void> _persistActiveTaskId(int? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id != null) {
        await prefs.setInt('active_task_id', id);
        developer.log('[TaskTimerService] Persisted active_task_id=$id');
      }
    } catch (e) {
      developer.log('[TaskTimerService] Failed to persist active_task_id: $e');
    }
  }

  /// Add [task] to pending list until [snoozeDuration] has passed.
  Future<void> _addToPending(TaskModel task, Duration snoozeDuration) async {
    final id = task.id;
    if (id == null) {
      developer.log(
        '[TaskTimerService] Cannot add to pending: task id is null',
      );
      return;
    }
    // Allow per-task snooze override via SharedPreferences: 'snooze_minutes_task_{id}'
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'snooze_minutes_task_$id';
      final override = prefs.getInt(key);
      if (override != null && override > 0) {
        snoozeDuration = Duration(minutes: override);
        developer.log(
          '[TaskTimerService] Using per-task snooze override for task $id: ${override}m',
        );
      }
    } catch (e) {
      developer.log(
        '[TaskTimerService] Failed to read per-task snooze override: $e',
      );
    }

    final until = DateTime.now().add(snoozeDuration);
    _pendingUntil[id] = until;
    developer.log(
      '[TaskTimerService] Task ${task.taskName} (id=$id) added to pending until $until',
    );

    // Signal to any listeners (UI) that tasks have changed so lists refresh.
    try {
      tasksChanged.value = true;
    } catch (_) {}

    // Schedule timer to clear pending state after snooze duration and attempt geofence recreation
    Timer(snoozeDuration, () async {
      try {
        if (_pendingUntil.containsKey(id) &&
            _pendingUntil[id]!.isBefore(DateTime.now())) {
          _pendingUntil.remove(id);
          developer.log(
            '[TaskTimerService] Pending snooze expired for task id=$id',
          );

          // Attempt to recreate native geofence for this task if it existed
          try {
            if (task.geofenceId != null && task.geofenceId!.isNotEmpty) {
              final storage = GeofenceStorage();
              final geofenceData = await storage.getGeofenceById(
                task.geofenceId!,
              );
              if (geofenceData != null) {
                await GeofencingService().createGeofence(
                  geometry: Point(
                    coordinates: Position(
                      geofenceData.longitude,
                      geofenceData.latitude,
                    ),
                  ),
                  radiusMeters: geofenceData.radiusMeters,
                  customId: geofenceData.id,
                  fillColor: Color(
                    int.parse(
                      geofenceData.fillColor.startsWith('0x')
                          ? geofenceData.fillColor
                          : '0x${geofenceData.fillColor}',
                    ),
                  ),
                  fillOpacity: geofenceData.fillOpacity,
                  strokeColor: Color(
                    int.parse(
                      geofenceData.strokeColor.startsWith('0x')
                          ? geofenceData.strokeColor
                          : '0x${geofenceData.strokeColor}',
                    ),
                  ),
                  strokeWidth: geofenceData.strokeWidth,
                );
                developer.log(
                  '[TaskTimerService] Re-created native geofence for task id=$id (geofence ${task.geofenceId}) after snooze',
                );
              } else {
                developer.log(
                  '[TaskTimerService] No geofence data found in DB for id=${task.geofenceId}',
                );
              }
            }
          } catch (e, st) {
            developer.log(
              '[TaskTimerService] Error re-creating geofence after snooze for task id=$id: $e',
              error: e,
              stackTrace: st,
            );
          }

          notifyListeners();
          try {
            tasksChanged.value = true;
          } catch (_) {}
        }
      } catch (e) {
        developer.log(
          '[TaskTimerService] Error clearing pending state for task id=$id: $e',
        );
      }
    });

    // Notify listeners so UI can update pending indicators
    notifyListeners();
  }

  /// Check whether a task is currently pending (snoozed)
  bool isPending(int taskId) {
    final until = _pendingUntil[taskId];
    if (until == null) return false;
    return until.isAfter(DateTime.now());
  }

  /// Returns the DateTime until which [taskId] is pending, or null.
  DateTime? getPendingUntil(int taskId) => _pendingUntil[taskId];

  /// Returns remaining duration for pending state, or null if not pending.
  Duration? getPendingRemaining(int taskId) {
    final until = _pendingUntil[taskId];
    if (until == null) return null;
    final rem = until.difference(DateTime.now());
    return rem.isNegative ? Duration.zero : rem;
  }

  /// Update the default snooze duration (user-facing setting).
  void setDefaultSnoozeDuration(Duration duration) {
    defaultSnoozeDuration = duration;
    notifyListeners();
  }

  /// Public API to add [task] to pending for [snoozeDuration].
  Future<void> addToPending(TaskModel task, Duration snoozeDuration) async {
    return _addToPending(task, snoozeDuration);
  }

  /// Internal method to start the timer for a task
  bool _startTaskTimer(TaskModel task) {
    try {
      _activeTask = task;
      _startTime = DateTime.now();
      _isPaused = false;
      _elapsedTime = Duration.zero;

      // Start the timer that updates every second
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_startTime != null) {
          _elapsedTime = DateTime.now().difference(_startTime!);
          notifyListeners();
        }
      });

      developer.log(
        '[TaskTimerService] Started timer for task: ${task.taskName}',
      );

      // Active task started (persistence handled by caller)

      // Ensure UI updates to reflect task timer start
      notifyListeners();
      return true;
    } catch (e) {
      developer.log('[TaskTimerService] Error starting task timer: $e');
      return false;
    }
  }

  /// Pause the currently active task's timer.
  /// This cancels the periodic UI timer but preserves elapsed time so it can be resumed.
  Future<void> pauseTask() async {
    if (_activeTask == null || _startTime == null) {
      developer.log('[TaskTimerService] No active task to pause');
      return;
    }

    if (_isPaused) {
      developer.log('[TaskTimerService] Task already paused');
      return;
    }

    // Capture current elapsed time and cancel periodic updates
    _elapsedTime = DateTime.now().difference(_startTime!);
    _timer?.cancel();
    _timer = null;
    _isPaused = true;
    developer.log(
      '[TaskTimerService] Paused task: ${_activeTask!.taskName}, elapsed: ${_formatDuration(_elapsedTime)}',
    );
    notifyListeners();
  }

  /// Resume a previously paused task timer.
  Future<void> resumeTask() async {
    if (_activeTask == null || _startTime == null) {
      developer.log('[TaskTimerService] No active task to resume');
      return;
    }

    if (!_isPaused) {
      developer.log('[TaskTimerService] Task is not paused');
      return;
    }

    // Restore startTime so elapsed continues from previous elapsed time
    _startTime = DateTime.now().subtract(_elapsedTime);
    _isPaused = false;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startTime != null) {
        _elapsedTime = DateTime.now().difference(_startTime!);
        notifyListeners();
      }
    });

    developer.log(
      '[TaskTimerService] Resumed task: ${_activeTask!.taskName}, elapsed: ${_formatDuration(_elapsedTime)}',
    );
    notifyListeners();
  }

  /// Stop the currently active task, persist history, and mark/reschedule the task as needed.
  /// Returns the duration that was recorded for the stopped task.
  Future<Duration> stopTask() async {
    if (_activeTask == null) {
      developer.log('[TaskTimerService] No active task to stop');
      return Duration.zero;
    }

    // Cancel periodic updates
    _timer?.cancel();
    _timer = null;

    final completionTime = _elapsedTime;
    final task = _activeTask!;

    // Clear in-memory state
    _activeTask = null;
    _startTime = null;
    _elapsedTime = Duration.zero;
    _isPaused = false;

    // Clear persisted active task id
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_task_id');
      developer.log('[TaskTimerService] Cleared persisted active_task_id');
    } catch (e) {
      developer.log(
        '[TaskTimerService] Failed to clear persisted active_task_id: $e',
      );
    }

    // Persist history and handle task completion/reschedule
    await _markTaskCompleted(task, completionTime);

    notifyListeners();
    return completionTime;
  }

  /// Stop current task and reschedule it for later
  Future<void> _stopCurrentTaskAndReschedule() async {
    if (_activeTask == null) return;

    final taskToReschedule = _activeTask!;

    // Stop the timer
    _timer?.cancel();
    _timer = null;
    _activeTask = null;
    _startTime = null;
    _elapsedTime = Duration.zero;

    // Clear persisted active task id
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_task_id');
      developer.log(
        '[TaskTimerService] Cleared persisted active_task_id (reschedule)',
      );
    } catch (e) {
      developer.log(
        '[TaskTimerService] Failed to clear persisted active_task_id: $e',
      );
    }

    // Reschedule the interrupted task
    await _rescheduleTask(taskToReschedule);
  }

  /// Reschedule a task to a later time
  Future<void> _rescheduleTask(TaskModel task) async {
    try {
      // Calculate new time - add 1 hour to current time or original time, whichever is later
      final now = DateTime.now();
      final originalDateTime = DateTime(
        task.taskDate.year,
        task.taskDate.month,
        task.taskDate.day,
        task.taskTime.hour,
        task.taskTime.minute,
      );

      final baseTime = originalDateTime.isAfter(now) ? originalDateTime : now;
      final newDateTime = baseTime.add(const Duration(hours: 1));

      // Create updated task
      final rescheduledTask = TaskModel(
        id: task.id,
        taskName: task.taskName,
        taskPriority: task.taskPriority,
        taskTime: TimeOfDay(hour: newDateTime.hour, minute: newDateTime.minute),
        taskDate: DateTime(
          newDateTime.year,
          newDateTime.month,
          newDateTime.day,
        ),
        isRecurring: task.isRecurring,
        isCompleted: false, // Ensure it's not marked as completed
        geofenceId: task.geofenceId,
      );

      // Update in database
      await TaskRepository().updateTask(rescheduledTask);

      developer.log(
        '[TaskTimerService] Rescheduled task "${task.taskName}" to ${_formatDateTime(newDateTime)}',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[TaskTimerService] Error rescheduling task',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Reschedule a task manually (for "Do Later" action)
  Future<void> rescheduleTaskLater(TaskModel task) async {
    await _rescheduleTask(task);
  }

  /// Mark a task as completed in the database and save to task history
  Future<void> _markTaskCompleted(
    TaskModel task,
    Duration completionTime,
  ) async {
    try {
      // Save to task history first (so we have a history entry even if update fails)
      await _saveTaskHistory(task, completionTime);

      // If task is recurring, compute next occurrence and update the task to the next date/time.
      if (task.isRecurring) {
        try {
          final next = task.getNextOccurrence(DateTime.now());
          if (next != null) {
            // Update the existing task record to the next occurrence and keep it active (not completed)
            final updatedTask = task.copyWith(
              id: task.id,
              taskDate: DateTime(next.year, next.month, next.day),
              isCompleted: false,
            );
            await TaskRepository().updateTask(updatedTask);
            developer.log(
              '[TaskTimerService] Recurring task updated to next occurrence: ${updatedTask.taskName} -> ${_formatDateTime(next)}',
            );
          } else {
            // No next occurrence: mark as completed as a fallback
            final completedTask = task.copyWith(isCompleted: true);
            await TaskRepository().updateTask(completedTask);
            developer.log(
              '[TaskTimerService] Recurring task had no next occurrence; marked completed: ${task.taskName}',
            );
          }
        } catch (e, st) {
          developer.log(
            '[TaskTimerService] Error handling recurring update: $e',
            error: e,
            stackTrace: st,
          );
          // As a safe fallback, mark task completed so it's removed from active list
          final completedTask = task.copyWith(isCompleted: true);
          await TaskRepository().updateTask(completedTask);
        }
      } else {
        // Non-recurring: mark task as completed so it is removed from active list
        final completedTask = task.copyWith(isCompleted: true);
        await TaskRepository().updateTask(completedTask);
        developer.log(
          '[TaskTimerService] Marked task as completed: ${task.taskName}, Time taken: ${_formatDuration(completionTime)}',
        );
      }
      // Signal listeners that persisted task records changed (so UI can refresh lists)
      try {
        tasksChanged.value = true;
      } catch (_) {}
    } catch (e, stackTrace) {
      developer.log(
        '[TaskTimerService] Error marking task as completed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Save task completion to history
  Future<void> _saveTaskHistory(TaskModel task, Duration completionTime) async {
    try {
      final endTime = DateTime.now();
      final startTime = endTime.subtract(completionTime);

      final historyModel = TaskHistoryModel(
        taskId: task.id,
        taskName: task.taskName,
        taskPriority: task.taskPriority,
        startTime: startTime,
        endTime: endTime,
        duration: completionTime,
        completionDate: DateTime(endTime.year, endTime.month, endTime.day),
        geofenceId: task.geofenceId,
      );

      final db = await DatabaseService().mainDb;
      await DatabaseService().insertTaskHistory(db, historyModel.toMap());

      developer.log(
        '[TaskTimerService] Saved task history for: ${task.taskName}',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[TaskTimerService] Error saving task history',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Get formatted elapsed time string
  String getFormattedElapsedTime() {
    return _formatDuration(_elapsedTime);
  }

  /// Format duration to human readable string
  String _formatDuration(Duration duration) {
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

  /// Format DateTime to readable string
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// Clean up resources
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Start tracking time for [task]. If already running, this is a no-op.
  Future<void> startTimerForTask(TaskModel task) async {
    final id = task.id;
    if (id == null) {
      developer.log('[TaskTimerService] Cannot start timer: task id is null');
      return;
    }
    if (_runningTimers.containsKey(id)) {
      developer.log('[TaskTimerService] Timer already running for task $id');
      return;
    }

    // start in-memory stopwatch
    final sw = Stopwatch()..start();
    _runningTimers[id] = sw;

    // persist a new history start row
    await _historyRepo.startSession(taskId: id, startedAt: DateTime.now());

    developer.log('[TaskTimerService] Started timer for task $id');
  }

  /// Stop the running timer for a task and persist elapsed time.
  Future<void> stopTimerForTask(int taskId) async {
    final sw = _runningTimers.remove(taskId);
    if (sw == null) {
      developer.log('[TaskTimerService] No running timer for task $taskId');
      return;
    }
    sw.stop();
    final duration = sw.elapsed;
    // persist end for latest open session
    await _historyRepo.endSession(
      taskId: taskId,
      endedAt: DateTime.now(),
      duration: duration,
    );
    developer.log(
      '[TaskTimerService] Stopped timer for task $taskId, duration: $duration',
    );
  }

  bool isRunning(int taskId) => _runningTimers.containsKey(taskId);
}