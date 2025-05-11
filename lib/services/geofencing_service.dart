import 'package:flutter/material.dart';
import 'package:intelliboro/viewModel/Geofencing/map_viewmodel.dart';
import 'package:intelliboro/viewModel/notifications/callback.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:native_geofence/native_geofence.dart';
import 'dart:math';

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
    //var zoomLevel = await mapViewModel.currentZoomLevel();
    final double radiusInPixels = metersToPixels(
      radiusMeters,
      geometry.coordinates.lat.toDouble(),
    );

    geofenceZonePicker?.create(
      CircleAnnotationOptions(
        geometry: geometry,
        circleRadius: radiusInPixels,
        circleColor: fillColor.toARGB32(),
        circleOpacity: fillOpacity,
        circleStrokeColor: strokeColor.toARGB32(),
        circleStrokeWidth: 1.0,
      ),
    );

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

    NativeGeofenceManager.instance.createGeofence(geofence, geofenceTriggered);
    debugPrint('Geofence created: ${geofence.id}');
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

double metersToPixels(double radiusMeters, double latitude) {
  const double earthCircumference =
      40075016.686; // Earth's circumference in meters
  const double tileSize = 256.0; // Tile size in pixels

  // Adjust for latitude (cosine adjustment for non-equatorial locations)
  double latitudeAdjustment = 1 / (cos(latitude * pi / 180));

  // Convert meters to pixels
  return (radiusMeters / earthCircumference) * tileSize * latitudeAdjustment;
}
