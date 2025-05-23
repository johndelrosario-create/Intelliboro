import 'package:flutter/foundation.dart' show debugPrint; // For debug prints
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
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
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint("[LocationService] Location services are disabled.");
      // It might be helpful to prompt the user to enable location services
      // For example: await Geolocator.openLocationSettings();
      // However, let's keep it simple and return an error for now.
      return Future.error(
        'Location services are disabled. Please enable them in your device settings.',
      );
    }

    bool permissionGranted = await requestLocationPermission();
    if (!permissionGranted) {
      debugPrint("[LocationService] Location permission not granted.");
      return Future.error(
        'Location permissions are required. Please grant permission and try again.',
      );
    }

    debugPrint(
      "[LocationService] Permissions granted, attempting to get current position.",
    );
    try {
      return await Geolocator.getCurrentPosition(
        // Consider desiredAccuracy instead of locationSettings for simplicity if only accuracy is needed.
        // locationSettings: LocationSettings(accuracy: LocationAccuracy.medium),
        desiredAccuracy: LocationAccuracy.medium,
      );
    } catch (e) {
      debugPrint("[LocationService] Error getting location: $e");
      return Future.error('Failed to get current location: ${e.toString()}');
    }
  }
}
