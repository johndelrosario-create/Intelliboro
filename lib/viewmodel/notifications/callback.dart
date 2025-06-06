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
    'geofence_send_port',
  );
  if (sendPort != null) {
    sendPort.send("Callback received for event: ${params.event.name}");
    developer.log('[GeofenceCallback] Sent message to sendPort.');
  } else {
    developer.log(
      '[GeofenceCallback] Could not find sendPort "geofence_send_port".',
    );
  }

  Database? dbForIsolate;
  // Variables to hold notification content
  late String notificationTitle;
  late String notificationBody;
  String geofenceIdForPayload = "unknown_id";
  String? taskNameForPayload;

  try {
    String geofenceId =
        params.geofences.isNotEmpty ? params.geofences.first.id : "unknown_id";
    geofenceIdForPayload = geofenceId; // For payload
    String eventName = capitalize(params.event.name);
    String? fetchedTaskName;
    String? geofenceLocationString;

    if (params.geofences.isNotEmpty) {
      final firstGeofenceId = params.geofences.first.id;

      try {
        final databaseService = DatabaseService();
        dbForIsolate = await databaseService.openNewBackgroundConnection(
          readOnly: true,
        );
        developer.log(
          "[GeofenceCallback] Opened new DB connection for isolate.",
        );

        final GeofenceStorage geofenceStorage = GeofenceStorage();
        final GeofenceData? geofenceData = await geofenceStorage
            .getGeofenceById(firstGeofenceId, providedDb: dbForIsolate);

        if (geofenceData != null) {
          geofenceLocationString =
              "at ${geofenceData.latitude.toStringAsFixed(3)},${geofenceData.longitude.toStringAsFixed(3)}";
          if (geofenceData.task != null && geofenceData.task!.isNotEmpty) {
            fetchedTaskName = geofenceData.task!;
            taskNameForPayload = fetchedTaskName; // For payload
            developer.log(
              '[GeofenceCallback] Task found: $fetchedTaskName for ID: $firstGeofenceId',
            );
          } else {
            developer.log(
              '[GeofenceCallback] GeofenceData found, but task name is missing or empty for ID: $firstGeofenceId',
            );
          }
        } else {
          developer.log(
            '[GeofenceCallback] GeofenceData not found for ID: $firstGeofenceId',
          );
        }
      } catch (e, s) {
        developer.log(
          '[GeofenceCallback] Error fetching GeofenceData for ID $firstGeofenceId: $e\n$s',
        );
        // fetchedTaskName and geofenceLocationString will remain null
      }
    }

    // Construct Title
    if (fetchedTaskName != null) {
      notificationTitle = "$fetchedTaskName - Geofence $eventName";
    } else {
      notificationTitle = "Geofence $eventName";
    }

    // Construct Body
    List<String> bodyParts = [];
    if (fetchedTaskName != null) {
      bodyParts.add("Task: $fetchedTaskName");
    } else {
      bodyParts.add("No task assigned.");
    }
    if (geofenceLocationString != null) {
      bodyParts.add(geofenceLocationString);
    } else if (params.location != null) {
      bodyParts.add(
        "Triggered near Lat: ${params.location!.latitude.toStringAsFixed(3)}, Lon: ${params.location!.longitude.toStringAsFixed(3)}",
      );
    } else {
      bodyParts.add("Location details unavailable.");
    }
    notificationBody = bodyParts.join(" | ");

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
      Random().nextInt(100000), // Unique ID for each notification
      notificationTitle,
      notificationBody,
      platformChannelSpecifics,
      payload:
          'geofence_id=$geofenceIdForPayload&task_name=${taskNameForPayload ?? "N/A"}',
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
