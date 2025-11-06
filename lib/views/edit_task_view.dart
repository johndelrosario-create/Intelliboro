import 'package:flutter/material.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/viewmodel/Geofencing/map_viewmodel.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'dart:developer' as developer;
import 'dart:ui' as ui;
import 'package:intelliboro/services/notification_preferences_service.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String _selectedSoundKey = NotificationPreferencesService.soundDefault;

  GeofenceData? _originalGeofenceData;
  bool _isLoading = true;
  String? _errorMessage;

  // Snooze settings state
  int _currentSnoozeDuration = 5;
  bool _isLoadingSnoozeSettings = false;

  @override
  void initState() {
    super.initState();
    _taskNameController = TextEditingController();
    _mapViewModel = MapboxMapViewModel();
    _mapViewModel.addListener(_onMapViewModelChanged);
    _loadGeofenceData();
    _loadSnoozeSettings();
    // Load default notification sound preference
    Future.microtask(() async {
      final key = await NotificationPreferencesService().getDefaultSound();
      if (!mounted) return;
      setState(() {
        _selectedSoundKey = key;
      });
    });
  }

  void _onMapViewModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadGeofenceData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final data = await _geofenceStorage.getGeofenceById(widget.geofenceId);
      if (data != null) {
        _originalGeofenceData = data;
        _taskNameController.text = _originalGeofenceData!.task ?? '';

        // Wait for map to be ready before displaying geofence
        _mapViewModel.mapReadyFuture
            .then((_) async {
              if (!mounted) return;
              await _displayInitialGeofenceOnMap();
            })
            .catchError((error) {
              developer.log('Error waiting for map ready: $error');
            });
      } else {
        _errorMessage = 'Task not found.';
      }
    } catch (e) {
      developer.log('Error loading geofence data: $e');
      _errorMessage = 'Failed to load task details: ${e.toString()}';
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSnoozeSettings() async {
    setState(() {
      _isLoadingSnoozeSettings = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final duration =
          prefs.getInt('default_snooze_duration') ??
          TaskTimerService().defaultSnoozeDuration.inMinutes;

      setState(() {
        _currentSnoozeDuration = duration;
        _isLoadingSnoozeSettings = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingSnoozeSettings = false;
      });
    }
  }

  String formatDuration(int minutes) {
    if (minutes < 60) {
      return '${minutes}m';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return '${hours}h';
      } else {
        return '${hours}h ${remainingMinutes}m';
      }
    }
  }

  Future<void> _displayInitialGeofenceOnMap() async {
    if (_originalGeofenceData == null || _mapViewModel.mapboxMap == null) {
      return;
    }

    final initialPoint = Point(
      coordinates: Position(
        _originalGeofenceData!.longitude,
        _originalGeofenceData!.latitude,
      ),
    );

    // Fly to the geofence location and wait for animation to complete
    await _mapViewModel.mapboxMap!.flyTo(
      CameraOptions(center: initialPoint, zoom: 16),
      MapAnimationOptions(duration: 1000),
    );

    // Add a small delay to ensure camera is fully settled
    await Future.delayed(const Duration(milliseconds: 200));

    // Now display the existing geofence with proper pixel calculation
    await _mapViewModel.displayExistingGeofence(
      initialPoint,
      _originalGeofenceData!.radiusMeters,
    );

    _mapViewModel.selectedPoint = initialPoint;
    setState(() {});
  }

  void _onMapCreatedEditView(MapboxMap mapboxMap) async {
    await _mapViewModel.onMapCreated(mapboxMap);
    // The map is now ready and _loadGeofenceData will be notified via mapReadyFuture
    // No need to manually trigger display here as it's handled in _loadGeofenceData
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
      if (!mounted) return;
      setState(() => _isLoading = true);
      // Persist default notification sound preference
      try {
        await NotificationPreferencesService().setDefaultSound(
          _selectedSoundKey,
        );
      } catch (_) {}
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
              if (_mapViewModel.mapInitializationError != null)
                Center(
                  child: Card(
                    color: Colors.red.shade50,
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Map Error',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.red),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _mapViewModel.mapInitializationError ?? '',
                            style: const TextStyle(color: Colors.black87),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () async {
                              await _mapViewModel.refreshSavedGeofences();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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

  Widget _buildSnoozeSettingsSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.snooze_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Snooze Settings',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _isLoadingSnoozeSettings
                            ? 'Loading...'
                            : 'Current default: ${formatDuration(_currentSnoozeDuration)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Tasks are automatically snoozed when postponed or interrupted by higher priority tasks.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            // Inline snooze duration selector
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [5, 10, 15, 30, 60, 120].map((minutes) {
                    final isSelected = _currentSnoozeDuration == minutes;
                    return FilterChip(
                      label: Text(formatDuration(minutes)),
                      selected: isSelected,
                      onSelected: (selected) async {
                        if (selected) {
                          setState(() {
                            _currentSnoozeDuration = minutes;
                          });
                          // Save to preferences
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt(
                            'default_snooze_duration',
                            minutes,
                          );
                          // Update TaskTimerService
                          TaskTimerService().setDefaultSnoozeDuration(
                            Duration(minutes: minutes),
                          );
                        }
                      },
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
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
                              const SizedBox(height: 16),
                              Card.filled(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Default Notification Sound (Android)',
                                        style: textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: _selectedSoundKey,
                                            items:
                                                NotificationPreferencesService.getAvailableSounds()
                                                    .map(
                                                      (sound) =>
                                                          DropdownMenuItem<
                                                            String
                                                          >(
                                                            value: sound['key'],
                                                            child: Text(
                                                              sound['name']!,
                                                            ),
                                                          ),
                                                    )
                                                    .toList(),
                                            onChanged: (value) {
                                              if (value != null) {
                                                setState(() {
                                                  _selectedSoundKey = value;
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'This sets the app default sound used for task reminders on Android.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: OutlinedButton.icon(
                                          onPressed: () async {
                                            try {
                                              await openAppSettings();
                                            } catch (_) {}
                                          },
                                          icon: const Icon(
                                            Icons
                                                .settings_applications_outlined,
                                          ),
                                          label: const Text(
                                            'Open app notification settings',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Snooze settings section
                              _buildSnoozeSettingsSection(),
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
