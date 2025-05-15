import 'package:flutter/material.dart';
import 'package:intelliboro/viewModel/Geofencing/map_viewmodel.dart';
import 'package:intelliboro/viewModel/notifications/callback.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:native_geofence/native_geofence.dart';

class GeofencingService {
  final CircleAnnotationManager? geofenceZonePicker;
  final CircleAnnotationManager? geofenceZoneSymbol;
  final MapboxMapViewModel mapViewModel;

  GeofencingService(this.mapViewModel)
    : geofenceZonePicker = mapViewModel.getGeofenceZonePicker(),
      geofenceZoneSymbol = mapViewModel.getGeofenceZoneSymbol();

  Future<void> createGeofence({
    required Point geometry,
    required double radiusMeters,
    Color fillColor = Colors.amberAccent,
    Color strokeColor = Colors.white,
    double strokeWidth = 2.0,
    double fillOpacity = 0.5,
  }) async {
    try {
      // Get the current zoom level
      var zoomLevel = await mapViewModel.currentZoomLevel();

      // Calculate the radius in pixels based on the zoom level and latitude
      double radiusInPixels = await mapViewModel.metersToPixels(radiusMeters);

      // Debugging: Log the calculated radius
      debugPrint("Radius in meters: $radiusMeters");
      debugPrint("Zoom level: $zoomLevel");
      debugPrint("Calculated radius in pixels: $radiusInPixels");

      // Create the geofence zone with the calculated radius
      geofenceZonePicker?.create(
        CircleAnnotationOptions(
          geometry: geometry,
          circleRadius: radiusInPixels,
          circleColor: fillColor.toARGB32(),
          circleOpacity: fillOpacity,
          circleStrokeColor: strokeColor.toARGB32(),
          circleStrokeWidth: strokeWidth,
        ),
      );

      // Create the geofence for native geofencing
      final geofence = Geofence(
        id: "zone_${geometry.coordinates.lat}_${geometry.coordinates.lng}",
        location: Location(
          latitude: geometry.coordinates.lat.toDouble(),
          longitude: geometry.coordinates.lng.toDouble(),
        ),
        radiusMeters: radiusMeters,
        triggers: {GeofenceEvent.enter, GeofenceEvent.exit},
        iosSettings: IosGeofenceSettings(initialTrigger: true),
        androidSettings: AndroidGeofenceSettings(
          initialTriggers: {GeofenceEvent.enter},
          notificationResponsiveness: const Duration(seconds: 0),
        ),
      );

      NativeGeofenceManager.instance.createGeofence(
        geofence,
        geofenceTriggered,
      );
      debugPrint('Geofence created: ${geofence.id}');
    } catch (e) {
      debugPrint("Error in createGeofence: $e");
    }
  }
}

extension ModifyAndroidGeofenceSettings on AndroidGeofenceSettings {
  AndroidGeofenceSettings copyWith({
    Set<GeofenceEvent> Function()? initialTriggers,
    Duration Function()? expiration,
    Duration Function()? loiteringDelay,
    Duration Function()? notificationResponsiveness,
  }) {
    return AndroidGeofenceSettings(
      initialTriggers: initialTriggers?.call() ?? this.initialTriggers,
      expiration: expiration?.call() ?? this.expiration,
      loiteringDelay: loiteringDelay?.call() ?? this.loiteringDelay,
      notificationResponsiveness:
          notificationResponsiveness?.call() ?? this.notificationResponsiveness,
    );
  }
}
