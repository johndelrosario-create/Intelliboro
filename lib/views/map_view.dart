import 'package:flutter/material.dart';
import 'package:intelliboro/viewModel/Geofencing/map_viewmodel.dart';
//import 'package:flutter/services.dart';
import 'package:intelliboro/viewModel/notifications/callback.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:geolocator/geolocator.dart' as locator;

import 'package:intelliboro/viewModel/Geofencing/create_tasks_viewmodel.dart';

class MapboxMapView extends StatefulWidget {
  const MapboxMapView({Key? key}) : super(key: key);

  @override
  State<MapboxMapView> createState() => _MapboxMapViewState();
}

class _MapboxMapViewState extends State<MapboxMapView> {
  final MapboxMapViewModel mapboxMap = MapboxMapViewModel();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            // child: MapWidget(
            //   key: ValueKey("mapWidget"),
            //   onMapCreated: onMapCreated(),
            //   // onLongTapListener: _onLongTap,
            // ),
            child: ListenableBuilder(
              listenable: MapboxMapViewModel(),
              builder: (context, child) {
                return MapWidget(
                  key: ValueKey("mapwidget"),
                  onMapCreated: mapboxMap.onMapCreated,
                  onLongTapListener: mapboxMap.onLongTap,
                );
              },
            ),
          ),
          // ElevatedButton(
          //   onPressed: () async {
          //     _createGeofenceAtSelectedPoint();
          //     await NativeGeofenceManager.instance.createGeofence(
          //       data,
          //       geofenceTriggered,
          //     );
          //     debugPrint('Geofence created: ${data.location}');
          //     await _updateRegisteredGeofences();
          //     await Future.delayed(const Duration(seconds: 1));
          //     await _updateRegisteredGeofences();
          //   },
          //   child: Text("Add geofence"),
          // ),
        ],
      ),
    );
  }
}
