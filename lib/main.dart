import 'package:flutter/material.dart';
import 'package:intelliboro/theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'dart:async';
import 'package:intelliboro/views/task_list_view.dart';
import 'package:intelliboro/services/location_service.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intelliboro/services/text_to_speech_service.dart';
import 'package:intelliboro/views/active_task_view.dart';
import 'package:intelliboro/model/task_model.dart';

// Define the access token
const String accessToken = String.fromEnvironment('ACCESS_TOKEN');

// Create an instance of the plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Global singleton for managing task timers from notifications
final TaskTimerService taskTimerService = TaskTimerService();

// Global navigator key so notification handler can bring the app to foreground
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _onNotificationResponse(NotificationResponse response) async {
  // Unified notification response handler.
  try {
    final String? payload = response.payload;
    final int? responseId = response.id;

    // 1) If action is DO_NOW and payload is a simple task id, start that task
    if (response.actionId == 'com.intelliboro.DO_NOW') {
      final int? simpleTaskId = payload == null ? null : int.tryParse(payload);
      if (simpleTaskId != null) {
        final task = await TaskRepository().getTaskById(simpleTaskId);
        if (task != null) {
          await taskTimerService.startTask(task);
          developer.log(
            '[main] Started timer for task ${task.taskName} (id=$simpleTaskId)',
          );
          if (responseId != null) {
            await flutterLocalNotificationsPlugin.cancel(responseId);
          }
          // Bring app to foreground
          try {
            navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ActiveTaskView()),
              (r) => false,
            );
          } catch (e) {
            developer.log('[main] Navigation after DO_NOW failed: $e');
          }
          return;
        }
      }
    }

    if (payload == null || payload.isEmpty) {
      developer.log('[main] Notification response has no payload.');
      return;
    }

    // Parse JSON payload created by the geofence background callback
    final Map<String, dynamic> data =
        jsonDecode(payload) as Map<String, dynamic>;
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
        final started = await taskTimerService.startTask(highest);
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
                autoCancel: true,
                timeoutAfter: 3000,
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
          await flutterLocalNotificationsPlugin.show(
            99998,
            'Task Rescheduled 📅',
            'Higher priority task active. "${highest.taskName}" moved to later.',
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
              final started = await taskTimerService.startTask(matched);
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
                      autoCancel: true,
                      timeoutAfter: 3000,
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

    // Default tap: cancel the notification
    if (responseId != null) {
      await flutterLocalNotificationsPlugin.cancel(responseId);
    }

    // If the user tapped the notification body (no explicit actionId),
    // treat it like DO_NOW when we have a payload with taskIds or geofenceIds.
    if ((response.actionId == null || response.actionId!.isEmpty) &&
        payload.isNotEmpty) {
      try {
        // Resolve candidates and start the highest-priority one, then navigate
        final List<TaskModel> fallbackCandidates = await _resolveCandidates();
        if (fallbackCandidates.isNotEmpty) {
          final highestFallback = fallbackCandidates.reduce(
            (a, b) =>
                a.getEffectivePriority() > b.getEffectivePriority() ? a : b,
          );
          await taskTimerService.startTask(highestFallback);
          try {
            navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const ActiveTaskView()),
              (r) => false,
            );
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
  try {
    if (taskTimerService.hasActiveTask) {
      developer.log(
        '[main] Active task detected after notification handling. Navigating to ActiveTaskView.',
      );
      await _navigateToActiveView();
    }
  } catch (e) {
    developer.log('[main] Final navigation to ActiveTaskView failed: $e');
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize TTS service in background (non-blocking)
  _initializeTtsService();

  await _initializeTimezone();

  // Initialize flutter_local_notifications
  try {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          defaultPresentBanner: true,
          defaultPresentSound: true,
        );
    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    bool? initialized = await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        developer.log(
          '[main] Notification tapped: payload=${response.payload}, actionId=${response.actionId}, id=${response.id}',
        );
        await _onNotificationResponse(response);
      },
    );

    // Create the notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'geofence_alerts',
      'Geofence Alerts',
      description: 'Important alerts for location-based events',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // Request notification permissions
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidImplementation != null) {
      final bool? permissionGranted =
          await androidImplementation.requestNotificationsPermission();
      developer.log(
        "[main] Notification permission granted: $permissionGranted",
      );

      final bool? exactAlarmsPermission =
          await androidImplementation.requestExactAlarmsPermission();
      developer.log(
        "[main] Exact alarms permission granted: $exactAlarmsPermission",
      );
    }

    developer.log(
      "[main] FlutterLocalNotificationsPlugin initialized: $initialized",
    );
  } catch (e, s) {
    developer.log(
      "[main] Error initializing FlutterLocalNotificationsPlugin: $e\n$s",
    );
  }

  MapboxOptions.setAccessToken(accessToken);
  runApp(const MyApp());

  // If the app was launched via a notification (cold start), handle it now
  // so DO_NOW navigates to the ActiveTaskView on first launch.
  Future.microtask(() async {
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

      if (!mounted) return;
      setState(() {
        _permissionsGranted =
            locationGranted &&
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
      return const TaskListView();
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