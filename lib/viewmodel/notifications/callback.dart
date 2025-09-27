import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:developer' as developer;
import 'dart:ui' show IsolateNameServer, Color; // For SendPort lookup and Color
import 'package:flutter/widgets.dart'; // Ensure bindings in background isolate

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// notificationPlugin from the UI isolate is not used in this background callback.
// We'll initialize a local FlutterLocalNotificationsPlugin instance instead.
import 'package:native_geofence/native_geofence.dart' as native_geofence;
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/services/database_service.dart';
import 'package:intelliboro/services/context_detection_service.dart';
import 'package:intelliboro/services/text_to_speech_service.dart';
// import 'package:intelliboro/repository/task_repository.dart'; // unused in callback isolate

@pragma('vm:entry-point')
Future<void> geofenceTriggered(
  native_geofence.GeofenceCallbackParams params,
) async {
  Database? database;

  try {
    developer.log(
      '[GeofenceCallback] Starting geofence callback with params: ${params.toString()}',
    );

    // Ensure Flutter bindings are initialized for this background isolate so
    // plugins (notifications, shared_preferences, etc.) can function.
    try {
      WidgetsFlutterBinding.ensureInitialized();
    } catch (e) {
      developer.log('[GeofenceCallback] Widgets binding ensure failed: $e');
    }

    // Create and initialize a local FlutterLocalNotificationsPlugin instance
    // for use inside this background isolate. The global `notificationPlugin`
    // from the UI isolate is not usable here.
    final FlutterLocalNotificationsPlugin plugin =
        FlutterLocalNotificationsPlugin();
    try {
      final AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      final DarwinInitializationSettings initializationSettingsIOS =
          const DarwinInitializationSettings();
      final InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS,
          );
      await plugin.initialize(initializationSettings);
      developer.log(
        '[GeofenceCallback] Local notifications plugin initialized',
      );
    } catch (e) {
      developer.log(
        '[GeofenceCallback] Failed to init local notifications: $e',
      );
    }

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
      // No DB was opened yet in this path; nothing to close.
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

    // First, try to send the event through the port. Generate a notificationId
    // early so the UI isolate can cancel the notification if desired.
    final SendPort? sendPort = IsolateNameServer.lookupPortByName(
      'native_geofence_send_port',
    );
    final int earlyNotificationId = Random().nextInt(2147483647);

    // Create a short-lived acknowledgment ReceivePort and register it under
    // a name the UI isolate can look up. The background isolate will wait
    // briefly for an ack; if received, it will suppress the audible
    // notification/TTS to avoid race conditions.
    final String ackPortName = 'native_geofence_ack_port_$earlyNotificationId';
    final receiveForAck = ReceivePort();
    try {
      IsolateNameServer.registerPortWithName(
        receiveForAck.sendPort,
        ackPortName,
      );
    } catch (e) {
      developer.log('[GeofenceCallback] Could not register ack port: $e');
    }

    if (sendPort != null && params.location != null) {
      sendPort.send({
        'event': params.event.name,
        'geofenceIds': params.geofences.map((g) => g.id).toList(),
        'location': {
          'latitude': params.location!.latitude,
          'longitude': params.location!.longitude,
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'notificationId': earlyNotificationId,
        // Tell the UI which ack port to call if it suppresses the notification
        'ackPortName': ackPortName,
      });
      developer.log(
        '[GeofenceCallback] Successfully sent event through port with notificationId=$earlyNotificationId and ackPortName=$ackPortName',
      );
    }

    // --- Database Access for Background Isolate ---
    // We already have a database connection in the 'database' variable
    developer.log(
      '[GeofenceCallback] Using background DB connection. Path: ${database.path}',
    );

    // Get geofence details from storage, using the existing database connection
    final storage = GeofenceStorage(db: database);
    // --- End Database Access ---

    // Remove debug/progress notifications

    // Use the locally initialized plugin instance for Android-specific channel creation
    final androidPlugin =
        plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    // Create all our notification channels upfront with proper settings
    const AndroidNotificationChannel alertsChannel = AndroidNotificationChannel(
      'geofence_alerts',
      'Geofence Alerts',
      description: 'Important alerts for location-based events',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await androidPlugin?.createNotificationChannel(alertsChannel);

    // Removed progress and debug channels

    developer.log(
      '[GeofenceCallback] Created/ensured all notification channels',
    );

    // Removed debug verification notifications

    String notificationTitle = 'Task reminder';
    String notificationBody = '';

    for (final geofence in params.geofences) {
      final geofenceData = await storage.getGeofenceById(geofence.id);
      if (geofenceData != null) {
        // Add event type info to notification body
        final eventType =
            params.event == native_geofence.GeofenceEvent.enter
                ? 'entered'
                : 'exited';
        notificationBody +=
            'You have $eventType the area for task ${geofenceData.task}\n';
      }
    }

    if (notificationBody.isEmpty) {
      notificationBody =
          'Event: ${params.event.name} for geofences: ${params.geofences.map((g) => g.id).join(", ")}';
    }

    // Removed progress notifications while building

    // Removed final progress notification before showing task alert

    // Create the notification details with sound enabled (plays BEFORE TTS)
    // Add action buttons for persistent notifications
    final AndroidNotificationDetails
    androidNotificationDetails = AndroidNotificationDetails(
      'geofence_alerts', // Main alerts channel
      'Geofence Alerts',
      channelDescription:
          'Alerts when entering or exiting geofence areas (sound alert then TTS)',
      importance: Importance.max,
      priority: Priority.max, // Changed to max for immediate display
      ticker: 'New geofence alert',
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.alarm,
      showWhen: true,
      autoCancel: false, // Persistent until user acts
      ongoing: true, // Make notification persistent
      icon: '@mipmap/ic_launcher',
      styleInformation: const BigTextStyleInformation(''),
      fullScreenIntent:
          true, // Force immediate display even when app in background
      channelShowBadge: true,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 255, 200, 0),
      ledOnMs: 1000,
      ledOffMs: 500,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'com.intelliboro.DO_NOW',
          'Do Now \ud83c\udfc3\u200d\u2642\ufe0f',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          'com.intelliboro.DO_LATER',
          'Do Later \u23f0',
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidNotificationDetails,
    );

    developer.log(
      '[GeofenceCallback] Notification details created with channel: geofence_alerts',
    );

    // --- Show the notification FIRST (with sound) to alert user ---
    // Use the earlyNotificationId so the UI isolate can correlate and cancel it.
    final notificationId = earlyNotificationId;

    // Gather task IDs matching these geofence ids using the background DB
    List<int> matchedTaskIds = [];
    try {
      final geofenceIdList = params.geofences.map((g) => g.id).toList();
      developer.log(
        '[GeofenceCallback] Background query geofenceIdList: $geofenceIdList',
      );
      if (geofenceIdList.isNotEmpty) {
        final placeholders = List.filled(geofenceIdList.length, '?').join(',');
        final whereClause =
            'geofence_id IN ($placeholders) AND isCompleted = 0';
        final rows = await database.query(
          'tasks',
          columns: ['id', 'geofence_id'],
          where: whereClause,
          whereArgs: geofenceIdList,
        );
        developer.log(
          '[GeofenceCallback] Background DB returned ${rows.length} matching task rows: $rows',
        );
        for (final r in rows) {
          final idVal = r['id'];
          if (idVal is int)
            matchedTaskIds.add(idVal);
          else if (idVal is String) {
            final parsed = int.tryParse(idVal);
            if (parsed != null) matchedTaskIds.add(parsed);
          }
        }

        if (matchedTaskIds.isEmpty) {
          try {
            final allRows = await database.query(
              'tasks',
              columns: ['id', 'geofence_id', 'taskName', 'isCompleted'],
            );
            developer.log(
              '[GeofenceCallback] No matches - full tasks table snapshot: $allRows',
            );
          } catch (dumpError, dumpSt) {
            developer.log(
              '[GeofenceCallback] Failed to dump all tasks for debugging: $dumpError',
              error: dumpError,
              stackTrace: dumpSt,
            );
          }
        }
      }
    } catch (e, st) {
      developer.log(
        '[GeofenceCallback] Error while collecting task IDs from background DB: $e',
        error: e,
        stackTrace: st,
      );
    }

    // Before constructing payload, check SharedPreferences for an active task
    // so background can deterministically suppress audible notifications
    // even when UI isolate might be asleep.
    bool preemptivelySuppressed = false;
    try {
      developer.log(
        '[GeofenceCallback] Checking SharedPreferences for active_task_id',
      );
      final prefs = await SharedPreferences.getInstance();
      final int? activeTaskId = prefs.getInt('active_task_id');
      if (activeTaskId != null) {
        developer.log(
          '[GeofenceCallback] Found persisted active_task_id=$activeTaskId',
        );
        try {
          // Query the tasks table for the active task and compute its effective priority
          final rows = await database.query(
            'tasks',
            columns: [
              'id',
              'taskName',
              'taskPriority',
              'isCompleted',
              'geofence_id',
            ],
            where: 'id = ?',
            whereArgs: [activeTaskId],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final row = rows.first;
            final int? tp =
                row['taskPriority'] is int
                    ? row['taskPriority'] as int
                    : int.tryParse(row['taskPriority'].toString());
            final double activePriority = tp != null ? tp.toDouble() : 0.0;

            // Compute incoming highest priority from matchedTaskIds
            double incomingHighest = 0.0;
            if (matchedTaskIds.isNotEmpty) {
              final placeholders = List.filled(
                matchedTaskIds.length,
                '?',
              ).join(',');
              final incomingRows = await database.rawQuery(
                'SELECT id, taskPriority FROM tasks WHERE id IN ($placeholders) AND isCompleted = 0',
                matchedTaskIds,
              );
              for (final r in incomingRows) {
                final int? ip =
                    r['taskPriority'] is int
                        ? r['taskPriority'] as int
                        : int.tryParse(r['taskPriority'].toString());
                if (ip != null)
                  incomingHighest =
                      incomingHighest > ip ? incomingHighest : ip.toDouble();
              }
            }

            developer.log(
              '[GeofenceCallback] (pre-check) Active priority=$activePriority, incomingHighest=$incomingHighest',
            );

            // If we couldn't resolve any matching task IDs from the DB, do not
            // preemptively suppress — allow the early notification to be shown
            // so the user still sees the Do Now/Do Later actions.
            if (matchedTaskIds.isEmpty) {
              developer.log(
                '[GeofenceCallback] No matching task IDs found; will NOT preemptively suppress.',
              );
            } else if (incomingHighest <= activePriority) {
              developer.log(
                '[GeofenceCallback] (pre-check) Active task priority higher or equal; suppressing audible notification preemptively (no background snooze/pending).',
              );
              // Only suppress the early audible notification here; we no longer
              // persist pending state or show a fallback "Added to Do Later"
              // notification in the background isolate. The UI isolate will
              // decide whether to snooze or request a switch and will inform
              // the user appropriately.
              preemptivelySuppressed = true;
            }
          }
        } catch (e, st) {
          developer.log(
            '[GeofenceCallback] Error querying active task from DB: $e',
            error: e,
            stackTrace: st,
          );
        }
      }
    } catch (e) {
      developer.log(
        '[GeofenceCallback] Error reading SharedPreferences for active_task_id: $e',
      );
    }

    final payloadData = {
      'notificationId': notificationId,
      'title': notificationTitle,
      'body': notificationBody,
      'geofenceIds': params.geofences.map((g) => g.id).toList(),
      'taskIds': matchedTaskIds,
    };
    final payloadJson = jsonEncode(payloadData);
    developer.log('[GeofenceCallback] Notification payload JSON: $payloadJson');

    // Defer showing the early notification until after waiting for UI ack to avoid duplicates.
    // The UI isolate will cancel/suppress and post the correct UX if needed.
    if (preemptivelySuppressed) {
      developer.log(
        '[GeofenceCallback] Preemptively suppressed; not showing early audible notification',
      );
    }

    // Then wait briefly for the UI isolate to ack suppression before doing TTS.
    bool ackReceived = false;
    try {
      developer.log(
        '[GeofenceCallback] Waiting up to 4000ms for suppression ack...',
      );
      final completer = Completer<void>();
      late final StreamSubscription sub;
      sub = receiveForAck.listen((message) {
        try {
          developer.log('[GeofenceCallback] Received ack message: $message');
          if (!completer.isCompleted) completer.complete();
        } catch (e) {
          developer.log('[GeofenceCallback] Error processing ack message: $e');
        }
      });

      try {
        await Future.any([
          completer.future,
          Future.delayed(const Duration(milliseconds: 1000)),
        ]);
        if (completer.isCompleted) {
          ackReceived = true;
          developer.log(
            '[GeofenceCallback] Suppression ack received from UI isolate.',
          );
        } else {
          developer.log(
            '[GeofenceCallback] No ack received within timeout; proceeding with TTS.',
          );
        }
      } finally {
        await sub.cancel();
      }
    } catch (e, st) {
      developer.log(
        '[GeofenceCallback] Error while waiting for ack: $e',
        error: e,
        stackTrace: st,
      );
    } finally {
      // Clean up ack port registration
      try {
        IsolateNameServer.removePortNameMapping(ackPortName);
      } catch (e) {
        developer.log(
          '[GeofenceCallback] Failed to remove ack port mapping: $e',
        );
      }
    }

    // If ack was received, UI handled it; do not show an early notification here.
    if (ackReceived) {
      developer.log(
        '[GeofenceCallback] Ack received; UI will handle user-visible notification. Skipping early background notification.',
      );
    } else if (!preemptivelySuppressed) {
      // No ack and not preemptively suppressed: show the early notification now.
      try {
        developer.log(
          '[GeofenceCallback] No ack; showing deferred early notification (id=$notificationId)',
        );
        await plugin.show(
          notificationId,
          notificationTitle,
          notificationBody,
          platformChannelSpecifics,
          payload: payloadJson,
        );
      } catch (e, st) {
        developer.log(
          '[GeofenceCallback] Error showing deferred early notification: $e',
          error: e,
          stackTrace: st,
        );
      }
      // Small delay to allow system audio to settle before TTS
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // --- Then Trigger Text-to-Speech Notifications AFTER notification sound ---
    try {
      developer.log(
        '[GeofenceCallback] Attempting to trigger TTS notifications...',
      );

      // Build set of persisted pending IDs so TTS can choose wording
      final prefsForTts = await SharedPreferences.getInstance();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final Set<int> persistedPendingIds = {};
      for (final k in prefsForTts.getKeys()) {
        if (k.startsWith('pending_task_')) {
          final idStr = k.substring('pending_task_'.length);
          final tid = int.tryParse(idStr);
          if (tid == null) continue;
          final millis = prefsForTts.getInt(k);
          if (millis != null && millis > nowMs) persistedPendingIds.add(tid);
        }
      }

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
            // Determine if this geofence's task was persisted as pending by background/UI
            int? geofenceTaskId;
            try {
              final rows = await database.query(
                'tasks',
                columns: ['id'],
                where: 'geofence_id = ?',
                whereArgs: [geofence.id],
                limit: 1,
              );
              if (rows.isNotEmpty) {
                final idv = rows.first['id'];
                geofenceTaskId =
                    idv is int ? idv : int.tryParse(idv.toString());
              }
            } catch (_) {}

            final bool wasPersistedPending =
                geofenceTaskId != null &&
                persistedPendingIds.contains(geofenceTaskId);
            // Also treat as pending if this task is among matchedTaskIds
            final bool matchedAsPending =
                geofenceTaskId != null &&
                matchedTaskIds.contains(geofenceTaskId);
            final bool shouldAnnouncePending =
                wasPersistedPending || matchedAsPending;

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
                final speakText =
                    shouldAnnouncePending
                        ? '${geofenceData.task} added to pending queue.'
                        : geofenceData.task!;
                developer.log(
                  '[GeofenceCallback] Attempting to speak: "$speakText"',
                );
                await ttsService.speakTaskNotification(
                  speakText,
                  wasPersistedPending ? 'snooze' : 'location',
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
                await Future.delayed(const Duration(milliseconds: 200));
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
        if (!newDb.isOpen) {
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
