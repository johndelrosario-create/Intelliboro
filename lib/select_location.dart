import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as locator;

class FullMap extends StatefulWidget {
  const FullMap();

  @override
  State<StatefulWidget> createState() => FullMapState();
}

class FullMapState extends State<FullMap> {
  MapboxMap? mapboxMap;

  _onMapCreated(MapboxMap mapboxMap) async {
    this.mapboxMap = mapboxMap;

    mapboxMap.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        showAccuracyRing: true,
        puckBearingEnabled: true,
      ),
    );
    locator.Position userPosition = await locator.Geolocator.getCurrentPosition();
    mapboxMap.flyTo(
      CameraOptions(
        center: Point(
          coordinates: Position(userPosition.longitude, userPosition.latitude),
        ),
        zoom: 25,
        bearing: 0,
        pitch: 0,
      ),
      MapAnimationOptions(duration: 500),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapWidget(key: ValueKey("mapWidget"), onMapCreated: _onMapCreated),
    );
  }
}
