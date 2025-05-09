import 'package:flutter/material.dart';
import 'package:intelliboro/services/geofencing_service.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as locator;
import 'package:intelliboro/services/location_service.dart';

// Change Notifier, re-renderviews when data is changed.
class MapboxMapViewModel extends ChangeNotifier {
  final LocationService _locationService;
  late final GeofencingService _geofencingService;

  MapboxMapViewModel() : _locationService = LocationService();

  MapboxMap? mapboxMap;
  CircleAnnotationManager? geofenceZonePicker;
  CircleAnnotationManager? geofenceZoneSymbol;
  Point? selectedPoint;
  num? latitude;
  num? longitude;

  onMapCreated(MapboxMap mapboxMap) async {
    try {
      this.mapboxMap = mapboxMap;

      geofenceZonePicker =
          await mapboxMap.annotations.createCircleAnnotationManager();
      geofenceZoneSymbol =
          await mapboxMap.annotations.createCircleAnnotationManager();

      // Circle annotation for geofence zone
      _geofencingService = GeofencingService(geofenceZonePicker!);

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

  onLongTap(MapContentGestureContext context) {
    selectedPoint = context.point;
    latitude = context.point.coordinates.lat;
    longitude = context.point.coordinates.lng;
    //TODO: Radius must be obtained from map and set using a slider
    geofenceZoneSymbol!.create(
      CircleAnnotationOptions(
        geometry: context.point,
        circleRadius: 10,
        circleColor: Colors.lightBlue.toARGB32(),
        circleOpacity: 0.2,
        circleStrokeColor: Colors.black.toARGB32(),
        circleStrokeWidth: 1.0,
      ),
    );
    notifyListeners();
  }

  void createGeofenceAtSelectedPoint(BuildContext context) {
    if (selectedPoint != null) {
      _geofencingService.createGeofence(
        geometry: selectedPoint!,
        radius: 100,
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
}
