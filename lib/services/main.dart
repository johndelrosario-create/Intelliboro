import 'package:flutter/material.dart';
import 'package:intelliboro/theme.dart';
// permission_handler functions are imported where needed (keep explicit show import later)
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:intelliboro/services/flutter_alarm_service.dart';
import 'dart:async';
import 'package:intelliboro/views/task_list_view.dart';
import 'package:intelliboro/views/task_statistics_view.dart';
import 'package:intelliboro/views/notification_history_view.dart';
import 'package:intelliboro/services/location_service.dart';
import 'package:intelliboro/services/geofencing_service.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intelliboro/services/notification_service.dart'
    show notificationPlugin, initializeNotifications;
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intelliboro/services/text_to_speech_service.dart';
import 'package:intelliboro/views/active_task_view.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/services/pin_service.dart';
import 'package:intelliboro/views/pin_setup_view.dart';
import 'package:intelliboro/views/pin_lock_view.dart';
import 'package:intelliboro/views/settings_view.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:intelliboro/services/audio_focus_guard.dart';
import 'package:intelliboro/services/offline_operation_queue.dart';

const String _kPermissionsPromptShown = 'permissions_prompt_shown_v1';

// Define the access token
const String accessToken = String.fromEnvironment('ACCESS_TOKEN');

// Use centralized notification plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    notificationPlugin;

// Global singleton for managing task timers from notifications
final TaskTimerService taskTimerService = TaskTimerService();

// Global navigator key so notification handler can bring the app to foreground
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Guard to avoid showing multiple switch dialogs simultaneously
bool _isGlobalSwitchDialogVisible = false;

Future<void> _showGlobalSwitchDialog(TaskSwitchRequest req) async {
  if (_isGlobalSwitchDialogVisible) return;
  final context = navigatorKey.currentContext;
  if (context == null) return;
  _isGlobalSwitchDialogVisible = true;
  try {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Higher priority task available'),
          content: Text('Start "${req.newTask.taskName}" now or snooze it?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(false);
              },
              child: const Text('Snooze'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Start Now'),
            ),
          ],
        );
      },
    );
    // Default to snooze if dialog dismissed unexpectedly
    req.respond(result == true);
  } catch (e) {
    developer.log('[main] Global switch dialog error: $e');
    try {
      req.respond(false);
    } catch (_) {}
  } finally {
    _isGlobalSwitchDialogVisible = false;
  }
}

