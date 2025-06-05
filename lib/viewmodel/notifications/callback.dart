import 'dart:isolate';
import 'dart:math';
import 'dart:ui';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:intelliboro/main.dart';

import 'package:native_geofence/native_geofence.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

@pragma('vm:entry-point')
Future<void> geofenceTriggered(GeofenceCallbackParams params) async {
  developer.log(
    '[GeofenceCallback] Event: ${params.event}, Geofence IDs: ${params.geofences.map((g) => g.id).toList()}, Location: ${params.location}',
  );

  final SendPort? sendPort = IsolateNameServer.lookupPortByName(
    'native_geofence_send_port',
  );
  sendPort?.send("Callback received for event: ${params.event.name}");

  Database? dbForIsolate;
  try {
    String geofenceId =
        params.geofences.isNotEmpty ? params.geofences.first.id : "unknown_id";
    String taskName = "Task details not found";
    String notificationTitle = 'Geofence ${capitalize(params.event.name)}';
    String notificationBody =
        'Geofence ID: $geofenceId. Event: ${params.event.name}.';

    if (params.geofences.isNotEmpty) {
      final firstGeofenceId = params.geofences.first.id;

      try {
        // 1. Get a new database connection for this isolate
        final databaseService = DatabaseService();
        // Open read-only; background task should not write typically
        dbForIsolate = await databaseService.openNewBackgroundConnection(
          readOnly: true,
        );
        developer.log(
          "[GeofenceCallback] Opened new DB connection for isolate.",
        );

        // 2. Instantiate GeofenceStorage with this connection
        // (No longer needed, we pass the db directly to getGeofenceById)
        // final GeofenceStorage geofenceStorage = GeofenceStorage(db: dbForIsolate);

        // 3. Fetch geofence data using the specific connection
        final GeofenceStorage geofenceStorage =
            GeofenceStorage(); // Instantiate without db for now
        final GeofenceData? geofenceData = await geofenceStorage
            .getGeofenceById(
              firstGeofenceId,
              providedDb: dbForIsolate,
            ); // Pass the isolate-specific DB

        if (geofenceData != null &&
            geofenceData.task != null &&
            geofenceData.task!.isNotEmpty) {
          taskName = geofenceData.task!;
          notificationBody =
              'Task: $taskName at ${geofenceData.latitude.toStringAsFixed(3)},${geofenceData.longitude.toStringAsFixed(3)}';
          notificationTitle =
              '$taskName - Geofence ${capitalize(params.event.name)}';
          developer.log(
            '[GeofenceCallback] Task found: $taskName for ID: $firstGeofenceId',
          );
        } else {
          notificationBody = 'No task assigned to geofence $firstGeofenceId.';
          developer.log(
            '[GeofenceCallback] GeofenceData (isNull: ${geofenceData == null}) or task (isNullOrEmpty: ${geofenceData?.task == null || geofenceData!.task!.isEmpty}) not found for ID: $firstGeofenceId',
          );
        }
      } catch (e, s) {
        developer.log('[GeofenceCallback] Error fetching GeofenceData: $e\n$s');
        notificationBody =
            'Could not retrieve task for geofence $firstGeofenceId.';
      }
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'geofence_task_channel',
          'Geofence Tasks',
          channelDescription: 'Notifications for geofence-triggered tasks',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          styleInformation: BigTextStyleInformation(''),
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      Random().nextInt(100000),
      notificationTitle,
      notificationBody,
      platformChannelSpecifics,
      payload: 'geofence_id=$geofenceId&task_name=$taskName',
    );
    developer.log(
      '[GeofenceCallback] Notification show() called using global plugin. Title=$notificationTitle, Body=$notificationBody',
    );
  } catch (e, s) {
    developer.log(
      '[GeofenceCallback] Failed to send notification: $e',
      stackTrace: s,
    );
  } finally {
    // Ensure the database connection opened by this isolate is closed.
    if (dbForIsolate != null && dbForIsolate!.isOpen) {
      await dbForIsolate!.close();
      developer.log(
        "[GeofenceCallback] Closed isolate-specific DB connection.",
      );
    }
  }
}

String capitalize(String text) {
  if (text.isEmpty) return text;
  return text[0].toUpperCase() + text.substring(1);
}
