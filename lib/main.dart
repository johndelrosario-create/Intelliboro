import 'package:flutter/material.dart';
// import 'package:intelliboro/model/task_model.dart'; // Potentially unused if TaskListViewModel uses GeofenceData
// import 'package:intelliboro/repository/task_repository.dart'; // Potentially unused
import 'package:intelliboro/theme.dart';
// import 'package:native_geofence/native_geofence.dart'; // Potentially unused in main.dart directly
import 'package:intelliboro/views/create_task_view.dart'; // Used by old HomePage
import 'package:permission_handler/permission_handler.dart'; // Used by old HomePage
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'dart:async'; // Used by old HomePage
import 'dart:ui'; // Used by old HomePage
import 'dart:isolate'; // Used by old HomePage
// import 'package:intelliboro/viewModel/Geofencing/map_viewmodel.dart'; // No longer provided globally
// import 'package:intelliboro/viewModel/task_list_viewmodel.dart'; // No longer provided globally
// import 'package:provider/provider.dart'; // Provider package removed
import 'package:intelliboro/views/task_list_view.dart';
import 'package:intelliboro/services/location_service.dart'; // Import LocationService
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Add this
import 'dart:developer' as developer; // For logging
import 'dart:convert';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

// Define the access token
const String accessToken = String.fromEnvironment('ACCESS_TOKEN');

// Create an instance of the plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void _handleNotificationResponse(NotificationResponse response) async {
  developer.log(
    '[main] Handling notification response. ID: ${response.id}, Action: ${response.actionId}, Payload: ${response.payload}',
  );

  if (response.payload == null || response.payload!.isEmpty) {
    developer.log('[main] Notification response has no payload.');
    return;
  }

  final payloadData = jsonDecode(response.payload!);
  final int notificationId = payloadData['notificationId'];

  if (response.actionId == 'snooze_action') {
    developer.log(
      '[main] Snooze action selected for notification $notificationId',
    );
    // Don't cancel the original, just schedule a new one. The original will be cancelled by the system.
    // Let's schedule a new one for 5 minutes later.

    final String title = payloadData['title'];
    final String body = payloadData['body'];

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'geofence_alerts',
          'Geofence Alerts',
          channelDescription: 'Important alerts for location-based events',
          importance: Importance.max,
          priority: Priority.max,
          autoCancel: false,
          ongoing: true,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction('do_now_action', 'Do Now'),
            AndroidNotificationAction('snooze_action', 'Snooze (5 min)'),
          ],
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      notificationId, // Reuse the same ID
      title,
      'SNOOZED: $body', // Prepend text to indicate it was snoozed
      tz.TZDateTime.now(tz.local).add(const Duration(minutes: 5)),
      platformChannelSpecifics,
      payload: response.payload, // Resend the same payload
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
    developer.log('[main] Notification $notificationId snoozed for 5 minutes.');
  } else {
    // This handles both the 'do_now_action' and a normal tap on the notification.
    developer.log(
      '[main] Do Now / Default action selected for notification $notificationId. Cancelling it.',
    );
    await flutterLocalNotificationsPlugin.cancel(notificationId);
    // TODO: In the future, this is where you would trigger the task timer.
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        _handleNotificationResponse(response);
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

// ... (Keep existing HomePage and TaskList widgets as they might contain other logic or be placeholders for future refactoring)
// It seems HomePage and its _HomePageState and the TaskList widget below are part of an older UI structure.
// For now, they will remain, but the app starts with TaskListView.

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String geofenceState = 'N/A';
  final ReceivePort port = ReceivePort();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _initializeGeofencePort();
  }

  void _initializeGeofencePort() {
    // Remove any existing port mapping first
    IsolateNameServer.removePortNameMapping('native_geofence_send_port');

    // Register the port
    final bool registered = IsolateNameServer.registerPortWithName(
      port.sendPort,
      'native_geofence_send_port',
    );

    if (!registered) {
      debugPrint('Failed to register native_geofence_send_port');
      return;
    }

    port.listen((dynamic data) {
      debugPrint('Received geofence event: $data');
      if (mounted) {
        setState(() {
          geofenceState = data.toString();
        });
      }
    });
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Notification clicked: ${response.payload}');
        // Handle notification click
      },
    );

    // Create the notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'geofence_channel',
      'Geofence Notifications',
      description: 'Notifications for geofence events',
      importance: Importance.high,
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
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }
  }

  // _checkPermissions is effectively replaced by AppInitializer for the main app flow.
  // If HomePage is used independently and needs to check/request permissions:
  Future<bool> _ensurePermissionsForHomePage() async {
    bool locationOK = await LocationService().requestLocationPermission();
    PermissionStatus notificationOK = await Permission.notification.request();
    return locationOK && (notificationOK.isGranted || notificationOK.isLimited);
  }

  @override
  Widget build(BuildContext context) {
    // HomePage should not have its own MaterialApp if it's part of a larger app structure.
    // Assuming HomePage might be pushed onto the Navigator stack of the main MaterialApp.
    return Scaffold(
      // Changed from MaterialApp to Scaffold
      appBar: AppBar(title: Text(widget.title)), // Added AppBar for context
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(15.0), // Consistent padding
              child: Text('21 March, 2025', style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(height: 40),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 15.0,
              ), // Consistent padding
              child: Text(
                'Welcome!',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 60),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 15.0,
              ), // Consistent padding
              child: Text(
                'Tasks (Old UI - Geofence State: $geofenceState)', // Clarified it's old UI
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Expanded(child: TaskList()), // This TaskList is the old one
            const Center(child: Text("This is the old HomePage UI.")),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      floatingActionButton: FloatingActionButton(
        tooltip: 'New Task (via Old UI)',
        child: const Icon(Icons.add),
        onPressed: () async {
          if (!mounted) return;
          bool hasPermissions = await _ensurePermissionsForHomePage();

          if (!mounted) return;
          if (hasPermissions) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) {
                  return TaskCreation(showMap: true);
                },
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Permissions needed to create a task with map.'),
              ),
            );
            // Optionally, guide to settings again or show the TaskCreation view with map disabled
            // Navigator.push(
            //   context,
            //   MaterialPageRoute(
            //     builder: (context) {
            //       return TaskCreation(showMap: false);
            //     },
            //   ),
            // );
          }
        },
      ),
    );
  }
}

