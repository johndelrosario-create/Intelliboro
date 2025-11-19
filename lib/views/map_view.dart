import 'package:flutter/material.dart';
import 'package:intelliboro/viewmodel/Geofencing/map_viewmodel.dart'
    as MapViewModelImport;
import 'package:intelliboro/services/mapbox_search_service.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:intelliboro/services/location_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class MapboxMapView extends StatefulWidget {
  const MapboxMapView({Key? key}) : super(key: key);

  @override
  State<MapboxMapView> createState() => _MapboxMapViewState();
}

class _MapboxMapViewState extends State<MapboxMapView> {
  late final MapViewModelImport.MapboxMapViewModel mapViewModel;
  late final MapboxSearchService _searchService;
  late final TaskTimerService _taskTimerService;
  String? _selectedGeofenceId;

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<SearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;

  @override
  void initState() {
    super.initState();
    mapViewModel = MapViewModelImport.MapboxMapViewModel();
    _searchService = MapboxSearchService();
    _taskTimerService = TaskTimerService();

    // Listen to search input changes
    _searchController.addListener(_onSearchChanged);

    // Listen to focus changes to control search results visibility
    _searchFocusNode.addListener(_onSearchFocusChanged);

    // Listen to task changes to refresh geofences when tasks are completed
    _taskTimerService.tasksChanged.addListener(_onTasksChanged);
  }

