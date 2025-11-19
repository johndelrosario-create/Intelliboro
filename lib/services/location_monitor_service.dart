import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intelliboro/services/notification_service.dart';
import 'package:geolocator/geolocator.dart';

/// Service to monitor location status and show persistent notification when disabled
class LocationMonitorService {
  static final LocationMonitorService _instance =
      LocationMonitorService._internal();
  factory LocationMonitorService() => _instance;
  LocationMonitorService._internal();

  static const platform = MethodChannel('location_monitor');
  static const int _notificationId = 999999; // Unique ID for location alert
  bool _isMonitoring = false;
  bool _isLocationDisabledNotificationShowing = false;
  Timer? _notificationWatchdog;

  // Stream controller for broadcasting location status changes to UI
  final StreamController<bool> _locationStatusController =
      StreamController<bool>.broadcast();

  /// Stream of location enabled status (true = enabled, false = disabled)
  Stream<bool> get locationStatusStream => _locationStatusController.stream;

  /// Current location status (cached)
  bool _isLocationEnabled = true;
  bool get isLocationEnabled => _isLocationEnabled;

  /// Start monitoring location status changes
  Future<void> startMonitoring() async {
    if (_isMonitoring) {
      developer.log('[LocationMonitorService] Already monitoring');
      return;
    }

    try {
      // Set up method call handler to receive location status updates from native
      platform.setMethodCallHandler(_handleMethodCall);

      if (Platform.isAndroid) {
        // Start native broadcast receiver for location provider changes
        await platform.invokeMethod('startLocationMonitoring');
        developer.log(
          '[LocationMonitorService] Started native location monitoring',
        );
      }

      _isMonitoring = true;

      // Check initial status
      await _checkAndUpdateLocationStatus();
    } catch (e) {
      developer.log('[LocationMonitorService] Error starting monitoring: $e');
    }
  }

  /// Stop monitoring location status changes
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;

    try {
      if (Platform.isAndroid) {
        await platform.invokeMethod('stopLocationMonitoring');
      }

      // Clear any showing notification
      await _clearLocationDisabledNotification();

      _isMonitoring = false;
      developer.log('[LocationMonitorService] Stopped location monitoring');
    } catch (e) {
      developer.log('[LocationMonitorService] Error stopping monitoring: $e');
    }
  }

  /// Handle method calls from native platform
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onLocationStatusChanged':
        final bool isEnabled = call.arguments as bool;
        developer.log(
          '[LocationMonitorService] Location status changed: enabled=$isEnabled',
        );
        await _handleLocationStatusChange(isEnabled);
        break;
      default:
        developer.log(
          '[LocationMonitorService] Unknown method: ${call.method}',
        );
    }
  }

  /// Check current location status and update notification
  Future<void> _checkAndUpdateLocationStatus() async {
    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      await _handleLocationStatusChange(isEnabled);
    } catch (e) {
      developer.log(
        '[LocationMonitorService] Error checking location status: $e',
      );
    }
  }

  /// Handle location status change
  Future<void> _handleLocationStatusChange(bool isEnabled) async {
    // Update cached status and broadcast to UI
    _isLocationEnabled = isEnabled;
    _locationStatusController.add(isEnabled);

    if (isEnabled) {
      // Location is enabled - clear notification
      if (_isLocationDisabledNotificationShowing) {
        await _clearLocationDisabledNotification();
        _stopNotificationWatchdog();
      }
    } else {
      // Location is disabled - show notification
      if (!_isLocationDisabledNotificationShowing) {
        await _showLocationDisabledNotification();
        _startNotificationWatchdog();
      }
    }
  }

  /// Show persistent notification when location is disabled (with sound)
  Future<void> _showLocationDisabledNotification() async {
    await _showLocationDisabledNotificationInternal(playSound: true);
  }

  /// Show persistent notification when location is disabled (silent refresh)
  Future<void> _showLocationDisabledNotificationSilent() async {
    await _showLocationDisabledNotificationInternal(playSound: false);
  }

  /// Internal method to show notification with optional sound
  Future<void> _showLocationDisabledNotificationInternal({
    required bool playSound,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        'location_alerts_v2', // Changed channel ID to force new channel creation
        'Location Alerts',
        channelDescription:
            'Persistent reminder when location services are disabled',
        importance: Importance.max,
        priority: Priority.max,
        ongoing: true, // Cannot be dismissed by swiping
        autoCancel: false,
        onlyAlertOnce: true, // Only play sound/vibrate once, not on updates
        playSound: playSound, // Play sound only on first show
        enableVibration: false, // No vibration
        category: AndroidNotificationCategory.service, // Service category instead of alarm
        visibility: NotificationVisibility.public,
        // Make it stand out but not alarming
        colorized: true,
        color: const Color(0xFFFF9800), // Orange color instead of red
        // Add action button to open settings
        actions: const [
          AndroidNotificationAction(
            'open_location_settings',
            'Enable Location',
            showsUserInterface: true,
            cancelNotification: false, // Don't dismiss notification when tapped
          ),
        ],
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: 'alarm_sound.aiff',
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await notificationPlugin.show(
        _notificationId,
        '⚠️ Location Services Disabled',
        'Location is required for location-based alarms. Tap to enable.',
        details,
        payload: 'location_disabled',
      );

      _isLocationDisabledNotificationShowing = true;
      developer.log(
        '[LocationMonitorService] Showed location disabled notification (sound: $playSound)',
      );
    } catch (e) {
      developer.log('[LocationMonitorService] Error showing notification: $e');
    }
  }

  void _startNotificationWatchdog() {
    // Periodically re-show the notification while location remains disabled.
    // This prevents the user from permanently dismissing the alert by swiping it away.
    _notificationWatchdog?.cancel();
    _notificationWatchdog = Timer.periodic(const Duration(seconds: 3), (
      _,
    ) async {
      try {
        final isEnabled = await Geolocator.isLocationServiceEnabled();
        if (isEnabled) {
          await _clearLocationDisabledNotification();
          _stopNotificationWatchdog();
          return;
        }

        // Re-show the notification (harmless if already visible).
        if (!_isLocationDisabledNotificationShowing) {
          await _showLocationDisabledNotification(); // First time - with sound
        } else {
          // Refresh silently to keep notification persistent without repeating sound
          await _showLocationDisabledNotificationSilent();
        }
      } catch (e) {
        developer.log('[LocationMonitorService] Watchdog error: $e');
      }
    });
  }

  void _stopNotificationWatchdog() {
    _notificationWatchdog?.cancel();
    _notificationWatchdog = null;
  }

  /// Clear the location disabled notification
  Future<void> _clearLocationDisabledNotification() async {
    try {
      await notificationPlugin.cancel(_notificationId);
      _isLocationDisabledNotificationShowing = false;
      developer.log(
        '[LocationMonitorService] Cleared location disabled notification',
      );
    } catch (e) {
      developer.log('[LocationMonitorService] Error clearing notification: $e');
    }
  }

  /// Check if monitoring is active
  bool get isMonitoring => _isMonitoring;
}
