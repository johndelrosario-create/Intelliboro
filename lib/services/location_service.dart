import 'package:flutter/foundation.dart' show debugPrint; // For debug prints
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class LocationService {
  static const String _lastLocationLatKey = 'last_location_latitude';
  static const String _lastLocationLngKey = 'last_location_longitude';
  static const String _lastLocationTimestampKey = 'last_location_timestamp';
  static const String _homeRegionCenterLatKey = 'home_region_center_lat';
  static const String _homeRegionCenterLngKey = 'home_region_center_lng';
  static const String _homeRegionRadiusKey = 'home_region_radius';

  // Cache location for up to 24 hours when offline
  static const Duration _locationCacheExpiry = Duration(hours: 24);

  // Real-time location streaming
  StreamSubscription<Position>? _positionStreamSubscription;
  final StreamController<Position> _locationStreamController =
      StreamController<Position>.broadcast();
  Stream<Position> get locationStream => _locationStreamController.stream;

  // Singleton pattern
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();
  Future<bool> requestLocationPermission() async {
    final locationPerm = await Permission.location.request();
    debugPrint("[LocationService] Initial permission status: $locationPerm");

    if (locationPerm.isDenied) {
      debugPrint("[LocationService] Permission denied, requesting...");
      await Permission.location.request();
      debugPrint(
        "[LocationService] Permission status after request: $locationPerm",
      );
    } else if (locationPerm.isPermanentlyDenied) {
      debugPrint(
        "[LocationService] Permission permanently denied. Opening app settings.",
      );
      openAppSettings();
      return false;
    }

    debugPrint("[LocationService] Final permission status: $locationPerm");
    final backgroundLocationPerm = await Permission.locationAlways.request();
    debugPrint(
      "[LocationService] Background location permission status: $backgroundLocationPerm",
    );

    if (backgroundLocationPerm.isDenied) {
      debugPrint("[LocationService] Background location permission denied.");
      return false;
    } else if (backgroundLocationPerm.isPermanentlyDenied) {
      debugPrint(
        "[LocationService] Background location permission permanently denied. Opening app settings.",
      );
      openAppSettings();
      return false;
    }

    return true;
  }

  Future<Position> getCurrentLocation() async {
    debugPrint("[LocationService] Starting location request...");

    // First try to get fresh location if we have connectivity and permissions
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasConnectivity =
          !connectivityResult.contains(ConnectivityResult.none);

      debugPrint("[LocationService] Connectivity status: $connectivityResult");

      if (hasConnectivity) {
        // Try to get fresh location when online
        final freshLocation = await _getFreshLocation();
        if (freshLocation != null) {
          debugPrint("[LocationService] Got fresh location, caching it");
          await _cacheLocation(freshLocation);
          return freshLocation;
        }
      }
    } catch (e) {
      debugPrint("[LocationService] Error getting fresh location: $e");
    }

    // Fallback to cached location if fresh location failed or we're offline
    debugPrint("[LocationService] Attempting to use cached location");
    final cachedLocation = await _getCachedLocation();
    if (cachedLocation != null) {
      debugPrint(
        "[LocationService] Using cached location from ${DateTime.fromMillisecondsSinceEpoch(cachedLocation['timestamp'])}",
      );
      return Position(
        latitude: cachedLocation['latitude'],
        longitude: cachedLocation['longitude'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          cachedLocation['timestamp'],
        ),
        accuracy: 100.0, // Assume less accuracy for cached location
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );
    }

    // If no cached location, try one more time to get fresh location regardless of connectivity
    debugPrint(
      "[LocationService] No cached location available, making final attempt for fresh location",
    );
    final finalAttemptLocation = await _getFreshLocation();
    if (finalAttemptLocation != null) {
      await _cacheLocation(finalAttemptLocation);
      return finalAttemptLocation;
    }

    // Complete failure
    debugPrint("[LocationService] All location attempts failed");
    return Future.error(
      'Unable to get current location. Please ensure location services are enabled and try again.',
    );
  }

  /// Attempts to get a fresh location from GPS/network
  Future<Position?> _getFreshLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("[LocationService] Location services are disabled.");
        return null;
      }

      bool permissionGranted = await requestLocationPermission();
      if (!permissionGranted) {
        debugPrint("[LocationService] Location permission not granted.");
        return null;
      }

      debugPrint(
        "[LocationService] Permissions granted, attempting to get current position.",
      );

      // Try last known position first (instant, no GPS wait)
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          debugPrint("[LocationService] Got last known position (instant)");
          return lastKnown;
        }
      } catch (e) {
        debugPrint("[LocationService] No last known position: $e");
      }

      // Fall back to fresh GPS location with timeout
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5), // Reduced from 10s to prevent ANR
        ),
      );
    } catch (e) {
      debugPrint("[LocationService] Error getting fresh location: $e");
      return null;
    }
  }

  /// Caches the current location to SharedPreferences
  Future<void> _cacheLocation(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_lastLocationLatKey, position.latitude);
      await prefs.setDouble(_lastLocationLngKey, position.longitude);
      await prefs.setInt(
        _lastLocationTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      debugPrint("[LocationService] Location cached successfully");
    } catch (e) {
      debugPrint("[LocationService] Error caching location: $e");
    }
  }

  /// Retrieves cached location from SharedPreferences if it's not expired
  Future<Map<String, dynamic>?> _getCachedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final latitude = prefs.getDouble(_lastLocationLatKey);
      final longitude = prefs.getDouble(_lastLocationLngKey);
      final timestamp = prefs.getInt(_lastLocationTimestampKey);

      if (latitude == null || longitude == null || timestamp == null) {
        debugPrint("[LocationService] No cached location found");
        return null;
      }

      final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (cacheAge > _locationCacheExpiry.inMilliseconds) {
        debugPrint(
          "[LocationService] Cached location expired (age: ${Duration(milliseconds: cacheAge).inHours} hours)",
        );
        return null;
      }

      return {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp,
      };
    } catch (e) {
      debugPrint("[LocationService] Error retrieving cached location: $e");
      return null;
    }
  }

  /// Gets the last known location, prioritizing cached data for offline scenarios
  /// This is specifically useful for map flyTo functionality when offline
  Future<Position?> getLastKnownLocation() async {
    debugPrint("[LocationService] Getting last known location for offline use");

    // First try cached location (faster and works offline)
    final cachedLocation = await _getCachedLocation();
    if (cachedLocation != null) {
      debugPrint("[LocationService] Returning cached location for offline use");
      return Position(
        latitude: cachedLocation['latitude'],
        longitude: cachedLocation['longitude'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          cachedLocation['timestamp'],
        ),
        accuracy: 100.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );
    }

    // If no cache, try Geolocator's last known position (may work offline in some cases)
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        debugPrint("[LocationService] Got last known position from Geolocator");
        // Cache this for future offline use
        await _cacheLocation(lastKnown);
        return lastKnown;
      }
    } catch (e) {
      debugPrint("[LocationService] Error getting last known position: $e");
    }

    return null;
  }

  /// Start real-time location tracking with offline support
  /// This works even when offline within the cached hometown region
  Future<void> startLocationTracking() async {
    if (_positionStreamSubscription != null) {
      debugPrint("[LocationService] Location tracking already active");
      return;
    }

    try {
      // Check permissions first
      bool permissionGranted = await requestLocationPermission();
      if (!permissionGranted) {
        debugPrint(
          "[LocationService] Cannot start tracking: permission denied",
        );
        return;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint(
          "[LocationService] Cannot start tracking: location services disabled",
        );
        return;
      }

      debugPrint("[LocationService] Starting real-time location tracking...");

      // Configure location settings for real-time tracking
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Only update when user moves 10 meters
      );

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          debugPrint("[LocationService] New location received and cached");

          // Cache the new location for offline use
          _cacheLocation(position);

          // Check if we're within the hometown cached region
          _checkIfWithinHometown(position);

          // Emit to location stream for listeners
          _locationStreamController.add(position);
        },
        onError: (error) {
          debugPrint("[LocationService] Location stream error: $error");
          // On error, try to emit last known location if available
          _emitLastKnownLocationOnError();
        },
      );

      debugPrint("[LocationService] Real-time location tracking started");
    } catch (e) {
      debugPrint("[LocationService] Error starting location tracking: $e");
    }
  }

  /// Stop real-time location tracking
  Future<void> stopLocationTracking() async {
    try {
      if (_positionStreamSubscription != null) {
        await _positionStreamSubscription!.cancel();
        _positionStreamSubscription = null;
        debugPrint("[LocationService] Location tracking stopped");
      }
    } catch (e) {
      debugPrint("[LocationService] Error stopping location tracking: $e");
      // Ensure the subscription is nulled even if cancel fails
      _positionStreamSubscription = null;
    }
  }

  /// Check if current position is within the cached hometown region
  Future<void> _checkIfWithinHometown(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final centerLat = prefs.getDouble(_homeRegionCenterLatKey);
      final centerLng = prefs.getDouble(_homeRegionCenterLngKey);
      final radius = prefs.getDouble(_homeRegionRadiusKey);

      if (centerLat != null && centerLng != null && radius != null) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          centerLat,
          centerLng,
        );

        final isWithinHometown = distance <= radius;
        debugPrint(
          "[LocationService] Within hometown region: $isWithinHometown (${distance.toStringAsFixed(0)}m from center)",
        );

        if (!isWithinHometown) {
          debugPrint(
            "[LocationService] User moved outside hometown region - may need fresh map data",
          );
        }
      }
    } catch (e) {
      debugPrint("[LocationService] Error checking hometown region: $e");
    }
  }

  /// Cache the hometown region information when offline map is downloaded
  Future<void> cacheHometownRegion(
    double centerLat,
    double centerLng,
    double radiusMeters,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_homeRegionCenterLatKey, centerLat);
      await prefs.setDouble(_homeRegionCenterLngKey, centerLng);
      await prefs.setDouble(_homeRegionRadiusKey, radiusMeters);
      debugPrint(
        "[LocationService] Hometown region cached with radius: ${radiusMeters}m",
      );
    } catch (e) {
      debugPrint("[LocationService] Error caching hometown region: $e");
    }
  }

  /// Emit last known location when real-time tracking fails
  Future<void> _emitLastKnownLocationOnError() async {
    try {
      final lastKnown = await getLastKnownLocation();
      if (lastKnown != null) {
        debugPrint(
          "[LocationService] Emitting cached location due to tracking error",
        );
        _locationStreamController.add(lastKnown);
      }
    } catch (e) {
      debugPrint("[LocationService] Error emitting cached location: $e");
    }
  }

  /// Check if location services are available for real-time tracking
  Future<bool> isRealTimeTrackingAvailable() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permissionGranted = await requestLocationPermission();
      return serviceEnabled && permissionGranted;
    } catch (e) {
      debugPrint("[LocationService] Error checking tracking availability: $e");
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    try {
      // Cancel subscription immediately without awaiting
      if (_positionStreamSubscription != null) {
        _positionStreamSubscription!.cancel();
        _positionStreamSubscription = null;
      }

      // Close the stream controller
      if (!_locationStreamController.isClosed) {
        _locationStreamController.close();
      }

      debugPrint("[LocationService] Disposed successfully");
    } catch (e) {
      debugPrint("[LocationService] Error during disposal: $e");
      // Ensure cleanup even if errors occur
      _positionStreamSubscription = null;
    }
  }
}
