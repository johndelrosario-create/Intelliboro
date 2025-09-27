import 'package:flutter/material.dart';
import 'package:intelliboro/theme.dart';
import 'package:intelliboro/views/create_task_view.dart'; // Used by old HomePage
import 'package:permission_handler/permission_handler.dart'; // Used by old HomePage
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'dart:async'; // Used by old HomePage
import 'dart:ui'; // Used by old HomePage
import 'dart:isolate'; // Used by old HomePage
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

// Define the access token
const String accessToken = String.fromEnvironment('ACCESS_TOKEN');

// Create an instance of the plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void _onNotificationResponse(NotificationResponse response) async {
  developer.log(
    '[main] Handling notification response. ID: ${response.id}, Action: ${response.actionId}, Payload: ${response.payload}',
  );

  if (response.payload == null || response.payload!.isEmpty) {
    developer.log('[main] Notification response has no payload.');
    return;
  }

  try {
    final payloadData = jsonDecode(response.payload!);
    final int notificationId = payloadData['notificationId'];
    final List<dynamic> geofenceIds = payloadData['geofenceIds'] ?? [];

    if (response.actionId == 'com.intelliboro.DO_NOW') {
      developer.log(
        '[main] Do Now action selected for notification $notificationId',
      );
      
      // Cancel the notification
      await flutterLocalNotificationsPlugin.cancel(notificationId);
      
      // Start the task timer
      final taskTimerService = TaskTimerService();
      final taskRepository = TaskRepository();
      
      if (geofenceIds.isNotEmpty) {
        final tasks = await taskRepository.getTasks();
        final tasksForGeofence = tasks.where((task) => 
          geofenceIds.contains(task.geofenceId) && !task.isCompleted
        ).toList();
        
        if (tasksForGeofence.isNotEmpty) {
          // Find highest priority task
          final highestPriorityTask = tasksForGeofence.reduce((a, b) => 
            a.getEffectivePriority() > b.getEffectivePriority() ? a : b
          );
          
          bool started = await taskTimerService.startTask(highestPriorityTask);
          developer.log('[main] Task timer started: $started for task: ${highestPriorityTask.taskName}');
          
          // Show a quick feedback notification to confirm timer started
          if (started) {
            await flutterLocalNotificationsPlugin.show(
              99999, // Use a specific ID for feedback notifications
              'Timer Started! ⏰',
              'Now tracking time for "${highestPriorityTask.taskName}"',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'timer_feedback',
                  'Timer Feedback',
                  channelDescription: 'Confirms when task timers start',
                  importance: Importance.defaultImportance,
                  priority: Priority.defaultPriority,
                  showWhen: true,
                  autoCancel: true,
                  timeoutAfter: 3000, // Auto dismiss after 3 seconds
                ),
              ),
            );
          } else {
            // Show feedback if task was rescheduled instead
            await flutterLocalNotificationsPlugin.show(
              99998,
              'Task Rescheduled 📅',
              'Higher priority task active. "${highestPriorityTask.taskName}" moved to later.',
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
        }
      }
    } else if (response.actionId == 'com.intelliboro.DO_LATER') {
      developer.log(
        '[main] Do Later action selected for notification $notificationId',
      );
      
      // Cancel the notification
      await flutterLocalNotificationsPlugin.cancel(notificationId);
      
      // Reschedule tasks
      final taskTimerService = TaskTimerService();
      final taskRepository = TaskRepository();
      
      if (geofenceIds.isNotEmpty) {
        final tasks = await taskRepository.getTasks();
        final tasksForGeofence = tasks.where((task) => 
          geofenceIds.contains(task.geofenceId) && !task.isCompleted
        ).toList();
        
        for (final task in tasksForGeofence) {
          await taskTimerService.rescheduleTaskLater(task);
          developer.log('[main] Rescheduled task: ${task.taskName}');
        }
      }
    } else {
      // Default tap on notification
      developer.log(
        '[main] Default notification tap for notification $notificationId. Cancelling it.',
      );
      await flutterLocalNotificationsPlugin.cancel(notificationId);
    }
  } catch (e, stackTrace) {
    developer.log(
      '[main] Error handling notification response: $e',
      error: e,
      stackTrace: stackTrace,
    );
  }
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
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        developer.log('[main] Notification tapped: ${response.payload}');
        _onNotificationResponse(response);
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
      final bool? permissionGranted = await androidImplementation.requestNotificationsPermission();
      developer.log("[main] Notification permission granted: $permissionGranted");
      
      final bool? exactAlarmsPermission = await androidImplementation.requestExactAlarmsPermission();
      developer.log("[main] Exact alarms permission granted: $exactAlarmsPermission");
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