/// Gate that decides whether to show the first-launch PIN setup prompt, the PIN lock screen,
/// or the main home shell depending on the user's choice and PIN enablement.
class PinGate extends StatefulWidget {
  final bool locationEnabled;
  const PinGate({Key? key, required this.locationEnabled}) : super(key: key);

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  bool _loading = true;
  bool _promptAnswered = false;
  bool _pinEnabled = false;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final answered = await PinService().isPromptAnswered();
      final enabled = await PinService().isPinEnabled();
      if (!mounted) return;
      setState(() {
        _promptAnswered = answered;
        _pinEnabled = enabled;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _reloadAndProceed() async {
    await _load();
    if (mounted && !_pinEnabled) {
      setState(() => _unlocked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_promptAnswered) {
      return PinSetupView(onCompleted: _reloadAndProceed);
    }
    if (_pinEnabled && !_unlocked) {
      return PinLockView(onUnlocked: () => setState(() => _unlocked = true));
    }
    return HomeShell(locationEnabled: widget.locationEnabled);
  }
}

Future<void> _onNotificationResponse(NotificationResponse response) async {
  // Unified notification response handler.
  try {
    final String? payload = response.payload;

    developer.log(
      '[main] Processing notification response: ${response.actionId} ${response.id}',
    );
    developer.log('[main] Payload: $payload');

    // 1) If action is DO_NOW and payload is a simple task id, start that task
    if (response.actionId == 'com.intelliboro.DO_NOW') {
      developer.log('[main] Processing DO_NOW action with payload: $payload');
      final int? simpleTaskId = payload == null ? null : int.tryParse(payload);
      if (simpleTaskId != null) {
        developer.log('[main] Parsed valid task ID: $simpleTaskId');
        final task = await TaskRepository().getTaskById(simpleTaskId);
        if (task != null) {
          developer.log(
            '[main] Found task: ${task.taskName} (id=$simpleTaskId)',
          );

          // Clear any existing notification for this response
          if (response.id != null) {
            await flutterLocalNotificationsPlugin.cancel(response.id!);
            developer.log(
              '[main] Cancelled originating notification id=${response.id}',
            );

            // Stop the alarm if it's ringing
            await Alarm.stop(response.id!);
            developer.log('[main] Stopped alarm id=${response.id}');
            // Release audio focus guard
            AudioFocusGuard.instance.onAlarmStop(response.id);
          }

          // Request switch to pause current task and show switch UI (matches geofence behavior)
          final started = await taskTimerService.requestSwitch(task);
          developer.log(
            '[main] Task switch result for id=$simpleTaskId: $started',
          );

          if (started) {
            try {
              // Start timer tracking for the task
              await taskTimerService.startTimerForTask(task);
              developer.log(
                '[main] Successfully started timer for task ${task.taskName} (id=$simpleTaskId)',
              );

              // Show confirmation notification with chronometer
              await flutterLocalNotificationsPlugin.show(
                99999,
                'Timer Started! ⏰',
                'Now tracking time for "${task.taskName}"',
                const NotificationDetails(
                  android: AndroidNotificationDetails(
                    'timer_feedback',
                    'Timer Feedback',
                    channelDescription: 'Confirms when task timers start',
                    importance: Importance.defaultImportance,
                    priority: Priority.defaultPriority,
                    showWhen: true,
                    autoCancel: false,
                    ongoing: true,
                    usesChronometer: true,
                  ),
                ),
              );
              developer.log('[main] Posted timer confirmation notification');
            } catch (e) {
              developer.log(
                '[main] Error starting timer or posting confirmation: $e',
              );
            }
          } else {
            developer.log(
              '[main] Did not start task ${task.taskName} due to priority/scheduling',
            );
          }

          // Navigate to ActiveTaskView (best-effort) so user sees the timer
          try {
            await _navigateToActiveView(maxRetries: 5);
            developer.log('[main] Navigated to ActiveTaskView after DO_NOW');
          } catch (e) {
            developer.log('[main] Navigation after DO_NOW failed: $e');
          }

          return;
        }
      }
    }

    if (response.payload == null || response.payload!.isEmpty) {
      developer.log('[main] Notification response has no payload.');
      return;
    }

    // Parse JSON payload created by the geofence background callback
    final Map<String, dynamic> data =
        jsonDecode(response.payload!) as Map<String, dynamic>;
    // If this payload contains a switchRequestId (from TaskTimerService), allow quick response
    if (data.containsKey('switchRequestId')) {
      final switchId = data['switchRequestId'] as String?;
      if (switchId != null) {
        // If action is DO_NOW we respond true, DO_LATER responds false
        if (response.actionId == 'com.intelliboro.DO_NOW') {
          taskTimerService.respondSwitchRequest(switchId, true);
          return;
        }
        if (response.actionId == 'com.intelliboro.DO_LATER') {
          taskTimerService.respondSwitchRequest(switchId, false);
          return;
        }
      }
    }
    final dynamic nid = data['notificationId'];
    final int? notificationIdFromPayload =
        nid is int ? nid : (nid is String ? int.tryParse(nid) : null);
    final List<dynamic> geofenceIds =
        (data['geofenceIds'] as List<dynamic>?) ?? [];
    final List<dynamic> payloadTaskIds =
        (data['taskIds'] as List<dynamic>?) ?? [];

    // Helper: resolve candidate tasks either from explicit taskIds or geofenceIds
    Future<List<TaskModel>> _resolveCandidates() async {
      final taskRepo = TaskRepository();
      final List<TaskModel> out = [];
      if (payloadTaskIds.isNotEmpty) {
        for (final tid in payloadTaskIds) {
          final int? parsed =
              tid is int ? tid : (tid is String ? int.tryParse(tid) : null);
          if (parsed != null) {
            final t = await taskRepo.getTaskById(parsed);
            if (t != null && !t.isCompleted) out.add(t);
          }
        }
        if (out.isNotEmpty) return out;
      }
      if (geofenceIds.isNotEmpty) {
        final tasks = await TaskRepository().getTasks();
        out.addAll(
          tasks.where(
            (t) =>
                t.geofenceId != null &&
                geofenceIds.contains(t.geofenceId) &&
                !t.isCompleted,
          ),
        );
      }
      return out;
    }

    if (response.actionId == 'com.intelliboro.DO_NOW') {
      developer.log(
        '[main] DO_NOW action received (payload notificationId=$notificationIdFromPayload)',
      );
      if (notificationIdFromPayload != null) {
        await flutterLocalNotificationsPlugin.cancel(notificationIdFromPayload);
      }
      final candidates = await _resolveCandidates();
      if (candidates.isNotEmpty) {
        final highest = candidates.reduce(
          (a, b) => a.getEffectivePriority() > b.getEffectivePriority() ? a : b,
        );
        // Use requestSwitch to match geofence behavior (pauses current task immediately)
        final started = await taskTimerService.requestSwitch(highest);
        developer.log(
          '[main] Task timer started: $started for ${highest.taskName}',
        );
        // Navigate to the ActiveTaskView so the user can always see the timer UI
        try {
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ActiveTaskView()),
            (r) => false,
          );
        } catch (e) {
          developer.log('[main] Navigation after DO_NOW failed: $e');
        }
        if (started) {
          // Also start the timer for the task
          await taskTimerService.startTimerForTask(highest);
          developer.log(
            '[main] Started timer tracking for ${highest.taskName}',
          );

          await flutterLocalNotificationsPlugin.show(
            99999,
            'Timer Started! ⏰',
            'Now tracking time for "${highest.taskName}"',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'timer_feedback',
                'Timer Feedback',
                channelDescription: 'Confirms when task timers start',
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
                showWhen: true,
                autoCancel: false,
                ongoing: true,
                usesChronometer: true,
              ),
            ),
          );
          try {
            // Navigate to the ActiveTaskView so the user can see the running timer.
            navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ActiveTaskView()),
              (r) => false,
            );
          } catch (e) {
            developer.log('[main] Navigation after DO_NOW failed: $e');
          }
        } else {
          // Lower-priority than current: add to pending (snoozed for 5 minutes)
          await taskTimerService.addToPending(
            highest,
            const Duration(minutes: 5),
          );

          // Pause geofence reminders for this task for 5 minutes
          if (highest.geofenceId != null) {
            try {
              await GeofencingService().removeGeofence(highest.geofenceId!);
            } catch (e) {
              developer.log('[main] Failed to remove geofence for snooze: $e');
            }
            // We rely on map view or app init to recreate geofences after snooze; log intent
            Timer(const Duration(minutes: 5), () {
              developer.log(
                '[main] Snooze expired for geofence ${highest.geofenceId}; ensure recreation via MapViewModel/GeofenceStorage.',
              );
            });
          }

          await flutterLocalNotificationsPlugin.show(
            99998,
            'Task Pending ⏸️',
            'Lower priority task "${highest.taskName}" will be pending for 5 minutes.',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'timer_feedback',
                'Timer Feedback',
                channelDescription: 'Confirms when task timers start',
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
                showWhen: true,
                autoCancel: true,
                timeoutAfter: 4000,
              ),
            ),
          );
        }
      } else {
        // Fallback: try to extract a task name from notification body/title
        try {
          String? body = data['body'] as String?;
          String? title = data['title'] as String?;
          final RegExp r = RegExp(r'task\s+([^\n]+)', caseSensitive: false);
          RegExpMatch? m;
          if (body != null) m = r.firstMatch(body);
          if (m == null && title != null) m = r.firstMatch(title);
          if (m != null) {
            final String name = m.group(1)!.trim();
            final allTasks = await TaskRepository().getTasks();
            TaskModel? matched;
            for (final t in allTasks) {
              if (!t.isCompleted &&
                  t.taskName.toLowerCase() == name.toLowerCase()) {
                matched = t;
                break;
              }
            }
            if (matched != null) {
              developer.log(
                '[main] DO_NOW fallback matched task by name: ${matched.taskName}',
              );
              final started = await taskTimerService.requestSwitch(matched);
              if (started) {
                await flutterLocalNotificationsPlugin.show(
                  99999,
                  'Timer Started! \u23f0',
                  'Now tracking time for "${matched.taskName}"',
                  const NotificationDetails(
                    android: AndroidNotificationDetails(
                      'timer_feedback',
                      'Timer Feedback',
                      channelDescription: 'Confirms when task timers start',
                      importance: Importance.defaultImportance,
                      priority: Priority.defaultPriority,
                      showWhen: true,
                      autoCancel: false,
                      ongoing: true,
                      usesChronometer: true,
                    ),
                  ),
                );
                try {
                  navigatorKey.currentState?.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const ActiveTaskView()),
                    (r) => false,
                  );
                } catch (e) {
                  developer.log(
                    '[main] Navigation after DO_NOW fallback failed: $e',
                  );
                }
              }
            }
          }
        } catch (e, st) {
          developer.log(
            '[main] Error in DO_NOW fallback name-matching: $e',
            error: e,
            stackTrace: st,
          );
        }
      }
      return;
    }

    if (response.actionId == 'com.intelliboro.DO_LATER') {
      developer.log(
        '[main] DO_LATER action received (payload notificationId=$notificationIdFromPayload)',
      );
      if (notificationIdFromPayload != null) {
        await flutterLocalNotificationsPlugin.cancel(notificationIdFromPayload);
      }
      final candidates = await _resolveCandidates();
      for (final t in candidates) {
        await taskTimerService.rescheduleTaskLater(t);
        developer.log('[main] Rescheduled task: ${t.taskName}');
      }
      return;
    }

    // Handle quick snooze actions from the 'Pending' notification
    if (response.actionId == 'com.intelliboro.SNOOZE_5' ||
        response.actionId == 'com.intelliboro.SNOOZE_LATER') {
      developer.log('[main] Snooze action received: ${response.actionId}');
      if (notificationIdFromPayload != null) {
        await flutterLocalNotificationsPlugin.cancel(notificationIdFromPayload);
      }
      final candidates = await _resolveCandidates();
      if (candidates.isEmpty) return;

      if (response.actionId == 'com.intelliboro.SNOOZE_5') {
        for (final t in candidates) {
          await taskTimerService.addToPending(t, const Duration(minutes: 5));
          if (t.geofenceId != null) {
            try {
              await GeofencingService().removeGeofence(t.geofenceId!);
            } catch (e) {
              developer.log('[main] Failed to remove geofence for snooze: $e');
            }
          }
        }
        await flutterLocalNotificationsPlugin.show(
          99997,
          'Snoozed',
          'Tasks snoozed for 5 minutes.',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'timer_feedback',
              'Timer Feedback',
              channelDescription: 'Confirms snooze actions',
            ),
          ),
        );
        return;
      }

      // SNOOZE_LATER: bring app to foreground so user can pick a snooze duration
      try {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const HomeShell(locationEnabled: true),
          ),
          (r) => false,
        );
      } catch (e) {
        developer.log('[main] Navigation after SNOOZE_LATER failed: $e');
      }
      return;
    }

    // Default tap: cancel the notification
    if (response.id != null) {
      await flutterLocalNotificationsPlugin.cancel(response.id!);
    }

    // If the user tapped the notification body (no explicit actionId),
    // treat it like DO_NOW when we have a payload with taskIds or geofenceIds.
    if ((response.actionId == null || response.actionId!.isEmpty) &&
        response.payload != null &&
        response.payload!.isNotEmpty) {
      try {
        // Resolve candidates and start the highest-priority one, then navigate
        final List<TaskModel> fallbackCandidates = await _resolveCandidates();
        if (fallbackCandidates.isNotEmpty) {
          final highestFallback = fallbackCandidates.reduce(
            (a, b) =>
                a.getEffectivePriority() > b.getEffectivePriority() ? a : b,
          );
          await taskTimerService.requestSwitch(highestFallback);
          try {
            await _navigateToActiveView(maxRetries: 5);
          } catch (e) {
            developer.log(
              '[main] Navigation after default notification tap failed: $e',
            );
          }
        }
      } catch (e) {
        developer.log(
          '[main] Could not parse fallback payload for default tap: $e',
        );
      }
    }
  } catch (e, st) {
    developer.log(
      '[main] Error handling notification response: $e',
      error: e,
      stackTrace: st,
    );
  }

  // Final guarantee: if a task is active after handling the notification,
  // navigate to the ActiveTaskView so the user always sees the running timer.
  if (taskTimerService.hasActiveTask) {
    developer.log(
      '[main] Active task detected after notification handling. Navigating to ActiveTaskView.',
    );
    try {
      await _navigateToActiveView();
    } catch (e) {
      developer.log('[main] Final navigation to ActiveTaskView failed: $e');
    }
  }
}

