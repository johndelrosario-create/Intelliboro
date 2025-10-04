import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Privacy-safe logging utilities
/// This ensures sensitive location data is never logged in production builds
class PrivacyLogger {
  /// Log a message with optional location data
  /// In production, coordinates are redacted; in debug mode, they're shown
  static void logLocation(
    String message, {
    double? latitude,
    double? longitude,
    String? tag,
  }) {
    final prefix = tag != null ? '[$tag] ' : '';

    if (kDebugMode && latitude != null && longitude != null) {
      // Only show precise coordinates in debug mode
      debugPrint('$prefix$message (lat: $latitude, lng: $longitude)');
    } else if (latitude != null || longitude != null) {
      // In production, just indicate location is available
      debugPrint('$prefix$message (location available)');
    } else {
      // No location data
      debugPrint('$prefix$message');
    }
  }

  /// Log a geofence event without exposing precise coordinates
  static void logGeofenceEvent(
    String eventType,
    String geofenceId, {
    bool hasLocation = false,
    String? tag,
  }) {
    final prefix = tag != null ? '[$tag] ' : '';
    final locationStatus = hasLocation ? 'with location' : 'without location';
    debugPrint(
      '${prefix}Geofence event: $eventType for $geofenceId $locationStatus',
    );
  }

  /// Log position update without coordinates in production
  static void logPositionUpdate(
    String source, {
    double? latitude,
    double? longitude,
    double? accuracy,
    String? tag,
  }) {
    final prefix = tag != null ? '[$tag] ' : '';

    if (kDebugMode && latitude != null && longitude != null) {
      final accuracyStr =
          accuracy != null ? ' (±${accuracy.toStringAsFixed(1)}m)' : '';
      debugPrint('$prefix$source: lat=$latitude, lng=$longitude$accuracyStr');
    } else {
      final accuracyStr =
          accuracy != null
              ? ' with accuracy ±${accuracy.toStringAsFixed(1)}m'
              : '';
      debugPrint('$prefix$source: position updated$accuracyStr');
    }
  }

  /// Log a search/place result without coordinates
  static void logPlaceResult(
    String placeName, {
    double? latitude,
    double? longitude,
    String? tag,
  }) {
    final prefix = tag != null ? '[$tag] ' : '';

    if (kDebugMode && latitude != null && longitude != null) {
      debugPrint('$prefix$placeName at ($latitude, $longitude)');
    } else {
      debugPrint('$prefix$placeName location found');
    }
  }

  /// Generic privacy-safe log that strips location from any string
  static void log(String message, {String? tag}) {
    final prefix = tag != null ? '[$tag] ' : '';

    // In production, redact any number patterns that might be coordinates
    String sanitized = message;
    if (!kDebugMode) {
      // Redact patterns like "lat: 12.345" or "latitude: 12.345"
      sanitized = sanitized.replaceAllMapped(
        RegExp(r'(lat(?:itude)?[:=]\s*)-?\d+\.?\d*', caseSensitive: false),
        (match) => '${match.group(1)}<redacted>',
      );
      // Redact patterns like "lng: 12.345" or "longitude: 12.345"
      sanitized = sanitized.replaceAllMapped(
        RegExp(r'(lng|lon|longitude)[:=]\s*-?\d+\.?\d*', caseSensitive: false),
        (match) => '${match.group(1)}<redacted>',
      );
      // Redact coordinate pairs like (12.345, 67.890)
      sanitized = sanitized.replaceAllMapped(
        RegExp(r'\(-?\d+\.?\d*,\s*-?\d+\.?\d*\)'),
        (match) => '(<redacted>)',
      );
    }

    debugPrint('$prefix$sanitized');
  }

  /// Check if running in debug mode
  static bool get isDebugMode => kDebugMode;

  /// Check if location logging is safe (debug mode only)
  static bool get canLogLocationDetails => kDebugMode;
}
