import 'package:flutter/material.dart';
//import 'package:flutter/services.dart';
import 'package:intelliboro/Geofencing/add_geofence.dart';
import 'package:intelliboro/Geofencing/callback.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:geolocator/geolocator.dart' as locator;

class FullMap extends StatefulWidget {
  const FullMap();

  @override
  State<StatefulWidget> createState() => FullMapState();
}

class FullMapState extends State<FullMap> {
  MapboxMap? mapboxMap;
  CircleAnnotationManager? circleAnnotationManager;
  CircleAnnotationManager? GeofenceHelper;
  Point? selectedPoint;
  num? latitude;
  num? longitude;

  List<String> activeGeofences = [];
  // field data has not been initalized
  late Geofence data;

  static const Location _initialLocation = Location(
    latitude: 0.00,
    longitude: 0.00,
  );
  @override
  void initState() {
    super.initState();
    data = Geofence(
      id: 'zone1',
      location: _initialLocation,
      radiusMeters: 500,
      triggers: {GeofenceEvent.enter, GeofenceEvent.exit},
      iosSettings: IosGeofenceSettings(initialTrigger: true),
      androidSettings: AndroidGeofenceSettings(
        initialTriggers: {GeofenceEvent.enter},
      ),
    );
    _updateRegisteredGeofences();
  }

  _onMapCreated(MapboxMap mapboxMap) async {
    this.mapboxMap = mapboxMap;

    circleAnnotationManager =
        await mapboxMap.annotations.createCircleAnnotationManager();
    GeofenceHelper =
        await mapboxMap.annotations.createCircleAnnotationManager();

    mapboxMap.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        showAccuracyRing: true,
        puckBearingEnabled: true,
      ),
    );
    locator.Position userPosition =
        await locator.Geolocator.getCurrentPosition();
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
  }

  _onLongTap(MapContentGestureContext context) {
    setState(() {
      selectedPoint = context.point;
      latitude = context.point.coordinates.lat;
      longitude = context.point.coordinates.lng;
    });
    GeofenceHelper!.create(
      CircleAnnotationOptions(
        geometry: context.point,
        circleRadius: 10,
        circleColor: Colors.lightBlue.toARGB32(),
        circleOpacity: 0.2,
        circleStrokeColor: Colors.black.toARGB32(),
        circleStrokeWidth: 1.0,
      ),
    );
  }

  // TODO: Remove the helper once a geofence has been made

  void _createGeofenceAtSelectedPoint() {
    final selectedPointNotNull = selectedPoint;
    if (selectedPointNotNull != null && circleAnnotationManager != null) {
      circleAnnotationManager!.create(
        CircleAnnotationOptions(
          geometry: selectedPointNotNull,
          circleRadius: 100,
          circleColor: Colors.amberAccent.toARGB32(),
          circleOpacity: 0.5,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2.0,
        ),
      );
    }
    // Data is not yet initialized
    if (latitude != null && longitude != null) {
      data = data.copyWith(id: () => "zone1");
      data = data.copyWith(
        location: () => data.location.copyWith(latitude: latitude?.toDouble()),
      );
      data = data.copyWith(
        location:
            () => data.location.copyWith(longitude: longitude?.toDouble()),
      );

      data = data.copyWith(radiusMeters: () => 10.0);
    }
  }

  Future<void> _updateRegisteredGeofences() async {
    final List<String> geofences =
        await NativeGeofenceManager.instance.getRegisteredGeofenceIds();
    setState(() {
      activeGeofences = geofences;
    });
    debugPrint('Active geofences updated.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: MapWidget(
              key: ValueKey("mapWidget"),
              onMapCreated: _onMapCreated,
              onLongTapListener: _onLongTap,
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              _createGeofenceAtSelectedPoint();
              await NativeGeofenceManager.instance.createGeofence(
                data,
                geofenceTriggered,
              );
              debugPrint('Geofence created: ${data.location  }');
              await _updateRegisteredGeofences();
              await Future.delayed(const Duration(seconds: 1));
              await _updateRegisteredGeofences();
            },
            child: Text("Add geofence"),
          ),
        ],
      ),
    );
  }
}

extension ModifyGeofence on Geofence {
  Geofence copyWith({
    String Function()? id,
    Location Function()? location,
    double Function()? radiusMeters,
    Set<GeofenceEvent> Function()? triggers,
    IosGeofenceSettings Function()? iosSettings,
    AndroidGeofenceSettings Function()? androidSettings,
  }) {
    return Geofence(
      id: id?.call() ?? this.id,
      location: location?.call() ?? this.location,
      radiusMeters: radiusMeters?.call() ?? this.radiusMeters,
      triggers: triggers?.call() ?? this.triggers,
      iosSettings: iosSettings?.call() ?? this.iosSettings,
      androidSettings: androidSettings?.call() ?? this.androidSettings,
    );
  }
}

extension ModifyLocation on Location {
  Location copyWith({double? latitude, double? longitude}) {
    return Location(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}

extension ModifyAndroidGeofenceSettings on AndroidGeofenceSettings {
  AndroidGeofenceSettings copyWith({
    Set<GeofenceEvent> Function()? initialTrigger,
    Duration Function()? expiration,
    Duration Function()? loiteringDelay,
    Duration Function()? notificationResponsiveness,
  }) {
    return AndroidGeofenceSettings(
      initialTriggers: initialTrigger?.call() ?? this.initialTriggers,
      expiration: expiration?.call() ?? this.expiration,
      loiteringDelay: loiteringDelay?.call() ?? this.loiteringDelay,
      notificationResponsiveness:
          notificationResponsiveness?.call() ?? this.notificationResponsiveness,
    );
  }
}
