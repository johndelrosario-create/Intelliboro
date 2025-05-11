import 'package:flutter/material.dart';
import 'package:intelliboro/services/geofencing_service.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as locator;
import 'package:intelliboro/services/location_service.dart';
import 'dart:math';

// Change Notifier, re-renderviews when data is changed.
class MapboxMapViewModel extends ChangeNotifier {
  final LocationService _locationService;
  late final GeofencingService _geofencingService;

  MapboxMap? mapboxMap;
  CircleAnnotationManager? geofenceZonePicker;
  CircleAnnotationManager? geofenceZoneSymbol;
  Point? selectedPoint;
  num? latitude;
  num? longitude;

  MapboxMapViewModel() : _locationService = LocationService();

  onMapCreated(MapboxMap mapboxMap) async {
    try {
      this.mapboxMap = mapboxMap;

      geofenceZonePicker =
          await mapboxMap.annotations.createCircleAnnotationManager();
      geofenceZoneSymbol =
          await mapboxMap.annotations.createCircleAnnotationManager();

      // Pass the annotation managers to GeofencingService
      _geofencingService = GeofencingService(this);

      mapboxMap.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
          showAccuracyRing: true,
          puckBearingEnabled: true,
        ),
      );

      locator.Position userPosition =
          await _locationService.getCurrentLocation();
      mapboxMap.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(
              userPosition.longitude,
              userPosition.latitude,
            ),
          ),
          zoom: 20,
          bearing: 0,
          pitch: 0,
        ),
        MapAnimationOptions(duration: 500),
      );

      notifyListeners();
    } catch (e) {
      debugPrint("Error in onMapCreated: $e");
    }
  }

  Future<double> currentZoomLevel() {
    if (mapboxMap == null) {
      debugPrint("MapboxMap is null");
      throw StateError("Error: MapboxMap not yet intialized.");
    }
    mapboxMap = mapboxMap;
    return mapboxMap!.getCameraState().then((cameraState) {
      return cameraState.zoom;
    });
  }

  onLongTap(MapContentGestureContext context) async {
    try {
      selectedPoint = context.point;
      latitude = context.point.coordinates.lat;
      longitude = context.point.coordinates.lng;

      // Desired radius in meters
      double radiusInMeters = 100;

      // Get the current zoom level
      double zoomLevel = await currentZoomLevel();

      // Convert radius in meters to pixels based on zoom level and latitude
      double radiusInPixels = metersToPixels(
        radiusInMeters,
        context.point.coordinates.lat.toDouble(),
        zoomLevel,
      );

      // Create the geofence zone with the calculated radius
      geofenceZoneSymbol!.create(
        CircleAnnotationOptions(
          geometry: context.point,
          circleRadius: radiusInPixels,
          circleColor: Colors.lightBlue.toARGB32(),
          circleOpacity: 0.2,
          circleStrokeColor: Colors.black.toARGB32(),
          circleStrokeWidth: 1.0,
        ),
      );

      notifyListeners();
    } catch (e) {
      debugPrint("Error in onLongTap: $e");
    }
  }

  // Helper method to convert meters to pixels based on zoom level and latitude
  double metersToPixels(
    double radiusMeters,
    double latitude,
    double zoomLevel,
  ) {
    const double earthCircumference =
        40075016.686; // Earth's circumference in meters
    const double tileSize = 256.0; // Tile size in pixels

    // Adjust for latitude (cosine adjustment for non-equatorial locations)
    double latitudeAdjustment = 1 / (cos(latitude * pi / 180));

    // Convert meters to pixels
    return (radiusMeters / earthCircumference) *
        pow(2, zoomLevel) *
        tileSize *
        latitudeAdjustment;
  }

  void createGeofenceAtSelectedPoint(BuildContext context) {
    if (selectedPoint != null) {
      _geofencingService.createGeofence(
        geometry: selectedPoint!,
        radiusMeters: 100,
        fillColor: Colors.amberAccent,
        fillOpacity: 0.5,
        strokeColor: Colors.white,
        strokeWidth: 2.0,
      );
      debugPrint(
        "Geofence created at: ${selectedPoint!.coordinates.lat}, ${selectedPoint!.coordinates.lng}",
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Geofence created successfully!')));
      selectedPoint = null;
      geofenceZoneSymbol?.deleteAll();
      notifyListeners();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No point selected to create a geofence.')),
      );
    }
  }

  CircleAnnotationManager? getGeofenceZonePicker() => geofenceZonePicker;
  CircleAnnotationManager? getGeofenceZoneSymbol() => geofenceZoneSymbol;
}
