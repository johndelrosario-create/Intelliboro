import 'dart:isolate';
import 'dart:math';
import 'dart:ui';
import 'dart:developer' as developer;
import 'dart:typed_data' show Int64List;

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
  Database? db;
  try {
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
    // Open a new, dedicated database connection for this background task.
    // This prevents conflicts with the main isolate's database connection.
    db = await DatabaseService().openNewBackgroundConnection();
    developer.log(
      '[GeofenceCallback] Opened new background DB connection. Path: ${db.path}',
    );

    // Get geofence details from storage, passing the dedicated connection.
    final storage = GeofenceStorage(db: db);
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
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'geofence_alerts',
      'Geofence Alerts',
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

    String notificationTitle = 'Location Alert';
    String notificationBody = '';

    for (final geofence in params.geofences) {
      final geofenceData = await storage.getGeofenceById(geofence.id);
      if (geofenceData != null) {
        final eventType =
            params.event == GeofenceEvent.enter ? 'entered' : 'exited';
        notificationBody += 'You have $eventType ${geofenceData.task}\\n';
      }
    }

    if (notificationBody.isEmpty) {
      notificationBody =
          'Event: ${params.event.name} for geofences: ${params.geofences.map((g) => g.id).join(", ")}';
    }

    // Create the notification details with high priority
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        const AndroidNotificationDetails(
          'geofence_alerts',
          'Geofence Alerts',
          channelDescription: 'Important alerts for location-based events',
          importance: Importance.max,
          priority: Priority.max,
          showWhen: true,
          enableVibration: true,
          playSound: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          autoCancel: true,
          fullScreenIntent: true,
          ticker: 'New location alert',
        );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    // Show the notification with a unique ID based on timestamp
    final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(
      100000,
    );

    // Add a small delay to ensure the notification is shown after the geofence event
    await Future.delayed(const Duration(milliseconds: 500));

    await plugin.show(
      notificationId,
      notificationTitle,
      notificationBody,
      platformChannelSpecifics,
      payload: 'geofence_${params.geofences.map((g) => g.id).join("_")}',
    );

    developer.log(
      '[GeofenceCallback] Successfully showed notification: ID=$notificationId, Title=$notificationTitle, Body=$notificationBody',
    );
  } catch (e, stackTrace) {
    developer.log(
      '[GeofenceCallback] Error in geofence callback: $e\n$stackTrace',
    );
  } finally {
    // IMPORTANT: Always close the background database connection to prevent leaks.
    if (db != null && db.isOpen) {
      await db.close();
      developer.log(
        '[GeofenceCallback] Closed background database connection.',
      );
    }
  }
}

String capitalize(String s) =>
    s[0].toUpperCase() + s.substring(1).toLowerCase();
