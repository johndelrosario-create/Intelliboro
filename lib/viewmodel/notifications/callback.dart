import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:developer' as developer;
import 'dart:ui' show IsolateNameServer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart' as native_geofence;
import 'package:sqflite/sqflite.dart';

import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/services/database_service.dart';

@pragma('vm:entry-point')
Future<void> geofenceTriggered(native_geofence.GeofenceCallbackParams params) async {
  Database? database;

  try {
    developer.log(
      '[GeofenceCallback] Starting geofence callback with params: ${params.toString()}',
    );

    // Validate input parameters
    if (params.geofences.isEmpty) {
      developer.log(
        '[GeofenceCallback] WARNING: No geofences provided in params',
      );
      return;
    }

    // Filter for 'enter' events before proceeding
    if (params.event != native_geofence.GeofenceEvent.enter) {
      developer.log('[GeofenceCallback] Received event: ${params.event.name}, which is not an ENTER event. Skipping notification and history saving.');
      // Close the database if it was opened, as we are returning early.
      if (database != null && database.isOpen) {
        try {
          await database.close();
          developer.log('[GeofenceCallback] Closed database connection after skipping non-enter event.');
        } catch (e) {
          developer.log('[GeofenceCallback] Error closing database after skipping non-enter event: $e');
        }
      }
      return;
    }

    developer.log('[GeofenceCallback] Processing ENTER event for geofence(s): ${params.geofences.map((g) => g.id).join(', ')}');

    // Log geofence details (now only for enter events)
    for (final geofence in params.geofences) {
      developer.log('[GeofenceCallback] Details for geofence: ${geofence.id}');
    }

    // Initialize database service
    final DatabaseService dbService = DatabaseService();

    // Open database connection with error handling
    try {
      developer.log(
        '[GeofenceCallback] Attempting to open database connection...',
      );
      database = await dbService.openNewBackgroundConnection(readOnly: false);

      if (!database.isOpen) {
        developer.log(
          '[GeofenceCallback] ERROR: Database connection is not open',
        );
        return;
      }
      developer.log(
        '[GeofenceCallback] Successfully opened database connection. Path: ${database.path}',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[GeofenceCallback] CRITICAL: Failed to open database connection',
        error: e,
        stackTrace: stackTrace,
      );
      // Try to rethrow to see the full error in the native logs
      rethrow;
    }
    developer.log(
      '[GeofenceCallback] Starting geofence callback for event: ${params.event.name}',
    );
    developer.log(
      '[GeofenceCallback] Event: ${params.event}, Geofence IDs: ${params.geofences.map((g) => g.id).toList()}, Location: ${params.location}',
    );

    // First, try to send the event through the port
    final SendPort? sendPort = IsolateNameServer.lookupPortByName(
      'native_geofence_send_port',
    );
    if (sendPort != null && params.location != null) {
      sendPort.send({
        'event': params.event.name,
        'geofenceIds': params.geofences.map((g) => g.id).toList(),
        'location': {
          'latitude': params.location!.latitude,
          'longitude': params.location!.longitude,
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      developer.log('[GeofenceCallback] Successfully sent event through port');
    }

    // --- Database Access for Background Isolate ---
    // We already have a database connection in the 'database' variable
    developer.log(
      '[GeofenceCallback] Using background DB connection. Path: ${database.path}',
    );

    // Get geofence details from storage, using the existing database connection
    final storage = GeofenceStorage(db: database);
    // --- End Database Access ---

    // Create and initialize a new notifications plugin instance locally
    final plugin = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        developer.log(
          '[Notifications] Notification clicked: ${response.payload}',
        );
      },
    );

    // Create the notification channel (safe to call multiple times)
    const String channelId = 'geofence_alerts';
    const String channelName = 'Geofence Alerts';

    // Create the channel with proper settings
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: 'Important alerts for location-based events',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    developer.log(
      '[GeofenceCallback] Created notification channel: $channelId',
    );

    String notificationTitle = 'Location Alert';
    String notificationBody = '';

    for (final geofence in params.geofences) {
      final geofenceData = await storage.getGeofenceById(geofence.id);
      if (geofenceData != null) {
        final eventType =
            params.event == native_geofence.GeofenceEvent.enter ? 'entered' : 'exited';
        notificationBody += 'You have $eventType ${geofenceData.task}\n';
      }
    }

    if (notificationBody.isEmpty) {
      notificationBody =
          'Event: ${params.event.name} for geofences: ${params.geofences.map((g) => g.id).join(", ")}';
    }

    // Create the notification details with high priority
    final AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
          channel.id, // Must match the channel ID
          channel.name, // Must match the channel name
          channelDescription: 'Alerts when entering or exiting geofence areas',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'New geofence alert',
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.alarm,
          showWhen: true,
          autoCancel: false,
          channelShowBadge: true,
          icon: '@mipmap/ic_launcher',
          styleInformation: const BigTextStyleInformation(''),
        );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidNotificationDetails,
    );

    developer.log(
      '[GeofenceCallback] Notification details created with channel: ${channel.id}',
    );

    // Show the notification with a unique ID
    final notificationId = Random().nextInt(2147483647);

    final payloadData = {
      'notificationId': notificationId,
      'title': notificationTitle,
      'body': notificationBody,
      'geofenceIds': params.geofences.map((g) => g.id).toList(),
    };
    final payloadJson = jsonEncode(payloadData);

    try {
      await plugin.show(
        notificationId,
        notificationTitle,
        notificationBody,
        platformChannelSpecifics,
        payload: payloadJson,
      );
      developer.log('[GeofenceCallback] Notification shown successfully');
    } catch (e, stackTrace) {
      developer.log(
        '[GeofenceCallback] Error showing notification: $e',
        error: e,
        stackTrace: stackTrace,
      );

      // Try showing a basic notification as fallback
      try {
        await plugin.show(
          notificationId,
          'Location Alert',
          'You have ${params.event.name.toLowerCase()} a geofence area',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'geofence_alerts',
              'Geofence Alerts',
              importance: Importance.max,
              priority: Priority.max,
              showWhen: true,
            ),
          ),
        );
        developer.log('[GeofenceCallback] Fallback notification shown');
      } catch (e2) {
        developer.log(
          '[GeofenceCallback] Fallback notification also failed: $e2',
        );
      }
    }

    developer.log(
      '[GeofenceCallback] Successfully showed notification: ID=$notificationId, Title=$notificationTitle, Body=$notificationBody',
    );

    // --- Save to History ---
    developer.log(
      '[GeofenceCallback] Attempting to save notification to history...',
    );

    // Use a local variable for database operations
    Database currentDb = database; // Safe because we checked for null above

    try {
      // Ensure we have a valid database connection
      if (!currentDb.isOpen) {
        developer.log(
          '[GeofenceCallback] WARNING: Database connection is not open, reconnecting...',
        );
        final newDb = await dbService.openNewBackgroundConnection(readOnly: false);
        if (newDb == null || !newDb.isOpen) {
          developer.log(
            '[GeofenceCallback] ERROR: Failed to reopen database connection',
          );
          return;
        }
        currentDb = newDb;
      }

      // Log database path for debugging
      developer.log('[GeofenceCallback] Database path: ${currentDb.path}');

      // Process each geofence
      for (final geofence in params.geofences) {
        try {
          // Ensure we're still connected
          if (!currentDb.isOpen) {
            throw Exception('Database connection lost');
          }

          final geofenceData = await storage.getGeofenceById(geofence.id);

          // Create the notification record with explicit timestamp
          final now = DateTime.now();
          final recordMap = {
            'notification_id': notificationId,
            'geofence_id': geofence.id,
            'task_name': geofenceData?.task,
            'event_type': params.event.name,
            'body': notificationBody,
            'timestamp':
                now.millisecondsSinceEpoch ~/ 1000, // Convert to seconds
          };

          developer.log(
            '[GeofenceCallback] Attempting to insert record: $recordMap',
          );

          // Use DatabaseService to insert the record
          await dbService.insertNotificationHistory(currentDb, recordMap);

          developer.log(
            '[GeofenceCallback] Successfully saved record for geofence ID: ${geofence.id}',
          );

          // Notify the main isolate to update the UI
          final SendPort? mainIsolateSendPort = IsolateNameServer.lookupPortByName('notification_update_port');
          if (mainIsolateSendPort != null) {
            mainIsolateSendPort.send('update_history');
            developer.log('[GeofenceCallback] Sent update_history message to main isolate.');
          } else {
            developer.log('[GeofenceCallback] WARNING: Could not find SendPort for notification_update_port.');
          }
        } catch (e, stackTrace) {
          developer.log(
            '[GeofenceCallback] Error saving record for geofence ${geofence.id}: $e',
            error: e,
            stackTrace: stackTrace,
          );

          // Try one more time with a fresh connection
          try {
            developer.log(
              '[GeofenceCallback] Retrying with fresh database connection...',
            );
            // Ensure the retry connection is writable
            final retryDb = await dbService.openNewBackgroundConnection(readOnly: false);
            if (retryDb.isOpen) {
              final geofenceData = await storage.getGeofenceById(geofence.id);
              final now = DateTime.now();
              final recordMap = {
                'notification_id': notificationId,
                'geofence_id': geofence.id,
                'task_name': geofenceData?.task,
                'event_type': params.event.name,
                'body': notificationBody,
                'timestamp':
                    now.millisecondsSinceEpoch ~/ 1000, // Convert to seconds
              };

              await dbService.insertNotificationHistory(retryDb, recordMap);
              currentDb = retryDb; // Update current DB reference
              developer.log(
                '[GeofenceCallback] Successfully saved record on retry',
              );

              // Notify the main isolate to update the UI
              final SendPort? mainIsolateSendPortRetry = IsolateNameServer.lookupPortByName('notification_update_port');
              if (mainIsolateSendPortRetry != null) {
                mainIsolateSendPortRetry.send('update_history');
                developer.log('[GeofenceCallback] Sent update_history message to main isolate on retry.');
              } else {
                developer.log('[GeofenceCallback] WARNING: Could not find SendPort for notification_update_port on retry.');
              }
            }
          } catch (retryError, retryStack) {
            developer.log(
              '[GeofenceCallback] Failed to save record on retry: $retryError',
              error: retryError,
              stackTrace: retryStack,
            );
          }
        }
      }

      // Verify the records were saved
      try {
        final count =
            Sqflite.firstIntValue(
              await currentDb.rawQuery(
                'SELECT COUNT(*) FROM notification_history',
              ),
            ) ??
            0;
        developer.log(
          '[GeofenceCallback] Total notification history records: $count',
        );

        // Log the most recent records for debugging
        final recentRecords = await currentDb.query(
          'notification_history',
          orderBy: 'timestamp DESC',
          limit: 5,
        );
        developer.log('[GeofenceCallback] Most recent records: $recentRecords');
      } catch (e) {
        developer.log(
          '[GeofenceCallback] Error accessing notification history: $e',
        );
      }

      developer.log(
        '[GeofenceCallback] Finished processing ${params.geofences.length} geofence(s) for notification history.',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[GeofenceCallback] CRITICAL ERROR in notification history processing: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
    // --- End Save to History ---
  } catch (e, stackTrace) {
    developer.log(
      '[GeofenceCallback] Error in geofence callback: $e',
      error: e,
      stackTrace: stackTrace,
    );
  } finally {
    // IMPORTANT: Always close the background database connection to prevent leaks.
    try {
      if (database != null && database.isOpen) {
        await database.close();
        developer.log(
          '[GeofenceCallback] Closed background database connection.',
        );
      }
    } catch (e) {
      developer.log('[GeofenceCallback] Error closing database connection: $e');
    }
  }
}

// Helper function to capitalize strings (unused but kept for future use)
@visibleForTesting
String capitalize(String s) =>
    s.isNotEmpty ? s[0].toUpperCase() + s.substring(1).toLowerCase() : s;
