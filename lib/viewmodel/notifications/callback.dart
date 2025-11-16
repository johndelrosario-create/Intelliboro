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

import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/services/database_service.dart';

double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371000.0; // Earth radius in meters
  final dLat = (lat2 - lat1) * pi / 180.0;
  final dLon = (lon2 - lon1) * pi / 180.0;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180.0) *
          cos(lat2 * pi / 180.0) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

class _GeofenceTaskBucket {
  final List<int> taskIds = [];
  double highestPriority = 0;
}

class _GeofenceEventDetail {
  final native_geofence.ActiveGeofence geofence;
  final GeofenceData? data;
  final double radiusMeters;
  final double? distanceFromCenter;
  final List<int> taskIds;
  final double highestPriority;

  const _GeofenceEventDetail({
    required this.geofence,
    required this.data,
    required this.radiusMeters,
    required this.distanceFromCenter,
    required this.taskIds,
    required this.highestPriority,
  });

  String get id => geofence.id;

  double get penetration =>
      distanceFromCenter != null
          ? radiusMeters - distanceFromCenter!
          : double.negativeInfinity;
}

class _RecentGeofenceTrigger {
  final String geofenceId;
  final DateTime timestamp;
  final double? triggerLatitude;
  final double? triggerLongitude;
  final double radiusMeters;
  final double distanceFromCenter;
  final double highestPriority;

  const _RecentGeofenceTrigger({
    required this.geofenceId,
    required this.timestamp,
    required this.triggerLatitude,
    required this.triggerLongitude,
    required this.radiusMeters,
    required this.distanceFromCenter,
    required this.highestPriority,
  });
}

const Duration _geofenceDedupWindow = Duration(seconds: 25);
const double _geofenceClusterRadiusMeters = 80.0;
const double _penetrationLeewayMeters = 5.0;
_RecentGeofenceTrigger? _lastGeofenceTrigger;

_GeofenceEventDetail _selectPrimaryDetail(List<_GeofenceEventDetail> details) {
  _GeofenceEventDetail selected = details.first;
  for (final detail in details.skip(1)) {
    if (detail.highestPriority > selected.highestPriority) {
      selected = detail;
      continue;
    }

    if (detail.highestPriority == selected.highestPriority) {
      final double detailPenetration = detail.penetration;
      final double selectedPenetration = selected.penetration;

      if (detailPenetration > selectedPenetration + 0.1) {
        selected = detail;
        continue;
      }

      final double detailDistance =
          detail.distanceFromCenter ?? double.infinity;
      final double selectedDistance =
          selected.distanceFromCenter ?? double.infinity;

      if (detailDistance < selectedDistance) {
        selected = detail;
      }
    }
  }

  return selected;
}

bool _shouldSuppressDueToRecent(
  _GeofenceEventDetail detail,
  native_geofence.Location? triggerLocation,
) {
  final last = _lastGeofenceTrigger;
  if (last == null) return false;

  if (DateTime.now().difference(last.timestamp) > _geofenceDedupWindow) {
    return false;
  }

  if (triggerLocation != null &&
      last.triggerLatitude != null &&
      last.triggerLongitude != null) {
    final separation = _calculateDistance(
      triggerLocation.latitude,
      triggerLocation.longitude,
      last.triggerLatitude!,
      last.triggerLongitude!,
    );
    if (separation > _geofenceClusterRadiusMeters) {
      return false;
    }
  }

  if (last.geofenceId == detail.id) {
    return true;
  }

  if (detail.highestPriority < last.highestPriority) {
    return true;
  }
  if (detail.highestPriority > last.highestPriority) {
    return false;
  }

  final double detailPenetration = detail.penetration;
  final double lastPenetration = last.radiusMeters - last.distanceFromCenter;

  if (detailPenetration <= lastPenetration + _penetrationLeewayMeters) {
    return true;
  }

  return false;
}

