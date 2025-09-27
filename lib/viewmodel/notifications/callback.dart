import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:developer' as developer;
import 'dart:ui' show IsolateNameServer; // For SendPort lookup

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:native_geofence/native_geofence.dart' as native_geofence;
import 'package:sqflite/sqflite.dart';

import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/services/database_service.dart';
import 'package:intelliboro/services/context_detection_service.dart';
import 'package:intelliboro/services/text_to_speech_service.dart';

@pragma('vm:entry-point')
Future<void> geofenceTriggered(
  native_geofence.GeofenceCallbackParams params,
) async {
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
      developer.log(
        '[GeofenceCallback] Received event: ${params.event.name}, which is not an ENTER event. Skipping notification and history saving.',
      );
      // Close the database if it was opened, as we are returning early.
      if (database != null && database.isOpen) {
        try {
          await database.close();
          developer.log(
            '[GeofenceCallback] Closed database connection after skipping non-enter event.',
          );
        } catch (e) {
          developer.log(
            '[GeofenceCallback] Error closing database after skipping non-enter event: $e',
          );
        }
      }
      return;
    }

    developer.log(
      '[GeofenceCallback] Processing ENTER event for geofence(s): ${params.geofences.map((g) => g.id).join(', ')}',
    );

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

    String notificationTitle = 'Task reminder';
    String notificationBody = '';

    for (final geofence in params.geofences) {
      final geofenceData = await storage.getGeofenceById(geofence.id);
      if (geofenceData != null) {
        final eventType =
            params.event == native_geofence.GeofenceEvent.enter
                ? 'entered'
                : 'exited';
        notificationBody += 'You have task ${geofenceData.task}\n';
      }
    }

    if (notificationBody.isEmpty) {
      notificationBody =
          'Event: ${params.event.name} for geofences: ${params.geofences.map((g) => g.id).join(", ")}';
    }

    // Create the notification details with sound enabled (plays BEFORE TTS)
    final AndroidNotificationDetails
    androidNotificationDetails = AndroidNotificationDetails(
      channel.id, // Must match the channel ID
      channel.name, // Must match the channel name
      channelDescription:
          'Alerts when entering or exiting geofence areas (sound alert then TTS)',
      importance: Importance.max, // High importance for immediate sound
      priority: Priority.high,
      ticker: 'New geofence alert',
      playSound: true, // Enabled - notification sound plays first
      enableVibration: true, // Keep vibration for tactile feedback
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.alarm, // Back to alarm for urgency
      showWhen: true,
      autoCancel: true, // Allow user to dismiss easily
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

    // --- Show the notification FIRST (with sound) to alert user ---
    final notificationId = Random().nextInt(2147483647);

    final payloadData = {
      'notificationId': notificationId,
      'title': notificationTitle,
      'body': notificationBody,
      'geofenceIds': params.geofences.map((g) => g.id).toList(),
    };
    final payloadJson = jsonEncode(payloadData);

    try {
      developer.log(
        '[GeofenceCallback] Showing notification with sound first...',
      );
      await plugin.show(
        notificationId,
        notificationTitle,
        notificationBody,
        platformChannelSpecifics,
        payload: payloadJson,
      );
      developer.log('[GeofenceCallback] Notification shown successfully');

      // Short delay to let notification sound play
      await Future.delayed(const Duration(milliseconds: 1500));
    } catch (e, stackTrace) {
      developer.log(
        '[GeofenceCallback] Error showing notification: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }

    // --- Then Trigger Text-to-Speech Notifications AFTER notification sound ---
    try {
      developer.log(
        '[GeofenceCallback] Attempting to trigger TTS notifications...',
      );

      // Process each geofence for TTS
      for (final geofence in params.geofences) {
        try {
          developer.log(
            '[GeofenceCallback] Processing geofence ${geofence.id} for TTS',
          );

          final geofenceData = await storage.getGeofenceById(geofence.id);
          developer.log(
            '[GeofenceCallback] Geofence data retrieved: ${geofenceData?.toJson()}',
          );

          if (geofenceData != null &&
              geofenceData.task != null &&
              geofenceData.task!.isNotEmpty) {
            developer.log(
              '[GeofenceCallback] Found task for TTS: ${geofenceData.task}',
            );

            // Try direct TTS service approach first
            try {
              developer.log(
                '[GeofenceCallback] Initializing TTS service for geofence callback...',
              );
              final ttsService = TextToSpeechService(); // Singleton instance

              // Force re-initialization in background context
              developer.log('[GeofenceCallback] Calling TTS init...');
              await ttsService.init();
              developer.log('[GeofenceCallback] TTS init completed');

              // Check if TTS is available
              developer.log('[GeofenceCallback] Checking TTS availability...');
              final isAvailable = await ttsService.isAvailable();
              developer.log(
                '[GeofenceCallback] TTS availability: $isAvailable',
              );
              developer.log(
                '[GeofenceCallback] TTS enabled: ${ttsService.isEnabled}',
              );

              if (isAvailable && ttsService.isEnabled) {
                developer.log(
                  '[GeofenceCallback] Attempting to speak: "${geofenceData.task}"',
                );
                await ttsService.speakTaskNotification(
                  geofenceData.task!,
                  'location',
                );
                developer.log(
                  '[GeofenceCallback] Direct TTS triggered successfully for: ${geofenceData.task}',
                );

                // Wait longer for TTS to complete before showing notification
                developer.log(
                  '[GeofenceCallback] Waiting for TTS to complete before showing notification...',
                );
                int waitTime = 0;
                const maxWaitTime = 10000; // 10 seconds max
                const checkInterval = 500; // Check every 500ms

                while (ttsService.isSpeaking && waitTime < maxWaitTime) {
                  await Future.delayed(
                    const Duration(milliseconds: checkInterval),
                  );
                  waitTime += checkInterval;
                  developer.log(
                    '[GeofenceCallback] TTS still speaking, waited ${waitTime}ms',
                  );
                }

                if (waitTime >= maxWaitTime) {
                  developer.log(
                    '[GeofenceCallback] TTS timeout reached, proceeding with notification',
                  );
                } else {
                  developer.log(
                    '[GeofenceCallback] TTS completed after ${waitTime}ms',
                  );
                }

                // Add additional delay to ensure audio system is free
                await Future.delayed(const Duration(milliseconds: 1000));
              } else {
                developer.log(
                  '[GeofenceCallback] TTS not available or disabled. Available: $isAvailable, Enabled: ${ttsService.isEnabled}',
                );
                developer.log('[GeofenceCallback] TTS will not be triggered');
              }
            } catch (directTtsError) {
              developer.log(
                '[GeofenceCallback] Direct TTS failed: $directTtsError, trying context service...',
              );

              // Fallback to context service approach
              try {
                final contextService = ContextDetectionService();
                await contextService.init();

                await contextService.handleGeofenceContext(
                  geofenceData.task!,
                  geofence.id,
                  metadata: {
                    'event_type': params.event.name,
                    'latitude': params.location?.latitude,
                    'longitude': params.location?.longitude,
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                  },
                );
                developer.log(
                  '[GeofenceCallback] Context service TTS triggered for: ${geofenceData.task}',
                );
              } catch (contextError) {
                developer.log(
                  '[GeofenceCallback] Context service TTS also failed: $contextError',
                );
              }
            }
          } else {
            developer.log(
              '[GeofenceCallback] No task found for geofence ${geofence.id} or task is empty',
            );
          }
        } catch (geofenceError) {
          developer.log(
            '[GeofenceCallback] Error processing geofence ${geofence.id} for TTS: $geofenceError',
          );
        }
      }

      developer.log(
        '[GeofenceCallback] TTS notifications processing completed',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[GeofenceCallback] Error triggering TTS notifications: $e',
        error: e,
        stackTrace: stackTrace,
      );
      // Continue execution even if TTS fails
    }
    // --- End Text-to-Speech Notifications ---

    // Notification was already shown above with sound alert

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
        final newDb = await dbService.openNewBackgroundConnection(
          readOnly: false,
        );
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

          // Use DatabaseService to insert the record
          await dbService.insertNotificationHistory(currentDb, recordMap);

          developer.log(
            '[GeofenceCallback] Successfully saved record for geofence ID: ${geofence.id}',
          );

          // Notify the main UI isolate that a new notification was saved
          final SendPort? uiSendPort = IsolateNameServer.lookupPortByName(
            'intelliboro_new_notification_port',
          );
          if (uiSendPort != null) {
            developer.log(
              '[GeofenceCallback] Found UI SendPort, sending notification update signal.',
            );
            uiSendPort.send('new_notification_saved');
          } else {
            developer.log(
              '[GeofenceCallback] WARNING: Could not find UI SendPort \'intelliboro_new_notification_port\'. UI will not be updated immediately.',
            );
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
            final retryDb = await dbService.openNewBackgroundConnection(
              readOnly: false,
            );
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
                '[GeofenceCallback] Successfully saved record on retry for geofence ID: ${geofence.id}', // Added geofence.id for clarity
              );

              // Notify the main UI isolate that a new notification was saved (after retry)
              final SendPort? uiSendPortRetry =
                  IsolateNameServer.lookupPortByName(
                    'intelliboro_new_notification_port',
                  );
              if (uiSendPortRetry != null) {
                developer.log(
                  '[GeofenceCallback] Found UI SendPort (after retry), sending notification update signal.',
                );
                uiSendPortRetry.send('new_notification_saved_after_retry');
              } else {
                developer.log(
                  '[GeofenceCallback] WARNING: Could not find UI SendPort \'intelliboro_new_notification_port\' (after retry). UI will not be updated immediately.',
                );
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
