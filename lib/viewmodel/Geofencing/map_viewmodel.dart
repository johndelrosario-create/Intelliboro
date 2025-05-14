import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intelliboro/services/geofencing_service.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as locator;
import 'package:intelliboro/services/location_service.dart';

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
  double? circleRadiusInPixels;
  late final Projection projection = Projection();
  bool isGeofenceHelperPlaced = false; // Flag to track if the helper is placed

  Timer? _debugTimer;

  MapboxMapViewModel() : _locationService = LocationService();

  // Start a timer to log the value of fixedRadiusInPixels
  void startDebugLogging() {
    _debugTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (circleRadiusInPixels != null) {
        debugPrint("Current circleRadiusInPixels: $circleRadiusInPixels");
      } else {
        debugPrint("fixedRadiusInPixels is not set yet.");
      }
    });
  }

  void stopDebugLogging() {
    _debugTimer?.cancel();
  }

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
    return mapboxMap!.getCameraState().then((cameraState) {
      return cameraState.zoom;
    });
  }

  onLongTap(MapContentGestureContext context) async {
    try {
      //   if (isGeofenceHelperPlaced) {
      //     debugPrint("Geofence helper is already placed. Ignoring further taps.");
      //     return;
      //   }
      //   startDebugLogging();

      //   selectedPoint = context.point;
      //   latitude = context.point.coordinates.lat;
      //   longitude = context.point.coordinates.lng;

      //   // Desired radius in meters
      //   double radiusInMeters = 50;

      //   // Convert radius in meters to pixels (fixed calculation)
      //   double metersPerPixel = await metersToPixels(radiusInMeters);
      //   debugPrint("meters per pixel: $metersPerPixel");
      //   circleRadiusInPixels = radiusInMeters / metersPerPixel;
      //   debugPrint("Pixel for radius : $circleRadiusInPixels");

      // Create the geofence zone helper with the calculated radius
      geofenceZoneSymbol!.create(
        CircleAnnotationOptions(
          geometry: context.point,
          circleRadius: circleRadiusInPixels,
          circleColor: Colors.lightBlue.toARGB32(),
          circleOpacity: 0.2,
          circleStrokeColor: Colors.black.toARGB32(),
          circleStrokeWidth: 1.0,
        ),
      );

      isGeofenceHelperPlaced = true; // Mark the helper as placed
      debugPrint(
        "Geofence helper placed with radius in pixels: $circleRadiusInPixels",
      );
      notifyListeners();
    } catch (e) {
      debugPrint("Error in onLongTap: $e");
    }
  }

  onZoom(MapContentGestureContext context) async {
    try {
      if (isGeofenceHelperPlaced) {
        debugPrint("Geofence helper is already placed. Ignoring further taps.");
        return;
      }
      startDebugLogging();

      selectedPoint = context.point;
      latitude = context.point.coordinates.lat;
      longitude = context.point.coordinates.lng;

      // Desired radius in meters
      double radiusInMeters = 50;

      // Convert radius in meters to pixels (fixed calculation)
      double metersPerPixel = await metersToPixels(radiusInMeters);
      debugPrint("meters per pixel: $metersPerPixel");
      circleRadiusInPixels = radiusInMeters / metersPerPixel;
      debugPrint("Pixel for radius : $circleRadiusInPixels");

      // Create the geofence zone helper with the calculated radius
      // geofenceZoneSymbol!.create(
      //   CircleAnnotationOptions(
      //     geometry: context.point,
      //     circleRadius: circleRadiusInPixels,
      //     circleColor: Colors.lightBlue.toARGB32(),
      //     circleOpacity: 0.2,
      //     circleStrokeColor: Colors.black.toARGB32(),
      //     circleStrokeWidth: 1.0,
      //   ),
      // );

      //Update the circle's radius
      await geofenceZonePicker!.setCircleRadius(circleRadiusInPixels ?? 0.0);
      notifyListeners();

      isGeofenceHelperPlaced = true; // Mark the helper as placed
      debugPrint(
        "Geofence helper placed with radius in pixels: $circleRadiusInPixels",
      );
    } catch (e) {
      debugPrint("Error in onZoom: $e");
    }
  }

  // Simplified helper method to convert meters to pixels
  Future<double> metersToPixels(double radiusMeters) async {
    if (mapboxMap == null) {
      throw StateError("Error: MapboxMap not yet intialized.");
    }
    try {
      if (latitude == null) {
        throw StateError("Longitude is null");
      }
      double zoomLevel = await currentZoomLevel();
      debugPrint("METERS TO PIX lat_long:$latitude, $longitude");
      debugPrint("METERSTOPIXL zoom:$zoomLevel");
      return mapboxMap!.projection.getMetersPerPixelAtLatitude(
        latitude!.toDouble(),
        zoomLevel,
      );
    } catch (e) {
      debugPrint("Error in metersToPixels: $e");
      return 0.0; // Return a default value in case of error}
    }
  }

  void createGeofenceAtSelectedPoint(BuildContext context) {
    if (selectedPoint != null) {
      _geofencingService.createGeofence(
        geometry: selectedPoint!,
        radiusMeters: 50,
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
      isGeofenceHelperPlaced = false; // Reset the flag after geofence creation
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
