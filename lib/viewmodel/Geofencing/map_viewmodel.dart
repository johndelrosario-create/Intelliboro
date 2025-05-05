import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as locator;
import 'package:intelliboro/services/location_service.dart';

// Change Notifier, re-renderviews when data is changed.
class MapboxMapViewModel extends ChangeNotifier {
  final LocationService _locationService;
  // What constructor? The inputs are the repository that provide it's data
  MapboxMapViewModel()
    :_locationService = LocationService();

  //These are state which are public members
  MapboxMap? mapboxMap;
  CircleAnnotationManager? geofenceZonePicker;
  CircleAnnotationManager? geofenceZoneSymbol;
  Point? selectedPoint;
  num? latitude;
  num? longitude;

  onMapCreated(MapboxMap mapboxMap) async {
    this.mapboxMap = mapboxMap;

    geofenceZonePicker =
        await mapboxMap.annotations.createCircleAnnotationManager();
    geofenceZoneSymbol =
        await mapboxMap.annotations.createCircleAnnotationManager();

    mapboxMap.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        showAccuracyRing: true,
        puckBearingEnabled: true,
      ),
    );
     locator.Position userPosition = await _locationService.getCurrentLocation();
    mapboxMap.flyTo(
      CameraOptions(
        center: Point(
          coordinates: Position(userPosition.longitude, userPosition.latitude),
        ),
        zoom: 20,
        bearing: 0,
        pitch: 0,
      ),
      MapAnimationOptions(duration: 500),
    );
    notifyListeners();
  }

  //   _onLongTap(MapContentGestureContext context) {
  //     setState(() {
  //       selectedPoint = context.point;
  //       latitude = context.point.coordinates.lat;
  //       longitude = context.point.coordinates.lng;
  //       //TODO: Radius must be obtained from map and set using a slider
  //     });
  //     geofenceZoneSymbol!.create(
  //       CircleAnnotationOptions(
  //         geometry: context.point,
  //         circleRadius: 10,
  //         circleColor: Colors.lightBlue.toARGB32(),
  //         circleOpacity: 0.2,
  //         circleStrokeColor: Colors.black.toARGB32(),
  //         circleStrokeWidth: 1.0,
  //       ),
  //     );
  //   }

  //   // TODO: Remove the helper once a geofence has been made
  //   void _createGeofenceAtSelectedPoint() {
  //     final selectedPointNotNull = selectedPoint;
  //     if (selectedPointNotNull != null && geofenceZonePicker != null) {
  //       geofenceZonePicker!.create(
  //         CircleAnnotationOptions(
  //           geometry: selectedPointNotNull,
  //           //TODO: Radius should reflect the radius in meters need a function to convert meters to pixels @ diff zoom levels
  //           circleRadius: 100,
  //           circleColor: Colors.amberAccent.toARGB32(),
  //           circleOpacity: 0.5,
  //           circleStrokeColor: Colors.white.toARGB32(),
  //           circleStrokeWidth: 2.0,
  //         ),
  //       );
  //     }
  //     if (latitude != null && longitude != null) {
  //       data = data.copyWith(id: () => "zone1");
  //       data = data.copyWith(
  //         location: () => data.location.copyWith(latitude: latitude?.toDouble()),
  //       );
  //       data = data.copyWith(
  //         location:
  //             () => data.location.copyWith(longitude: longitude?.toDouble()),
  //       );

  //       data = data.copyWith(radiusMeters: () => 10.0);
  //     }
  //   }

  //   Future<void> _updateRegisteredGeofences() async {
  //     final List<String> geofences =
  //         await NativeGeofenceManager.instance.getRegisteredGeofenceIds();
  //     setState(() {
  //       activeGeofences = geofences;
  //     });
  //     debugPrint('Active geofences updated.');
  //   }
}