/// Helper that retries navigation until the `navigatorKey` is available.
Future<void> _navigateToActiveView({int maxRetries = 8}) async {
  int attempts = 0;
  while (attempts < maxRetries) {
    final navState = navigatorKey.currentState;
    if (navState != null) {
      try {
        navState.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ActiveTaskView()),
          (r) => false,
        );
        developer.log(
          '[main] Navigation to ActiveTaskView succeeded on attempt ${attempts + 1}',
        );
        return;
      } catch (e) {
        developer.log('[main] Navigation attempt failed: $e');
        return;
      }
    }
    attempts += 1;
    developer.log(
      '[main] navigatorKey not ready, retrying navigation in 150ms (attempt $attempts)',
    );
    await Future.delayed(const Duration(milliseconds: 150));
  }
  developer.log(
    '[main] Failed to navigate to ActiveTaskView after $maxRetries attempts',
  );
}

Future<void> _initializeTimezone() async {
  try {
    tz.initializeTimeZones();
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));
    developer.log("[main] Timezone initialized for: $timeZoneName");
  } catch (e) {
    developer.log("[main] Error initializing timezone: $e");
  }
}

/// Initialize TTS service in background (non-blocking)
void _initializeTtsService() {
  Future.microtask(() async {
    try {
      developer.log('[main] Initializing TTS service...');
      final ttsService = TextToSpeechService();
      await ttsService.init();
      await ttsService.setEnabled(true);
      developer.log('[main] TTS service initialized successfully');
    } catch (e) {
      developer.log('[main] Error initializing TTS service: $e');
      // Don't rethrow - let the app continue without TTS
    }
  });
}

