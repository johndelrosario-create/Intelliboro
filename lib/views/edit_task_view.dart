import 'package:flutter/material.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/viewModel/Geofencing/map_viewmodel.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

class EditTaskView extends StatefulWidget {
  final String geofenceId;

  const EditTaskView({Key? key, required this.geofenceId}) : super(key: key);

  @override
  _EditTaskViewState createState() => _EditTaskViewState();
}

class _EditTaskViewState extends State<EditTaskView> {
  final _formKey = GlobalKey<FormState>();
  final GeofenceStorage _geofenceStorage = GeofenceStorage();
  late TextEditingController _taskNameController;
  late MapboxMapViewModel _mapViewModel;

  GeofenceData? _originalGeofenceData;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isMapReadyForInitialDisplay = false;

  @override
  void initState() {
    super.initState();
    _taskNameController = TextEditingController();
    _mapViewModel = MapboxMapViewModel();
    _mapViewModel.addListener(_onMapViewModelChanged);
    _loadGeofenceData();
  }

  void _onMapViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadGeofenceData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final data = await _geofenceStorage.getGeofenceById(widget.geofenceId);
      if (data != null) {
        _originalGeofenceData = data;
        _taskNameController.text = _originalGeofenceData!.task ?? '';

        if (_isMapReadyForInitialDisplay && _mapViewModel.mapboxMap != null) {
          await _displayInitialGeofenceOnMap();
        }
      } else {
        _errorMessage = 'Task not found.';
      }
    } catch (e) {
      developer.log('Error loading geofence data: $e');
      _errorMessage = 'Failed to load task details: ${e.toString()}';
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _displayInitialGeofenceOnMap() async {
    if (_originalGeofenceData == null || _mapViewModel.mapboxMap == null)
      return;

    final initialPoint = Point(
      coordinates: Position(
        _originalGeofenceData!.longitude,
        _originalGeofenceData!.latitude,
      ),
    );

    await _mapViewModel.mapboxMap!.flyTo(
      CameraOptions(center: initialPoint, zoom: 16),
      MapAnimationOptions(duration: 1000),
    );
    await _mapViewModel.displayExistingGeofence(
      initialPoint,
      _originalGeofenceData!.radiusMeters,
    );

    _mapViewModel.selectedPoint = initialPoint;
    setState(() {});
  }

  void _onMapCreatedEditView(MapboxMap mapboxMap) async {
    await _mapViewModel.onMapCreated(mapboxMap);
    setState(() {
      _isMapReadyForInitialDisplay = true;
    });
    if (!_isLoading && _originalGeofenceData != null) {
      await _displayInitialGeofenceOnMap();
    }
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;
    if (_originalGeofenceData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Original geofence data not found.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final updatedTaskName = _taskNameController.text;

    Point geofencePoint;
    if (_mapViewModel.selectedPoint != null) {
      geofencePoint = _mapViewModel.selectedPoint!;
    } else {
      geofencePoint = Point(
        coordinates: Position(
          _originalGeofenceData!.longitude,
          _originalGeofenceData!.latitude,
        ),
      );
      developer.log(
        "SaveTask: Using original geofence point as mapViewModel.selectedPoint was null",
      );
    }

    final double geofenceRadius = _originalGeofenceData!.radiusMeters;

    final updatedGeofenceData = GeofenceData(
      id: _originalGeofenceData!.id,
      latitude: geofencePoint.coordinates.lat.toDouble(),
      longitude: geofencePoint.coordinates.lng.toDouble(),
      radiusMeters: geofenceRadius,
      fillColor: _originalGeofenceData!.fillColor,
      fillOpacity: _originalGeofenceData!.fillOpacity,
      strokeColor: _originalGeofenceData!.strokeColor,
      strokeWidth: _originalGeofenceData!.strokeWidth,
      task: updatedTaskName,
    );

    try {
      setState(() => _isLoading = true);
      await _geofenceStorage.saveGeofence(updatedGeofenceData);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      developer.log('Error saving geofence data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update task: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _taskNameController.dispose();
    _mapViewModel.removeListener(_onMapViewModelChanged);
    _mapViewModel.dispose();
    super.dispose();
  }

  Widget _buildMapSection() {
    return ListenableBuilder(
      listenable: _mapViewModel,
      builder: (context, child) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          width: MediaQuery.of(context).size.width,
          child: Stack(
            children: [
              MapWidget(
                key: const ValueKey("edit_task_mapwidget"),
                onMapCreated: _onMapCreatedEditView,
                onLongTapListener: _mapViewModel.onLongTap,
                onZoomListener: _mapViewModel.onZoom,
              ),
              if (!_mapViewModel.isMapReady ||
                  (_isLoading && _originalGeofenceData == null))
                const Center(child: CircularProgressIndicator()),
              if (_mapViewModel.selectedPoint != null)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Chip(
                    label: Text(
                      _mapViewModel.selectedPoint!.coordinates.lat
                                      .toStringAsFixed(3) ==
                                  _originalGeofenceData?.latitude
                                      .toStringAsFixed(3) &&
                              _mapViewModel.selectedPoint!.coordinates.lng
                                      .toStringAsFixed(3) ==
                                  _originalGeofenceData?.longitude
                                      .toStringAsFixed(3)
                          ? 'Current Geofence Location'
                          : 'New Geofence Location Selected',
                    ),
                    backgroundColor: Colors.greenAccent,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(
      context,
    ).textTheme.apply(displayColor: Theme.of(context).colorScheme.onSurface);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Task & Geofence')),
      body:
          (_isLoading && _originalGeofenceData == null)
              ? const Center(child: CircularProgressIndicator())
              : ((_errorMessage != null)
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadGeofenceData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                  : ((_originalGeofenceData == null)
                      ? const Center(
                        child: Text('Task data not available to edit.'),
                      )
                      : SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Text('Task Name', style: textTheme.titleMedium),
                              const SizedBox(height: 8.0),
                              TextFormField(
                                controller: _taskNameController,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'Enter task name',
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter a task name';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Geofence Location & Radius',
                                style: textTheme.titleMedium,
                              ),
                              const Text(
                                'Long-press on the map to select a new location. Radius is fixed at 50m for now.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8.0),
                              _buildMapSection(),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _isLoading ? null : _saveTask,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const ui.Size(300, 50),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16.0,
                                  ),
                                ),
                                child:
                                    (_isLoading &&
                                            _originalGeofenceData != null)
                                        ? const SizedBox(
                                          height: 24.0,
                                          width: 24.0,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                        : const Text('Save Changes'),
                              ),
                            ],
                          ),
                        ),
                      ))),
    );
  }
}
