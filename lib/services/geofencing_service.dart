import 'package:flutter/material.dart';
import 'package:intelliboro/viewModel/notifications/callback.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:native_geofence/native_geofence.dart';

class GeofencingService {
  final CircleAnnotationManager geofenceZonePicker;
  GeofencingService(this.geofenceZonePicker);

  void createGeofence({
    required Point geometry,
    double radius = 10.0,
    Color fillColor = Colors.amberAccent,
    Color strokeColor = Colors.white,
    double strokeWidth = 2.0,
    double fillOpacity = 0.5,
  }) {
    geofenceZonePicker.create(
      CircleAnnotationOptions(
        geometry: geometry,
        circleRadius: 100,
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
      radiusMeters: 100.0,
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