/// Handle when an alarm rings - show notification with action buttons
Future<void> _handleAlarmRing(AlarmSettings alarmSettings) async {
  try {
    developer.log('[main] Handling alarm ring for id=${alarmSettings.id}');

    // Extract task ID from alarm ID (reverse of _alarmIdForTaskId)
    final taskId = alarmSettings.id - 100000;

    // Get task details
    final task = await TaskRepository().getTaskById(taskId);
    if (task == null) {
      developer.log(
        '[main] Task not found for alarm id=${alarmSettings.id}, taskId=$taskId',
      );
      return;
    }

    // Show notification with action buttons (no sound - alarm package handles audio)
    await flutterLocalNotificationsPlugin.show(
      alarmSettings.id,
      'Task Reminder ⏰',
      '${task.taskName} - Time to start!',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'task_alarms',
          'Task Alarms',
          channelDescription: 'Time-based task alarms',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          playSound:
              false, // Disable notification sound - alarm package plays audio
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              'com.intelliboro.DO_NOW',
              'Do Now 🏃‍♂️',
              showsUserInterface: true,
              cancelNotification: true,
            ),
            const AndroidNotificationAction(
              'com.intelliboro.DO_LATER',
              'Do Later ⏰',
              showsUserInterface: false,
              cancelNotification: false,
            ),
          ],
        ),
      ),
      payload: taskId.toString(),
    );

    developer.log(
      '[main] Showed alarm notification for task: ${task.taskName}',
    );
  } catch (e) {
    developer.log('[main] Error handling alarm ring: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone and notifications BEFORE bringing up the UI so
  // scheduling calls (which may run during early DB/insert flows) always
  // have tz.local and the notification plugin ready. This adds a small
  // startup delay but avoids races where scheduleForTask is invoked early.
  try {
    // Initialize timezone data and set local zone
    tz.initializeTimeZones();
    final String timezoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneName));
    developer.log('[main] Timezone initialized for: $timezoneName');

    // Initialize Flutter alarm service
    final flutterAlarmService = FlutterAlarmService();
    await flutterAlarmService.initialize();
    developer.log('[main] Flutter alarm service initialized');

    // Initialize notification plugin (centralized instance)
    await initializeNotifications();
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        developer.log(
          '[main] Notification tapped: payload=${response.payload}, actionId=${response.actionId}, id=${response.id}',
        );
        await _onNotificationResponse(response);
      },
    );

    // Set up alarm ring listener
    Alarm.ringing.listen((AlarmSet alarmSet) {
      for (final alarm in alarmSet.alarms) {
        developer.log('[main] Alarm ringing: id=${alarm.id}');
        AudioFocusGuard.instance.onAlarmStart(alarm.id);
        _handleAlarmRing(alarm);
      }
    });
    developer.log('[main] Alarm ring listener set up');
  } catch (e, s) {
    developer.log(
      '[main] Error initializing timezone/notifications early: $e\n$s',
    );
    // Fall back to deferred initialization in microtask (keeps UX resilient)
    Future.microtask(() async {
      try {
        await _initializeTimezone();
        await initializeNotifications();
      } catch (e2, s2) {
        developer.log('[main] Deferred init also failed: $e2\n$s2');
      }
    });
  }

  // Bring up the UI immediately after core init steps
  MapboxOptions.setAccessToken(accessToken);
  // Diagnostic: log whether an access token was provided at build/run time.
  developer.log(
    '[main] Mapbox access token present: ${accessToken.isNotEmpty}',
  );
  if (accessToken.isEmpty) {
    developer.log(
      '[main] WARNING: Mapbox ACCESS_TOKEN is empty. If maps previously worked, ensure you built the app with --dart-define=ACCESS_TOKEN=<your_token>',
    );
  }
  // Early request: ensure the user is offered the exact-alarms setting as soon
  // as the app starts. This helps devices that block exact alarms by default.
  if (Platform.isAndroid) {
    try {
      const platform = MethodChannel('exact_alarms');
      final bool canSchedule = await platform.invokeMethod(
        'canScheduleExactAlarms',
      );
      developer.log('[main] Early canScheduleExactAlarms: $canSchedule');
      if (!canSchedule) {
        developer.log(
          '[main] Early requestExactAlarmPermission: launching system intent',
        );
        // Fire-and-forget - this will open the system page where the user can
        // enable "Allow exact alarms" for the app.
        await platform.invokeMethod('requestExactAlarmPermission');
      }
    } catch (e) {
      // Silenced: alarm package v5.1.5 handles exact alarms internally
      // developer.log('[main] Early exact alarms check/request failed: $e');
    }
  }

  runApp(const MyApp());

  // Initialize TTS service in background (non-blocking)
  _initializeTtsService();

  // Defer other initializations to microtasks so first frame can render.
  Future.microtask(() async {
    // Initialize offline operation queue
    try {
      await OfflineOperationQueue().init();
      developer.log('[main] OfflineOperationQueue initialized');
    } catch (e, st) {
      developer.log(
        '[main] Error initializing OfflineOperationQueue: $e',
        error: e,
        stackTrace: st,
      );
    }

    // Initialize geofencing service early so the port listener is registered
    try {
      await GeofencingService().init();
      developer.log('[main] GeofencingService initialized early in main');
    } catch (e, st) {
      developer.log(
        '[main] Error initializing GeofencingService early: $e',
        error: e,
        stackTrace: st,
      );
    }

    // Load any pending tasks persisted by background callbacks while app wasn't active
    try {
      await taskTimerService.loadPersistedPending();
    } catch (e) {
      developer.log('[main] Failed to load persisted pending tasks: $e');
    }

    // If the app was launched via a notification (cold start), handle it now
    // so DO_NOW navigates to the ActiveTaskView on first launch.
    try {
      final details =
          await flutterLocalNotificationsPlugin
              .getNotificationAppLaunchDetails();
      if (details != null &&
          details.didNotificationLaunchApp &&
          details.notificationResponse != null) {
        developer.log(
          '[main] App launched from notification, handling response...',
        );
        await _onNotificationResponse(details.notificationResponse!);
      }
    } catch (e, st) {
      developer.log(
        '[main] Error checking notification launch details: $e',
        error: e,
        stackTrace: st,
      );
    }

    // Also ask native side if the app was launched with an action from our
    // alarm notification (e.g., do_now). MainActivity exposes 'getLaunchAction'.
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('exact_alarms');
        final Map? launch = await platform.invokeMethod('getLaunchAction');
        developer.log('[main] Native launch action (raw): $launch');
        if (launch != null) {
          // Prefer explicit taskId when provided by native code
          final dynamic tval = launch['taskId'];
          final int? launchTaskId =
              tval is int ? tval : (tval is String ? int.tryParse(tval) : null);
          final String? action = launch['action'] as String?;

          if (launchTaskId != null) {
            try {
              final task = await TaskRepository().getTaskById(launchTaskId);
              if (task != null) {
                if (action == 'do_later') {
                  // For alarm-based do_later, reschedule the task to ring again after snooze duration
                  await taskTimerService.rescheduleTaskLater(task);
                  developer.log(
                    '[main] Rescheduled task (native do_later) ${task.taskName} for ${taskTimerService.defaultSnoozeDuration.inMinutes} minutes later',
                  );
                } else {
                  // Default (do_now or missing action): start the task
                  // First cancel any existing alarms for this task to prevent re-ringing
                  try {
                    final alarmService = FlutterAlarmService();
                    await alarmService.cancelForTaskId(launchTaskId);
                    developer.log(
                      '[main] Cancelled alarm for task id=$launchTaskId before starting',
                    );
                  } catch (e) {
                    developer.log(
                      '[main] Failed to cancel alarm for task id=$launchTaskId: $e',
                    );
                  }

                  final started = await taskTimerService.requestSwitch(task);
                  developer.log(
                    '[main] Native launch started task id=$launchTaskId started=$started',
                  );
                  if (started) {
                    try {
                      // Also start the timer for the task once it's activated
                      await taskTimerService.startTimerForTask(task);
                      developer.log(
                        '[main] Started timer for task id=$launchTaskId',
                      );

                      // Show feedback notification
                      await flutterLocalNotificationsPlugin.show(
                        99999,
                        'Timer Started! ⏰',
                        'Now tracking time for "${task.taskName}"',
                        const NotificationDetails(
                          android: AndroidNotificationDetails(
                            'timer_feedback',
                            'Timer Feedback',
                            channelDescription:
                                'Confirms when task timers start',
                            importance: Importance.defaultImportance,
                            priority: Priority.defaultPriority,
                            showWhen: true,
                            autoCancel: false,
                            ongoing: true,
                            usesChronometer: true,
                          ),
                        ),
                      );

                      // Navigate to the task view to show the timer
                      navigatorKey.currentState?.pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const ActiveTaskView(),
                        ),
                        (r) => false,
                      );
                    } catch (e) {
                      developer.log(
                        '[main] Navigation or timer start failed: $e',
                      );
                    }
                  }
                }
              } else {
                developer.log(
                  '[main] Native launch included taskId=$launchTaskId but task not found',
                );
              }
            } catch (e) {
              developer.log(
                '[main] Error handling native launch taskId=$launchTaskId: $e',
              );
            }
          } else if (action == 'do_later') {
            // Fallback: legacy behavior using notificationId -> taskId arithmetic
            try {
              final dynamic nid = launch['notificationId'];
              final int? notificationIdFromLaunch =
                  nid is int ? nid : (nid is String ? int.tryParse(nid) : null);
              if (notificationIdFromLaunch != null) {
                try {
                  await flutterLocalNotificationsPlugin.cancel(
                    notificationIdFromLaunch,
                  );
                } catch (e) {}

                if (notificationIdFromLaunch >= 100000) {
                  final int taskId = notificationIdFromLaunch - 100000;
                  final task = await TaskRepository().getTaskById(taskId);
                  if (task != null) {
                    await taskTimerService.rescheduleTaskLater(task);
                    developer.log(
                      '[main] Rescheduled task (legacy do_later) ${task.taskName}',
                    );
                  }
                }
              }
            } catch (e) {
              developer.log(
                '[main] Failed to handle native do_later fallback: $e',
              );
            }
          } else if (action == 'do_now') {
            // If we have a do_now without taskId, navigate to ActiveTaskView as best-effort
            developer.log(
              '[main] Native launch do_now without taskId: $launch',
            );
            try {
              navigatorKey.currentState?.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const ActiveTaskView()),
                (r) => false,
              );
            } catch (e) {
              developer.log(
                '[main] Failed to handle native do_now fallback: $e',
              );
            }
          }
        }
      }
    } catch (e) {
      // Silenced: alarm package handles notification actions internally
      // developer.log('[main] getLaunchAction call failed: $e');
    }

    // Also listen for immediate native launch-action forwards so we don't
    // miss taps on the alarm notification when the app is backgrounded.
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('exact_alarms');
        platform.setMethodCallHandler((call) async {
          try {
            if (call.method == 'onLaunchAction') {
              final Map? launch = call.arguments as Map?;
              developer.log('[main] onLaunchAction received: $launch');
              if (launch == null) return;
              final dynamic tval = launch['taskId'];
              final int? launchTaskId =
                  tval is int
                      ? tval
                      : (tval is String ? int.tryParse(tval) : null);
              final String? action = launch['action'] as String?;
              if (launchTaskId != null) {
                final task = await TaskRepository().getTaskById(launchTaskId);
                if (task != null) {
                  if (action == 'do_later') {
                    // For alarm-based do_later, reschedule the task to ring again after snooze duration
                    await taskTimerService.rescheduleTaskLater(task);
                    developer.log(
                      '[main] Rescheduled task (onLaunchAction do_later) ${task.taskName} for ${taskTimerService.defaultSnoozeDuration.inMinutes} minutes later',
                    );
                  } else {
                    // Cancel any existing alarms for this task first
                    try {
                      final alarmService = FlutterAlarmService();
                      await alarmService.cancelForTaskId(launchTaskId);
                      developer.log(
                        '[main] Cancelled alarm for task id=$launchTaskId (onLaunchAction)',
                      );
                    } catch (e) {
                      developer.log(
                        '[main] Failed to cancel alarm for task id=$launchTaskId (onLaunchAction): $e',
                      );
                    }

                    final started = await taskTimerService.requestSwitch(task);
                    developer.log(
                      '[main] onLaunchAction started task id=$launchTaskId started=$started',
                    );
                    if (started) {
                      try {
                        await taskTimerService.startTimerForTask(task);
                        developer.log(
                          '[main] Started timer for task id=$launchTaskId',
                        );
                        await flutterLocalNotificationsPlugin.show(
                          99999,
                          'Timer Started! \u23f0',
                          'Now tracking time for "${task.taskName}"',
                          const NotificationDetails(
                            android: AndroidNotificationDetails(
                              'timer_feedback',
                              'Timer Feedback',
                              channelDescription:
                                  'Confirms when task timers start',
                              importance: Importance.defaultImportance,
                              priority: Priority.defaultPriority,
                              showWhen: true,
                              autoCancel: false,
                              ongoing: true,
                              usesChronometer: true,
                            ),
                          ),
                        );

                        // Navigate to the task view to show the timer
                        try {
                          navigatorKey.currentState?.pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const ActiveTaskView(),
                            ),
                            (r) => false,
                          );
                        } catch (e) {
                          developer.log(
                            '[main] Navigation or timer start failed: $e',
                          );
                        }
                      } catch (e) {
                        developer.log(
                          '[main] Failed to start timer for onLaunchAction: $e',
                        );
                      }
                    }
                  }
                }
              } else if (action == 'do_later') {
                try {
                  final dynamic nid = launch['notificationId'];
                  final int? notificationIdFromLaunch =
                      nid is int
                          ? nid
                          : (nid is String ? int.tryParse(nid) : null);
                  if (notificationIdFromLaunch != null) {
                    try {
                      await flutterLocalNotificationsPlugin.cancel(
                        notificationIdFromLaunch,
                      );
                    } catch (e) {}

                    if (notificationIdFromLaunch >= 100000) {
                      final int taskId = notificationIdFromLaunch - 100000;
                      final task = await TaskRepository().getTaskById(taskId);
                      if (task != null) {
                        await taskTimerService.rescheduleTaskLater(task);
                        developer.log(
                          '[main] Rescheduled task (legacy do_later) ${task.taskName}',
                        );
                      }
                    }
                  }
                } catch (e) {
                  developer.log(
                    '[main] Failed to handle onLaunchAction do_later fallback: $e',
                  );
                }
              } else if (action == 'do_now') {
                // If we only have an action, bring up ActiveTaskView as best-effort
                developer.log(
                  '[main] onLaunchAction do_now without taskId: $launch',
                );
                try {
                  navigatorKey.currentState?.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const ActiveTaskView()),
                    (r) => false,
                  );
                } catch (e) {
                  developer.log(
                    '[main] Failed to handle onLaunchAction do_now fallback: $e',
                  );
                }
              } else if (action == 'alarm_triggered') {
                // Show a proper Flutter notification with showsUserInterface: true
                developer.log('[main] onLaunchAction alarm_triggered: $launch');
                try {
                  final notificationId =
                      launch['notificationId'] as int? ?? 999999;
                  final title = launch['title'] as String? ?? 'Task Reminder';
                  final body =
                      launch['body'] as String? ?? 'Time to work on your task!';

                  await flutterLocalNotificationsPlugin.show(
                    notificationId,
                    title,
                    body,
                    NotificationDetails(
                      android: AndroidNotificationDetails(
                        'task_alarms',
                        'Task Alarms',
                        channelDescription: 'Time-based task alarms',
                        importance: Importance.max,
                        priority: Priority.high,
                        category: AndroidNotificationCategory.alarm,
                        fullScreenIntent: true,
                        playSound:
                            false, // Disable notification sound - alarm package plays audio
                        actions: <AndroidNotificationAction>[
                          const AndroidNotificationAction(
                            'com.intelliboro.DO_NOW',
                            'Do Now 🏃‍♂️',
                            showsUserInterface: true,
                            cancelNotification: true,
                          ),
                          const AndroidNotificationAction(
                            'com.intelliboro.DO_LATER',
                            'Do Later ⏰',
                            showsUserInterface: false,
                            cancelNotification: false,
                          ),
                        ],
                      ),
                    ),
                    payload: launchTaskId?.toString(),
                  );

                  developer.log(
                    '[main] Showed alarm notification with Flutter plugin: id=$notificationId',
                  );
                } catch (e) {
                  developer.log('[main] Failed to show alarm notification: $e');
                }
              }
            }
          } catch (ee) {
            developer.log('[main] onLaunchAction handler error: $ee');
          }
        });
      }
    } catch (e) {
      // Silenced: alarm package handles notification actions internally
      // developer.log('[main] onLaunchAction registration failed: $e');
    }

    // Global listener for switch requests so prompts appear regardless of current screen
    try {
      taskTimerService.switchRequests.listen((req) {
        // If TaskListView also listens, this guard prevents duplicate dialogs here
        if (_isGlobalSwitchDialogVisible) return;
        // Defer to next frame to ensure navigator is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showGlobalSwitchDialog(req);
        });
      });
      developer.log('[main] Registered global listener for switchRequests');
    } catch (e) {
      developer.log('[main] Failed to register global switch listener: $e');
    }
  });
}