@pragma('vm:entry-point')
Future<void> geofenceTriggered(
  native_geofence.GeofenceCallbackParams params,
) async {
  Database? database;
  bool criticalFailure = false;
  String? failureReason;

  try {
    developer.log(
      '[GeofenceCallback] Starting geofence callback with params: ${params.toString()}',
    );

    // Ensure Flutter bindings are initialized for this background isolate so
    // plugins (notifications, shared_preferences, etc.) can function.
    try {
      WidgetsFlutterBinding.ensureInitialized();
    } catch (e) {
      developer.log(
        '[GeofenceCallback] CRITICAL: Widgets binding ensure failed: $e',
      );
      criticalFailure = true;
      failureReason = 'Flutter bindings initialization failed';
    }

    // Create and initialize a local FlutterLocalNotificationsPlugin instance
    // for use inside this background isolate. The global `notificationPlugin`
    // from the UI isolate is not usable here.
    final FlutterLocalNotificationsPlugin plugin =
        FlutterLocalNotificationsPlugin();
    bool pluginInitialized = false;
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
      pluginInitialized = true;
      developer.log(
        '[GeofenceCallback] Local notifications plugin initialized',
      );
    } catch (e) {
      developer.log(
        '[GeofenceCallback] CRITICAL: Failed to init local notifications: $e',
      );
      criticalFailure = true;
      failureReason = 'Notification plugin initialization failed';
    }

    // Show fallback notification if critical components failed
    if (criticalFailure && pluginInitialized) {
      try {
        await plugin.show(
          999999,
          '⚠️ Geofence System Error',
          'Failed to process geofence: $failureReason. Please restart the app.',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'geofence_errors',
              'Geofence Errors',
              channelDescription: 'Critical geofence system errors',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
            ),
          ),
        );
        developer.log('[GeofenceCallback] Fallback error notification shown');
      } catch (fallbackError) {
        developer.log(
          '[GeofenceCallback] Failed to show fallback notification: $fallbackError',
        );
      }
      return;
    } else if (criticalFailure) {
      developer.log(
        '[GeofenceCallback] CRITICAL: Cannot proceed or notify user of failure',
      );
      return;
    }

    // Validate input parameters
    if (params.geofences.isEmpty) {
      developer.log(
        '[GeofenceCallback] CRITICAL: No geofences provided in params',
      );
      // Show diagnostic notification
      try {
        await plugin.show(
          999998,
          '⚠️ Geofence Processing Error',
          'Geofence triggered but no geofence data was provided. This may indicate a system issue.',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'geofence_errors',
              'Geofence Errors',
              channelDescription: 'Critical geofence system errors',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      } catch (e) {
        developer.log(
          '[GeofenceCallback] Failed to show empty geofences error notification: $e',
        );
      }
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
          '[GeofenceCallback] CRITICAL: Database connection is not open',
        );
        // Show fallback notification
        try {
          await plugin.show(
            999997,
            '⚠️ Database Connection Failed',
            'Unable to process geofence notification - database not accessible. Geofences: ${params.geofences.map((g) => g.id).join(", ")}',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'geofence_errors',
                'Geofence Errors',
                channelDescription: 'Critical geofence system errors',
                importance: Importance.max,
                priority: Priority.max,
                playSound: true,
              ),
            ),
          );
        } catch (notifError) {
          developer.log(
            '[GeofenceCallback] Failed to show database error notification: $notifError',
          );
        }
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
      // Show fallback notification before failing
      try {
        await plugin.show(
          999996,
          '⚠️ Critical Database Error',
          'Geofence system failed: ${e.toString()}. Geofences: ${params.geofences.map((g) => g.id).join(", ")}',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'geofence_errors',
              'Geofence Errors',
              channelDescription: 'Critical geofence system errors',
              importance: Importance.max,
              priority: Priority.max,
              playSound: true,
            ),
          ),
        );
      } catch (notifError) {
        developer.log(
          '[GeofenceCallback] Failed to show critical error notification: $notifError',
        );
      }
      rethrow;
    }
    developer.log(
      '[GeofenceCallback] Starting geofence callback for event: ${params.event.name}',
    );
    developer.log(
      '[GeofenceCallback] Event: ${params.event}, Geofence IDs: ${params.geofences.map((g) => g.id).toList()}, Location available: ${params.location != null}',
    );

    developer.log(
      '[GeofenceCallback] Using background DB connection. Path: ${database.path}',
    );

    // Get geofence details from storage, using the existing database connection
    final storage = GeofenceStorage(db: database);

    final List<String> incomingGeofenceIds =
        params.geofences.map((g) => g.id).toList();
    final Map<String, _GeofenceTaskBucket> geofenceTaskBuckets = {};
    List<int> matchedTaskIds = [];

    if (incomingGeofenceIds.isNotEmpty) {
      final placeholders = List.filled(
        incomingGeofenceIds.length,
        '?',
      ).join(',');
      final rows = await database.query(
        'tasks',
        columns: ['id', 'geofence_id', 'taskPriority'],
        where: 'geofence_id IN ($placeholders) AND isCompleted = 0',
        whereArgs: incomingGeofenceIds,
      );
      developer.log(
        '[GeofenceCallback] Background DB returned ${rows.length} matching task rows: $rows',
      );
      for (final row in rows) {
        final dynamic gidRaw = row['geofence_id'];
        if (gidRaw == null) continue;
        final String? gid = gidRaw as String?;
        if (gid == null) continue;

        final bucket = geofenceTaskBuckets.putIfAbsent(
          gid,
          () => _GeofenceTaskBucket(),
        );

        final dynamic idVal = row['id'];
        final int? parsedId =
            idVal is int ? idVal : int.tryParse(idVal?.toString() ?? '');
        if (parsedId != null) {
          bucket.taskIds.add(parsedId);
        }

        final dynamic priorityVal = row['taskPriority'];
        final double? parsedPriority =
            priorityVal is int
                ? priorityVal.toDouble()
                : double.tryParse(priorityVal?.toString() ?? '');
        if (parsedPriority != null && parsedPriority > bucket.highestPriority) {
          bucket.highestPriority = parsedPriority;
        }
      }
    }

    final List<_GeofenceEventDetail> geofenceDetails = [];
    for (final geofence in params.geofences) {
      final GeofenceData? geofenceData = await storage.getGeofenceById(
        geofence.id,
      );
      double? distance;
      if (geofenceData != null && params.location != null) {
        distance = _calculateDistance(
          params.location!.latitude,
          params.location!.longitude,
          geofenceData.latitude,
          geofenceData.longitude,
        );
        developer.log(
          '[GeofenceCallback] Geofence ${geofence.id} triggered at distance: ${distance.toStringAsFixed(1)}m, configured radius: ${geofenceData.radiusMeters}m',
        );
      }

      geofenceDetails.add(
        _GeofenceEventDetail(
          geofence: geofence,
          data: geofenceData,
          radiusMeters: geofenceData?.radiusMeters ?? geofence.radiusMeters,
          distanceFromCenter: distance,
          taskIds: List<int>.from(
            geofenceTaskBuckets[geofence.id]?.taskIds ?? const [],
          ),
          highestPriority:
              geofenceTaskBuckets[geofence.id]?.highestPriority ?? 0,
        ),
      );
    }

    if (geofenceDetails.isEmpty) {
      developer.log(
        '[GeofenceCallback] No geofence details resolved; aborting processing.',
      );
      return;
    }

    final _GeofenceEventDetail primaryDetail = _selectPrimaryDetail(
      geofenceDetails,
    );
    final List<_GeofenceEventDetail> processedDetails = [primaryDetail];

    if (primaryDetail.taskIds.isNotEmpty &&
        _shouldSuppressDueToRecent(primaryDetail, params.location)) {
      developer.log(
        '[GeofenceCallback] Suppressing geofence ${primaryDetail.id} because a higher or equal trigger was handled recently.',
      );
      return;
    }

    final List<String> selectedGeofenceIds =
        processedDetails.map((detail) => detail.id).toList();
    matchedTaskIds = List<int>.from(primaryDetail.taskIds);

    if (primaryDetail.taskIds.isNotEmpty) {
      _lastGeofenceTrigger = _RecentGeofenceTrigger(
        geofenceId: primaryDetail.id,
        timestamp: DateTime.now(),
        triggerLatitude: params.location?.latitude,
        triggerLongitude: params.location?.longitude,
        radiusMeters: primaryDetail.radiusMeters,
        distanceFromCenter:
            primaryDetail.distanceFromCenter ?? primaryDetail.radiusMeters,
        highestPriority: primaryDetail.highestPriority,
      );
    }

    // First, try to send the filtered event through the port.
    final SendPort? sendPort = IsolateNameServer.lookupPortByName(
      'native_geofence_send_port',
    );
    final int earlyNotificationId = Random().nextInt(2147483647);
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
      try {
        sendPort.send({
          'event': params.event.name,
          'geofenceIds': selectedGeofenceIds,
          'location': {
            'latitude': params.location!.latitude,
            'longitude': params.location!.longitude,
          },
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'notificationId': earlyNotificationId,
          'ackPortName': ackPortName,
          'taskIds': matchedTaskIds,
        });
        developer.log(
          '[GeofenceCallback] Successfully sent event through port with notificationId=$earlyNotificationId and ackPortName=$ackPortName',
        );
      } catch (portError) {
        developer.log(
          '[GeofenceCallback] CRITICAL: Failed to send event through port: $portError',
        );
      }
    } else {
      developer.log(
        '[GeofenceCallback] WARNING: SendPort is ${sendPort == null ? "null" : "available"}, '
        'location is ${params.location == null ? "null" : "available"}. '
        'UI isolate may not receive geofence event.',
      );
    }

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

    // Create error notification channel
    const AndroidNotificationChannel errorsChannel = AndroidNotificationChannel(
      'geofence_errors',
      'Geofence Errors',
      description: 'Critical geofence system errors and diagnostics',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await androidPlugin?.createNotificationChannel(errorsChannel);

    // Removed progress and debug channels

    developer.log(
      '[GeofenceCallback] Created/ensured all notification channels',
    );

    // Removed debug verification notifications

    String notificationTitle = 'Task reminder';
    String notificationBody = '';

    for (final detail in processedDetails) {
      final geofenceData =
          detail.data ?? await storage.getGeofenceById(detail.id);
      if (geofenceData != null) {
        notificationBody +=
            'You have a task for this geofence: ${geofenceData.task}\n';
      }
    }

    if (notificationBody.isEmpty) {
      notificationBody =
          'Event: ${params.event.name} for geofences: ${selectedGeofenceIds.join(", ")}';
    }

    // Create the notification details with immediate display settings
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
      ongoing: false, // Changed from true - ongoing can be delayed
      icon: '@mipmap/ic_launcher',
      styleInformation: const BigTextStyleInformation(''),
      fullScreenIntent: false, // Disabled - can cause delays on newer Android
      channelShowBadge: true,
      enableLights: true,
      ledColor: const Color.fromARGB(255, 255, 200, 0),
      ledOnMs: 1000,
      ledOffMs: 500,
      // Immediate display flags
      timeoutAfter: null, // No timeout
      when: DateTime.now().millisecondsSinceEpoch,
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

    // --- Show the notification IMMEDIATELY with simplified logic ---
    // Use the earlyNotificationId so the UI isolate can correlate and cancel it.
    final notificationId = earlyNotificationId;

    // Create simple payload for immediate notification
    final immediatePayloadData = {
      'notificationId': notificationId,
      'title': notificationTitle,
      'body': notificationBody,
      'geofenceIds': selectedGeofenceIds,
      'taskIds': matchedTaskIds,
    };
    final immediatePayloadJson = jsonEncode(immediatePayloadData);

    // Wait for UI isolate acknowledgment before showing background notification
    // The ack port was already registered earlier (receiveForAck with ackPortName)
    bool shouldShowBackgroundNotification = true;

    try {
      developer.log(
        '[GeofenceCallback] Waiting for UI acknowledgment on port: $ackPortName',
      );

      // Wait up to 800ms for UI acknowledgment on the already-registered port
      final ackFuture = receiveForAck.first.timeout(
        const Duration(milliseconds: 800),
        onTimeout: () {
          developer.log(
            '[GeofenceCallback] Ack timeout - UI isolate may be unavailable, showing background notification',
          );
          return {'status': 'timeout'};
        },
      );

      final ackResponse = await ackFuture;
      developer.log('[GeofenceCallback] Received ack response: $ackResponse');

      // Check if UI isolate suppressed the notification
      if (ackResponse is Map && ackResponse['status'] == 'suppressed') {
        shouldShowBackgroundNotification = false;
        developer.log(
          '[GeofenceCallback] UI isolate will handle notification, suppressing background notification',
        );
      }
    } catch (e, st) {
      developer.log(
        '[GeofenceCallback] Error in ack-wait logic: $e, will show background notification',
        error: e,
        stackTrace: st,
      );
    } finally {
      // Clean up ack port
      try {
        IsolateNameServer.removePortNameMapping(ackPortName);
        receiveForAck.close();
      } catch (e) {
        developer.log('[GeofenceCallback] Error cleaning up ack port: $e');
      }
    }

    // Show notification only if UI didn't suppress it
    if (shouldShowBackgroundNotification) {
      try {
        developer.log(
          '[GeofenceCallback] Showing background notification (id=$notificationId)',
        );

        await plugin.show(
          notificationId,
          notificationTitle,
          notificationBody,
          platformChannelSpecifics,
          payload: immediatePayloadJson,
        );

        developer.log(
          '[GeofenceCallback] Background notification shown successfully',
        );
      } catch (e, st) {
        developer.log(
          '[GeofenceCallback] Error showing background notification: $e',
          error: e,
          stackTrace: st,
        );
      }
    } else {
      developer.log(
        '[GeofenceCallback] Skipping background notification (UI handling)',
      );
    }

    // Provide diagnostics if we failed to resolve tasks for the selected geofence
    try {
      developer.log(
        '[GeofenceCallback] Background query geofenceIdList: $selectedGeofenceIds',
      );
      if (matchedTaskIds.isEmpty && selectedGeofenceIds.isNotEmpty) {
        developer.log(
          '[GeofenceCallback] WARNING: No matching tasks found for geofences: $selectedGeofenceIds',
        );
        final placeholders = List.filled(
          selectedGeofenceIds.length,
          '?',
        ).join(',');
        final allTasksRows = await database.query(
          'tasks',
          columns: ['id', 'geofence_id', 'isCompleted'],
          where: 'geofence_id IN ($placeholders)',
          whereArgs: selectedGeofenceIds,
        );
        if (allTasksRows.isNotEmpty &&
            allTasksRows.every((r) => r['isCompleted'] == 1)) {
          developer.log(
            '[GeofenceCallback] GUARD: All tasks for these geofences are completed. Skipping notification and cleaning up orphaned geofences.',
          );
          try {
            for (final gid in selectedGeofenceIds) {
              await database.delete(
                'geofences',
                where: 'id = ?',
                whereArgs: [gid],
              );
              developer.log(
                '[GeofenceCallback] Cleaned up orphaned geofence: $gid',
              );
            }
          } catch (cleanupError) {
            developer.log(
              '[GeofenceCallback] Error cleaning up orphaned geofences: $cleanupError',
            );
          }
          return;
        }
        try {
          final allRows = await database.query(
            'tasks',
            columns: ['id', 'geofence_id', 'taskName', 'isCompleted'],
          );
          developer.log(
            '[GeofenceCallback] No matches - full tasks table snapshot: $allRows',
          );
          await plugin.show(
            999995,
            'ℹ️ No Tasks Found',
            'Entered geofence area but no active tasks are linked to: ${selectedGeofenceIds.join(", ")}',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'geofence_alerts',
                'Geofence Alerts',
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
              ),
            ),
          );
        } catch (dumpError, dumpSt) {
          developer.log(
            '[GeofenceCallback] Failed to dump all tasks for debugging: $dumpError',
            error: dumpError,
            stackTrace: dumpSt,
          );
        }
      }
    } catch (e, st) {
      developer.log(
        '[GeofenceCallback] Error while evaluating geofence task matches: $e',
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
                if (ip != null) {
                  incomingHighest =
                      incomingHighest > ip ? incomingHighest : ip.toDouble();
                }
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
      'geofenceIds': selectedGeofenceIds,
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

    // Simplified: Notification already shown immediately above
    // Skip complex ack logic since we want reliable immediate notifications
    developer.log(
      '[GeofenceCallback] Skipping complex ack logic - notification already shown immediately',
    );

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
      for (final detail in processedDetails) {
        try {
          developer.log(
            '[GeofenceCallback] Processing geofence ${detail.id} for TTS',
          );

          final geofenceData =
              detail.data ?? await storage.getGeofenceById(detail.id);
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
                whereArgs: [detail.id],
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
            // shouldAnnouncePending should ONLY be true if task was explicitly
            // added to pending queue (snoozed), not just because it matched a geofence
            final bool shouldAnnouncePending = wasPersistedPending;

            // Request TTS from UI isolate instead of speaking directly in background
            // Background isolates can't reliably access Android audio on real devices
            try {
              developer.log(
                '[GeofenceCallback] Sending TTS request to UI isolate...',
              );

              final SendPort? sendPort = IsolateNameServer.lookupPortByName(
                'native_geofence_send_port',
              );

              if (sendPort != null) {
                final speakText =
                    shouldAnnouncePending
                        ? '${geofenceData.task} added to pending queue.'
                        : geofenceData.task!;

                // Send TTS request to UI isolate
                sendPort.send({
                  'type': 'tts_request',
                  'text': speakText,
                  'context': wasPersistedPending ? 'snooze' : 'location',
                });

                developer.log(
                  '[GeofenceCallback] TTS request sent to UI isolate for: ${geofenceData.task}',
                );

                // Small delay to allow TTS to start in UI isolate
                await Future.delayed(const Duration(milliseconds: 500));
              } else {
                developer.log(
                  '[GeofenceCallback] UI isolate port not found, skipping TTS',
                );
              }
            } catch (ttsPortError) {
              developer.log(
                '[GeofenceCallback] Failed to send TTS request to UI isolate: $ttsPortError',
              );
            }
          } else {
            developer.log(
              '[GeofenceCallback] No task found for geofence ${detail.id} or task is empty',
            );
          }
        } catch (geofenceError) {
          developer.log(
            '[GeofenceCallback] Error processing geofence ${detail.id} for TTS: $geofenceError',
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

        // Close the old connection first
        if (database.isOpen && database != currentDb) {
          try {
            await database.close();
            developer.log('[GeofenceCallback] Closed old database connection');
          } catch (closeError) {
            developer.log(
              '[GeofenceCallback] Error closing old connection: $closeError',
            );
          }
        }

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
        database =
            newDb; // Update the outer variable so finally block closes the right connection
      }

      // Log database path for debugging
      developer.log('[GeofenceCallback] Database path: ${currentDb.path}');

      // Process each geofence
      for (final detail in processedDetails) {
        try {
          // Ensure we're still connected
          if (!currentDb.isOpen) {
            throw Exception('Database connection lost');
          }

          final geofenceData =
              detail.data ?? await storage.getGeofenceById(detail.id);

          // Create the notification record with explicit timestamp
          final now = DateTime.now();
          final recordMap = {
            'notification_id': notificationId,
            'geofence_id': detail.id,
            'task_name': geofenceData?.task,
            'event_type': params.event.name,
            'body': notificationBody,
            'timestamp':
                now.millisecondsSinceEpoch ~/ 1000, // Convert to seconds
          };

          // Use DatabaseService to insert the record
          await dbService.insertNotificationHistory(currentDb, recordMap);

          developer.log(
            '[GeofenceCallback] Successfully saved record for geofence ID: ${detail.id}',
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
            '[GeofenceCallback] Error saving record for geofence ${detail.id}: $e',
            error: e,
            stackTrace: stackTrace,
          );

          // Try one more time with a fresh connection
          try {
            developer.log(
              '[GeofenceCallback] Retrying with fresh database connection...',
            );

            // Close the old connection if it's different from the database variable
            if (currentDb != database && currentDb.isOpen) {
              try {
                await currentDb.close();
                developer.log(
                  '[GeofenceCallback] Closed previous database connection before retry',
                );
              } catch (closeError) {
                developer.log(
                  '[GeofenceCallback] Error closing old connection: $closeError',
                );
              }
            }

            // Ensure the retry connection is writable
            final retryDb = await dbService.openNewBackgroundConnection(
              readOnly: false,
            );
            if (retryDb.isOpen) {
              final geofenceData =
                  detail.data ?? await storage.getGeofenceById(detail.id);
              final now = DateTime.now();
              final recordMap = {
                'notification_id': notificationId,
                'geofence_id': detail.id,
                'task_name': geofenceData?.task,
                'event_type': params.event.name,
                'body': notificationBody,
                'timestamp':
                    now.millisecondsSinceEpoch ~/ 1000, // Convert to seconds
              };

              await dbService.insertNotificationHistory(retryDb, recordMap);

              // Update current DB reference and the outer database variable
              currentDb = retryDb;
              database = retryDb;

              developer.log(
                '[GeofenceCallback] Successfully saved record on retry for geofence ID: ${detail.id}',
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
              '[GeofenceCallback] Failed to save record on retry for geofence ID: ${detail.id}: $retryError',
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
        '[GeofenceCallback] Finished processing ${processedDetails.length} geofence(s) for notification history.',
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