// This TaskList widget seems to be an older version.
// The new TaskListView uses GeofenceData and TaskListViewModel.
class TaskList extends StatefulWidget {
  const TaskList({super.key});

  @override
  State<TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<TaskList> {
  // late Future<List<TaskModel>> _tasksFuture; // Uses old TaskModel
  // @override
  // void initState() {
  //   super.initState();
  //   _tasksFuture = TaskRepository().getTasks(); // Uses old TaskRepository
  // }

  @override
  Widget build(BuildContext context) {
    // This FutureBuilder setup is for the old TaskModel and TaskRepository
    // return FutureBuilder<List<TaskModel>>(
    //   future: TaskRepository().getTasks(),
    //   builder: (context, snapshot) {
    //     if (snapshot.connectionState == ConnectionState.waiting) {
    //       return Center(child: CircularProgressIndicator());
    //     } else if (snapshot.hasError) {
    //       return Center(child: Text('Error: ${snapshot.error}'));
    //     } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
    //       return Center(child: Text('No tasks available'));
    //     } else {
    //       final tasks = snapshot.data!;
    //       return ListView.separated(
    //         padding: const EdgeInsets.all(22),
    //         itemCount: tasks.length,
    //         itemBuilder: (BuildContext context, int index) {
    //           return Container(
    //             decoration: BoxDecoration(
    //               borderRadius: BorderRadius.circular(8.0),
    //               border: Border.all(
    //                 color: Colors.blueGrey.shade100,
    //                 width: 1.0,
    //               ),
    //             ),
    //             height: 50,
    //             child: Padding(
    //               padding: const EdgeInsets.all(8.0),
    //               child: Text(
    //                 tasks[index].taskName,
    //                 style: TextStyle(fontSize: 20),
    //               ),
    //             ),
    //           );
    //         },
    //         separatorBuilder:
    //             (BuildContext context, int index) => SizedBox(height: 8),
    //       );
    //     }
    //   },
    // );
    return const Center(
      child: Text("Old TaskList widget. App uses TaskListView via main.dart."),
    ); // Placeholder
  }
}
