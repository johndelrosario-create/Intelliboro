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
                onMapIdleListener: mapViewModel.onCameraIdle,
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
              // Show dialog to get task name
              final taskName = await _showTaskNameDialog(context);
              if (taskName != null && taskName.isNotEmpty) {
                mapViewModel.createGeofenceAtSelectedPoint(
                  context,
                  taskName: taskName, // Pass the task name
                );
              }
            },
            child: Text("Add geofence"),
          ),
        ],
      ),
    );
  }

  Future<String?> _showTaskNameDialog(BuildContext context) async {
    final TextEditingController taskNameController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Enter Task Name'),
          content: TextField(
            controller: taskNameController,
            decoration: const InputDecoration(hintText: "Task Name"),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop(taskNameController.text);
              },
            ),
          ],
        );
      },
    );
  }
}
