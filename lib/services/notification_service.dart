import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:developer' as developer;

final FlutterLocalNotificationsPlugin notificationPlugin =
    FlutterLocalNotificationsPlugin();

/// Initialize the plugin and timezone data. Call this from main before using notifications.
Future<void> initializeNotifications({String? defaultIcon}) async {
  try {
    tz.initializeTimeZones();
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    // Note: caller may set timezone via tz.setLocalLocation if needed
    developer.log('[NotificationService] Timezone initialized: $timeZoneName');

    final AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings(defaultIcon ?? '@mipmap/ic_launcher');
    final DarwinInitializationSettings initializationSettingsIOS =
        const DarwinInitializationSettings(
          defaultPresentBanner: true,
          defaultPresentSound: true,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    final bool? initialized = await notificationPlugin.initialize(
      initializationSettings,
    );
    developer.log('[NotificationService] Initialized plugin: $initialized');
  } catch (e, st) {
    developer.log(
      '[NotificationService] Failed to initialize: $e',
      error: e,
      stackTrace: st,
    );
    rethrow;
  }
}