// Optional: Callback for when a notification is tapped (if you need to handle it)
// void onDidReceiveNotificationResponse(NotificationResponse notificationResponse) async {
//   final String? payload = notificationResponse.payload;
//   if (notificationResponse.payload != null) {
//     developer.log('[main] Notification payload: $payload');
//   }
//   // Navigate to a specific screen, etc.
// }

// Optional: For older iOS versions to handle notifications when app is in foreground
// Future onDidReceiveLocalNotification(int id, String? title, String? body, String? payload) async {
//   // display a dialog with the notification details, tap ok to go to another page
//   developer.log('[main] onDidReceiveLocalNotification: $title - $payload');
// }

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'IntelliBoro',
      theme: appTheme,
      home: const AppInitializer(), // Use AppInitializer
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({Key? key}) : super(key: key);

  @override
  _AppInitializerState createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _permissionsGranted = false;
  bool _isLoadingPermissions = true;
  String? _permissionError; // To store any error message
  final LocationService _locationService = LocationService();
  bool _locationAllowed = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (!mounted) return;
    setState(() {
      _isLoadingPermissions = true;
      _permissionError = null; // Clear previous error
    });

    try {
      // First-run flow: if the app has not shown the permissions prompt yet,
      // perform the guided permission checks and attempt to request exact alarm
      // permission when appropriate (Android).
      final prefs = await SharedPreferences.getInstance();
      final bool firstRun = !(prefs.getBool(_kPermissionsPromptShown) ?? false);
      if (firstRun) {
        developer.log('[main] First-run detected: showing permissions flow');
      }

      debugPrint("[_AppInitializerState] Requesting location permission...");
      bool locationGranted = await _locationService.requestLocationPermission();
      debugPrint(
        "[_AppInitializerState] Location permission granted: $locationGranted",
      );

      debugPrint(
        "[_AppInitializerState] Requesting notification permission...",
      );
      PermissionStatus notificationStatus =
          await Permission.notification.request();
      debugPrint(
        "[_AppInitializerState] Notification permission status: $notificationStatus",
      );

      // Request exact alarm permission for Android 12+ (API 31+)
      // This is required for alarms to ring at exact times
      if (Platform.isAndroid) {
        try {
          final exactAlarmStatus = await Permission.scheduleExactAlarm.status;
          developer.log(
            '[main] Exact alarm permission status: $exactAlarmStatus',
          );

          if (!exactAlarmStatus.isGranted) {
            developer.log('[main] Requesting exact alarm permission...');
            final result = await Permission.scheduleExactAlarm.request();
            developer.log(
              '[main] Exact alarm permission request result: $result',
            );

            // If still denied, open settings to allow user to enable it manually
            if (!result.isGranted) {
              developer.log(
                '[main] Exact alarm permission denied, opening app settings',
              );
              await openAppSettings();
            }
          }
        } catch (e) {
          developer.log('[main] Error requesting exact alarm permission: $e');
        }
      }

      // Legacy exact alarm check removed - now using permission_handler above
      // if (firstRun && Platform.isAndroid && notificationStatus.isDenied) {
      //   try {
      //     const platform = MethodChannel('exact_alarms');
      //     ...
      //   } catch (e) {
      //     developer.log(...);
      //   }
      // }

      if (!mounted) return;
      setState(() {
        _locationAllowed = locationGranted;
        // Proceed if notifications are allowed, even if location is denied
        _permissionsGranted =
            (notificationStatus.isGranted || notificationStatus.isLimited);
      });

      if (!_permissionsGranted) {
        debugPrint(
          "[_AppInitializerState] Permissions not fully granted. Showing dialog.",
        );
        _showPermissionDeniedDialog();
      } else {
        debugPrint("[_AppInitializerState] All necessary permissions granted.");
      }

      // Mark that we've shown the first-run permissions flow so we don't repeat
      // this aggressive flow on subsequent app starts.
      if (firstRun) {
        await prefs.setBool(_kPermissionsPromptShown, true);
      }
    } catch (e, stackTrace) {
      debugPrint(
        "[_AppInitializerState] Error during permission request: $e\n$stackTrace",
      );
      if (!mounted) return;
      setState(() {
        _permissionError =
            "An error occurred while requesting permissions: ${e.toString()}";
        _permissionsGranted = false; // Ensure we don't proceed if error occurs
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingPermissions = false;
      });
      debugPrint("[_AppInitializerState] _isLoadingPermissions set to false.");
    }
  }

  void _showPermissionDeniedDialog() {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, // User must interact with the dialog
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Permissions Required'),
            content: const Text(
              'This app requires location and notification permissions to function correctly. Please grant these permissions in app settings.',
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Open Settings'),
                onPressed: () {
                  openAppSettings(); // From permission_handler
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('Retry'),
                onPressed: () {
                  Navigator.of(context).pop();
                  _requestPermissions();
                },
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPermissions) {
      debugPrint("[_AppInitializerState] Building: Loading permissions...");
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_permissionError != null) {
      debugPrint(
        "[_AppInitializerState] Building: Displaying permission error: $_permissionError",
      );
      return Scaffold(
        appBar: AppBar(title: const Text("Permission Error")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _permissionError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _requestPermissions,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_permissionsGranted) {
      debugPrint(
        "[_AppInitializerState] Building: Permissions granted, showing TaskListView.",
      );
      return PinGate(locationEnabled: _locationAllowed);
    } else {
      debugPrint(
        "[_AppInitializerState] Building: Permissions not granted, showing fallback screen.",
      );
      // Fallback screen if permissions are still not granted (and no error)
      return Scaffold(
        appBar: AppBar(title: const Text("Permissions Needed")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Location and Notification permissions are essential for this app. Please enable them in your app settings to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    openAppSettings();
                  },
                  child: const Text('Open App Settings'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _requestPermissions,
                  child: const Text('Retry Permission Check'),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}

/// Simple bottom navigation shell using Material 3 NavigationBar.
class HomeShell extends StatefulWidget {
  final bool locationEnabled;
  const HomeShell({Key? key, required this.locationEnabled}) : super(key: key);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  bool _bannerDismissed = false;

  static const List<Widget> _pages = <Widget>[
    TaskListView(),
    TaskStatisticsView(),
    NotificationHistoryView(),
    SettingsView(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showLocationBanner = !widget.locationEnabled && !_bannerDismissed;
    final scaffold = Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        height: 72,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.list_rounded),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_rounded),
            label: 'Statistics',
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_rounded),
            label: 'Notifications',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentMaterialBanner();
      if (showLocationBanner) {
        messenger.showMaterialBanner(
          MaterialBanner(
            content: const Text(
              'Location permission is off. Geofenced reminders and map features are disabled. Time-based reminders still work.',
            ),
            leading: const Icon(Icons.location_off),
            actions: [
              TextButton(
                onPressed: () async {
                  await openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
              TextButton(
                onPressed: () async {
                  // Attempt a re-check/ask
                  try {
                    final granted =
                        await LocationService().requestLocationPermission();
                    if (!mounted) return;
                    if (granted) {
                      setState(() {
                        _bannerDismissed = false;
                      });
                      messenger.hideCurrentMaterialBanner();
                    }
                  } catch (_) {}
                },
                child: const Text('Refresh'),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _bannerDismissed = true);
                  ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                },
                child: const Text('Dismiss'),
              ),
            ],
          ),
        );
      }
    });
    return scaffold;
  }
}
