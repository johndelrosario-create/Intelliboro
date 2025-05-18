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
              listenable: mapViewModel,
              builder: (context, child) {
                return Stack(
                  children: [
                    MapWidget(
                      key: ValueKey("mapwidget"),
                      onMapCreated: mapViewModel.onMapCreated,
                      onLongTapListener: mapViewModel.onLongTap,
                      onZoomListener: mapViewModel.onZoom,
                    ),
                    if (!mapViewModel.isMapReady)
                      const Center(child: CircularProgressIndicator()),
                  ],
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              mapViewModel.createGeofenceAtSelectedPoint(context);
            },
            child: Text("Add geofence"),
          ),
        ],
      ),
    );
  }
}
