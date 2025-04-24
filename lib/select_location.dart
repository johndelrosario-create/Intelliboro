
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
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

  void _createGeofenceAtSelectedPoint() {
    final selectedPointNotNull = selectedPoint;
    if (selectedPointNotNull != null && circleAnnotationManager != null) {
      circleAnnotationManager!.create(
        CircleAnnotationOptions(
          geometry: selectedPointNotNull,
          circleRadius: 100,
          circleColor: Colors.blue.value,
          circleOpacity: 0.5,
          circleStrokeColor: Colors.white.value,
          circleStrokeWidth: 2.0,
        ),
      );
    }
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
            onPressed: _createGeofenceAtSelectedPoint,
            child: Text("Add geofence"),
          ),
        ],
      ),
    );
  }
}
