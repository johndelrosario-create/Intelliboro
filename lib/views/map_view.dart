import 'package:flutter/material.dart';
import 'package:intelliboro/viewModel/Geofencing/map_viewmodel.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class MapboxMapView extends StatefulWidget {
  const MapboxMapView({Key? key}) : super(key: key);

  @override
  State<MapboxMapView> createState() => _MapboxMapViewState();
}

class _MapboxMapViewState extends State<MapboxMapView> {
  late final MapboxMapViewModel mapViewModel;
  @override
  void initState() {
    super.initState();
    mapViewModel = MapboxMapViewModel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: MapboxMapViewModel(),
              builder: (context, child) {
                return MapWidget(
                  key: ValueKey("mapwidget"),
                  onMapCreated: mapViewModel.onMapCreated,
                  onLongTapListener: mapViewModel.onLongTap,
                  onZoomListener: mapViewModel.onZoom,
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              mapViewModel.createGeofenceAtSelectedPoint(context);

              // await NativeGeofenceManager.instance.createGeofence(
              //   data,
              //   geofenceTriggered,
              // );
              // debugPrint('Geofence created: ${data.location}');
              // await _updateRegisteredGeofences();
              // await Future.delayed(const Duration(seconds: 1));
              // await _updateRegisteredGeofences();
            },
            child: Text("Add geofence"),
          ),
        ],
      ),
    );
  }
}
