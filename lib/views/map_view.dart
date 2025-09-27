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
  String? _selectedGeofenceId;
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Edit existing geofence controls
                if (mapViewModel.savedGeofences.isNotEmpty) ...[
                  Text(
                    'Edit existing geofence',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedGeofenceId,
                          hint: const Text('Select geofence to edit'),
                          items: mapViewModel.savedGeofences
                              .map((g) => DropdownMenuItem<String>(
                                    value: g.id,
                                    child: Text(
                                      '${g.task ?? g.id} • ${g.radiusMeters.toStringAsFixed(0)}m',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (val) async {
                            setState(() {
                              _selectedGeofenceId = val;
                            });
                            if (val != null) {
                              await mapViewModel.beginEditGeofence(val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _selectedGeofenceId == null
                            ? null
                            : () async {
                                // Re-load to ensure helper is visible if user changed selection
                                await mapViewModel.beginEditGeofence(
                                    _selectedGeofenceId!);
                              },
                        child: const Text('Load'),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (mapViewModel.isEditing) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Editing: ' +
                          (mapViewModel.editingGeofence?.task ?? mapViewModel.editingGeofenceId ?? ''),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  'Radius: ${mapViewModel.pendingRadiusMeters.toStringAsFixed(0)} m',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Slider(
                  value: mapViewModel.pendingRadiusMeters.clamp(1.0, 1000.0),
                  min: 1,
                  max: 1000,
                  divisions: 999,
                  label: '${mapViewModel.pendingRadiusMeters.toStringAsFixed(0)} m',
                  onChanged: (v) => mapViewModel.setPendingRadius(v),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: mapViewModel.isEditing
                        ? null
                        : () async {
                      // Show dialog to get task name
                      final taskName = await _showTaskNameDialog(context);
                      if (taskName != null && taskName.isNotEmpty) {
                        mapViewModel.createGeofenceAtSelectedPoint(
                          context,
                          taskName: taskName, // Pass the task name
                        );
                      }
                    },
                    child: const Text("Add geofence"),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: mapViewModel.isEditing
                        ? () async {
                            await mapViewModel.saveEditedGeofence(context);
                          }
                        : null,
                    child: const Text('Save edits'),
                  ),
                ),
              ],
            ),
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