  void _onTasksChanged() {
    // When tasks change (e.g., completion), refresh geofences to remove completed task geofences
    if (_taskTimerService.tasksChanged.value) {
      mapViewModel.refreshSavedGeofences();
      _taskTimerService.tasksChanged.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Search input field
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search for a location...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon:
                        _searchController.text.isNotEmpty
                            ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            )
                            : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    fillColor: Theme.of(context).colorScheme.surface,
                    filled: true,
                  ),
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      _performSearch(value);
                    }
                  },
                ),

                // Search results dropdown
                if (_showSearchResults && _searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8.0,
                          spreadRadius: 1.0,
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return ListTile(
                          leading: const Icon(Icons.location_on, size: 20),
                          title: Text(
                            result.name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            result.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          dense: true,
                          onTap: () => _selectSearchResult(result),
                        );
                      },
                    ),
                  ),

                // Loading indicator
                if (_isSearching)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),

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
                    if (mapViewModel.mapInitializationError != null)
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
                                  mapViewModel.mapInitializationError ?? '',
                                  style: const TextStyle(color: Colors.black87),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: () async {
                                    // Retry by reloading saved geofences and re-running portions of setup
                                    await mapViewModel.refreshSavedGeofences();
                                  },
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Floating action button for user location
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: FloatingActionButton(
                        mini: true,
                        onPressed: () async {
                          final success =
                              await mapViewModel.flyToUserLocation();
                          if (!success && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Unable to get current location'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        child: const Icon(Icons.my_location),
                      ),
                    ),

                    // Location warning overlay
                    if (mapViewModel.locationStatus != LocationStatus.granted)
                      _buildLocationWarningOverlay(context),
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
                          items:
                              mapViewModel.savedGeofences
                                  .map(
                                    (g) => DropdownMenuItem<String>(
                                      value: g.id,
                                      child: Text(
                                        '${g.task ?? g.id} • ${g.radiusMeters.toStringAsFixed(0)}m',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
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
                        onPressed:
                            _selectedGeofenceId == null
                                ? null
                                : () async {
                                  // Re-load to ensure helper is visible if user changed selection
                                  await mapViewModel.beginEditGeofence(
                                    _selectedGeofenceId!,
                                  );
                                },
                        child: const Text('Load'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (mapViewModel.isEditing) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Editing: ' +
                          (mapViewModel.editingGeofence?.task ??
                              mapViewModel.editingGeofenceId ??
                              ''),
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
                  label:
                      '${mapViewModel.pendingRadiusMeters.toStringAsFixed(0)} m',
                  onChanged: (v) => mapViewModel.setPendingRadius(v),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        mapViewModel.isEditing
                            ? null
                            : () async {
                              // Show dialog to get task name
                              final taskName = await _showTaskNameDialog(
                                context,
                              );
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
                    onPressed:
                        mapViewModel.isEditing
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

  /// Handle search input changes
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults.clear();
        _showSearchResults = false;
        _isSearching = false;
      });
      _searchService.cancelPendingSearches();
    } else {
      _performSearch(query);
    }
  }

  /// Handle search focus changes
  void _onSearchFocusChanged() {
    if (!_searchFocusNode.hasFocus) {
      // Delay hiding results to allow tapping on results
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          setState(() {
            _showSearchResults = false;
          });
        }
      });
    }
  }

  /// Perform search using the search service
  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });

    try {
      // Get current map center for proximity bias
      Point? proximityPoint;
      if (mapViewModel.mapboxMap != null) {
        final cameraState = await mapViewModel.mapboxMap!.getCameraState();
        proximityPoint = cameraState.center;
      }

      final results = await _searchService.searchPlaces(
        query: query,
        proximity: proximityPoint,
        limit: 5,
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
          _showSearchResults = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _showSearchResults = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Handle search result selection
  Future<void> _selectSearchResult(SearchResult result) async {
    // Hide search results and clear focus
    if (!mounted) return;
    setState(() {
      _showSearchResults = false;
    });
    _searchFocusNode.unfocus();

    // Update search field with selected result
    _searchController.text = result.name;

    try {
      // Fly to the selected location
      if (mapViewModel.mapboxMap != null) {
        await mapViewModel.mapboxMap!.flyTo(
          CameraOptions(
            center: result.toMapboxPoint(),
            zoom: 16,
            bearing: 0,
            pitch: 0,
          ),
          MapAnimationOptions(duration: 1500),
        );

        // Auto-place a geofence helper at the searched location
        await _placeGeofenceAtSearchResult(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error navigating to location: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Place a geofence helper at the search result location
  Future<void> _placeGeofenceAtSearchResult(SearchResult result) async {
    try {
      final point = result.toMapboxPoint();

      // Update the selected point in the view model first
      mapViewModel.selectedPoint = point;
      mapViewModel.latitude = result.latitude;
      mapViewModel.longitude = result.longitude;
      mapViewModel.isGeofenceHelperPlaced = true;

      // Use the map view model's method to display the helper at this location
      await mapViewModel.displayExistingGeofence(
        mapViewModel.pendingRadiusMeters,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error placing geofence helper: ${e.toString()}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Clear search input and results
  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults.clear();
      _showSearchResults = false;
      _isSearching = false;
    });
    _searchService.cancelPendingSearches();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchService.dispose();
    _taskTimerService.tasksChanged.removeListener(_onTasksChanged);
    super.dispose();
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

  /// Build location warning overlay
  Widget _buildLocationWarningOverlay(BuildContext context) {
    String title;
    String message;
    String actionButtonText;
    VoidCallback actionButtonCallback;

    switch (mapViewModel.locationStatus) {
      case LocationStatus.disabled:
        title = '⚠️ Location Services Disabled';
        message =
            'Location services are currently turned off. This app requires location access to display the map and set location-based alarms.\n\nPlease enable location services in your device settings.';
        actionButtonText = 'Open Settings';
        actionButtonCallback = () async {
          await Geolocator.openLocationSettings();
          // Wait a bit and then check status again
          Future.delayed(const Duration(seconds: 1), () {
            mapViewModel.checkLocationStatus();
          });
        };
        break;

      case LocationStatus.denied:
        title = '⚠️ Location Permission Required';
        message =
            'This app needs location permission to display the map and set location-based alarms.\n\nPlease grant location permission to continue.';
        actionButtonText = 'Grant Permission';
        actionButtonCallback = () async {
          await mapViewModel.retryLocationSetup();
          if (mounted) {
            await mapViewModel.checkLocationStatus();
          }
        };
        break;

      case LocationStatus.permanentlyDenied:
        title = '⚠️ Location Permission Denied';
        message =
            'Location permission has been permanently denied. This app requires location access to display the map and set location-based alarms.\n\nPlease enable location permission in app settings.';
        actionButtonText = 'Open App Settings';
        actionButtonCallback = () async {
          await openAppSettings();
          // Wait a bit and then check status again
          Future.delayed(const Duration(seconds: 1), () {
            mapViewModel.checkLocationStatus();
          });
        };
        break;

      case LocationStatus.granted:
        // This shouldn't happen as the overlay is only shown when not granted
        return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_off,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: actionButtonCallback,
                      icon: const Icon(Icons.settings),
                      label: Text(actionButtonText),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Go Back'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Note: Without location access, you can still set regular alarms, but map view and location-based features will be unavailable.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
