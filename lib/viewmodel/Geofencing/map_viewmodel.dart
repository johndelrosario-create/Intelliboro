import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intelliboro/services/geofencing_service.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as locator;
import 'package:intelliboro/services/location_service.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/models/geofence_data.dart';

// Change Notifier, re-renderviews when data is changed.
class MapboxMapViewModel extends ChangeNotifier {
  final LocationService _locationService;
  late final GeofencingService _geofencingService;

  MapboxMap? mapboxMap;
  bool isMapReady = false;
  CircleAnnotationManager? geofenceZoneHelper;
  CircleAnnotationManager? geofenceZoneSymbol;
  Point? selectedPoint;
  num? latitude;
  num? longitude;
  CameraState? cameraState;

  // Target radius in meters for the helper circle.
  static const double _helperTargetRadiusMeters = 50.0;
  // This will store the calculated pixel radius for the helper, updated on zoom/tap.
  double _currentHelperRadiusInPixels =
      30.0; // Initial fallback if map not ready for calc.

  List<CircleAnnotation> geofenceZoneHelperIds = [];
  List<CircleAnnotation> geofenceZoneSymbolIds =
      []; // These are for the actual saved geofences
  bool isGeofenceHelperPlaced = false;

  Timer? _debugTimer;
  final GeofenceStorage _geofenceStorage = GeofenceStorage();
  List<GeofenceData> _savedGeofences = [];
  String? mapInitializationError; // To store any error message during map setup

  MapboxMapViewModel() : _locationService = LocationService() {
    _geofencingService = GeofencingService(this);
  }

  Future<void> _loadSavedGeofences({bool forceNativeRecreation = true}) async {
    mapInitializationError = null; // Clear previous errors
    try {
      debugPrint('[MapViewModel] Loading saved geofences...');
      _savedGeofences = await _geofenceStorage.loadGeofences();
      debugPrint(
        '[MapViewModel] Found ${_savedGeofences.length} saved geofences',
      );

      if (isMapReady && mapboxMap != null) {
        await _displaySavedGeofences();
      }

      if (forceNativeRecreation) {
        debugPrint('[MapViewModel] Recreating geofences in native service...');
        // Recreate geofences in the native service
        for (final geofence in _savedGeofences) {
          try {
            final point = Point(
              coordinates: Position(geofence.longitude, geofence.latitude),
            );

            // Ensure geofencing service is initialized before creating geofences
            // It might be better to have _geofencingService.init() called once
            // explicitly, perhaps in onMapCreated or even earlier if possible.
            // For now, createGeofence handles its own initialization if needed.

            await _geofencingService.createGeofence(
              geometry: point,
              radiusMeters: geofence.radiusMeters,
              customId: geofence.id,
              fillColor:
                  _parseColor(geofence.fillColor) ??
                  Colors.transparent, // Use parsed color
              fillOpacity: geofence.fillOpacity,
              strokeColor:
                  _parseColor(geofence.strokeColor) ??
                  Colors.transparent, // Use parsed color
              strokeWidth: geofence.strokeWidth,
            );
            debugPrint(
              '[MapViewModel] Recreated geofence in native service: ${geofence.id}',
            );
          } catch (e, stackTrace) {
            debugPrint(
              '[MapViewModel] Error recreating geofence ${geofence.id} in native service: $e\\n$stackTrace',
            );
            // Optionally, collect these errors or rethrow if critical
          }
        }
        debugPrint('[MapViewModel] Finished recreating native geofences.');
      }
    } catch (e, stackTrace) {
      debugPrint(
        '[MapViewModel] Error loading saved geofences: $e\\n$stackTrace',
      );
      mapInitializationError = "Error loading geofences: ${e.toString()}";
      notifyListeners(); // Notify to update UI with error
    }
  }

  Future<void> _displaySavedGeofences() async {
    try {
      debugPrint('Displaying ${_savedGeofences.length} saved geofences');

      if (geofenceZoneSymbol == null || mapboxMap == null) {
        debugPrint(
          'Geofence zone symbol manager or mapboxMap is null, cannot display geofences',
        );
        return;
      }

      // Clear existing geofences
      debugPrint('Clearing existing geofence annotations...');
      await geofenceZoneSymbol!.deleteAll();
      geofenceZoneSymbolIds.clear();

      // Get the meters-to-pixels conversion factor once
      //BUG: metersPerPixel is wrong
      final double metersPerPixel =
          await metersToPixelsAtCurrentLocationAndZoom();
      debugPrint("[MapViewModel] Line 124 Meters per pixel: $metersPerPixel");
      if (metersPerPixel == 0.0) {
        debugPrint(
          "Could not calculate meters per pixel. Aborting geofence display.",
        );
        return;
      }

      // Add all saved geofences
      for (final geofence in _savedGeofences) {
        try {
          debugPrint(
            'Adding geofence ${geofence.id} at ${geofence.latitude}, ${geofence.longitude}',
          );

          final point = Point(
            coordinates: Position(geofence.longitude, geofence.latitude),
          );

          // Parse colors with error handling
          final fillColor = _parseColor(geofence.fillColor);
          final strokeColor = _parseColor(geofence.strokeColor);

          if (fillColor == null || strokeColor == null) {
            debugPrint('Invalid color format for geofence ${geofence.id}');
            continue;
          }

          // Calculate radius in pixels using the fetched conversion factor
          final radiusInPixels = geofence.radiusMeters / metersPerPixel;
          debugPrint(
            "[MapViewModel] Line 154 Radius in pixels: $radiusInPixels for ${geofence.radiusMeters}m",
          );

          final annotation = await geofenceZoneSymbol!.create(
            CircleAnnotationOptions(
              geometry: point,
              circleRadius: radiusInPixels,
              circleColor: fillColor.value,
              circleOpacity: geofence.fillOpacity,
              circleStrokeColor: strokeColor.value,
              circleStrokeWidth: geofence.strokeWidth,
            ),
          );

          geofenceZoneSymbolIds.add(annotation);
          debugPrint('Added geofence ${geofence.id} to map');
        } catch (e, stackTrace) {
          debugPrint(
            'Error displaying geofence ${geofence.id}: $e\n$stackTrace',
          );
        }
      }
      debugPrint(
        'Finished displaying ${_savedGeofences.length} geofences with ${geofenceZoneSymbolIds.length} symbols.',
      );
    } catch (e, stackTrace) {
      debugPrint('Error in _displaySavedGeofences: $e\n$stackTrace');
    }
  }

  Color? _parseColor(String colorString) {
    try {
      // Handle both hex with and without alpha
      if (colorString.startsWith('0x')) {
        return Color(int.parse(colorString));
      } else if (colorString.startsWith('#')) {
        return Color(
          int.parse(colorString.substring(1), radix: 16) + 0xFF000000,
        );
      } else if (colorString.length == 6 || colorString.length == 8) {
        // Handle hex without 0x or # prefix
        return Color(
          int.parse(colorString, radix: 16) +
              (colorString.length == 6 ? 0xFF000000 : 0),
        );
      }
      return null;
    } catch (e) {
      debugPrint('Error parsing color "$colorString": $e');
      return null;
    }
  }

  void _showError(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _showSuccess(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void startDebugLogging() {
    _debugTimer?.cancel(); // Cancel any existing timer
    _debugTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      // debugPrint("Current helper pixel radius: $_currentHelperRadiusInPixels");
    });
  }

  void stopDebugLogging() {
    _debugTimer?.cancel();
  }

  onMapCreated(MapboxMap mapboxMap) async {
    debugPrint("[MapViewModel] onMapCreated started.");
    mapInitializationError = null; // Clear previous errors
    try {
      this.mapboxMap = mapboxMap;

      geofenceZoneHelper =
          await mapboxMap.annotations.createCircleAnnotationManager();
      debugPrint("[MapViewModel] CircleAnnotationManager for helper created.");
      geofenceZoneSymbol =
          await mapboxMap.annotations.createCircleAnnotationManager();
      debugPrint("[MapViewModel] CircleAnnotationManager for symbols created.");

      await mapboxMap.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
          showAccuracyRing: true,
          puckBearingEnabled: true,
        ),
      );
      debugPrint("[MapViewModel] LocationComponentSettings updated.");

      locator.Position? userPosition;
      try {
        debugPrint("[MapViewModel] Attempting to get current location...");
        userPosition = await _locationService.getCurrentLocation();
        debugPrint(
          "[MapViewModel] Current location obtained: ${userPosition.latitude}, ${userPosition.longitude}",
        );
      } catch (e) {
        debugPrint("[MapViewModel] Error getting current location: $e");
        mapInitializationError =
            "Failed to get current location: ${e.toString()}. Please ensure location services are enabled and permissions granted.";
        // Do not proceed with flyTo if userPosition is null
      }

      if (userPosition != null) {
        debugPrint(
          "[MapViewModel] Flying to user location: ${userPosition.longitude}, ${userPosition.latitude}",
        );
        await this.mapboxMap!.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(
                userPosition.longitude,
                userPosition.latitude,
              ),
            ),
            zoom: 16, // Adjusted default zoom
            bearing: 0,
            pitch: 0,
          ),
          MapAnimationOptions(duration: 1500),
        );
        debugPrint("[MapViewModel] Flew to user location.");
      } else {
        debugPrint(
          "[MapViewModel] User position is null, cannot flyTo. Centering on a default location or doing nothing.",
        );
        // Optionally, center the map on a default location if userPosition is null
        // await this.mapboxMap!.flyTo(
        //   CameraOptions(
        //     center: Point(coordinates: Position(0,0)).toJson(), // Default fallback
        //     zoom: 2,
        //   ),
        //   MapAnimationOptions(duration: 1000),
        // );
      }

      isMapReady = true;
      debugPrint("[MapViewModel] Map is ready. Notifying listeners.");
      notifyListeners(); // Notify that map is ready, UI can update (e.g. hide loading indicator for map itself)

      // Load saved geofences and recreate native ones after map is ready and initial view is set.
      debugPrint(
        "[MapViewModel] Proceeding to load saved geofences post map setup.",
      );
      await _loadSavedGeofences(
        forceNativeRecreation: true,
      ); // Await this critical step

      if (mapInitializationError != null) {
        debugPrint(
          "[MapViewModel] An error occurred during _loadSavedGeofences: $mapInitializationError",
        );
      }

      // Calculate initial helper radius once map is ready
      // This should ideally use the actual map center after flyTo or a default if flyTo didn't happen.

      debugPrint("[MapViewModel] onMapCreated finished.");
    } catch (e, stackTrace) {
      debugPrint(
        "[MapViewModel] CRITICAL Error in onMapCreated: $e\\n$stackTrace",
      );
      mapInitializationError = "Map initialization failed: ${e.toString()}";
      isMapReady = false; // Explicitly set to false on critical error
    } finally {
      // Notify listeners regardless of success or failure to update UI
      // (e.g. to show mapInitializationError if any)
      notifyListeners();
    }
  }

  onCameraIdle(MapIdleEventData eventData) async {
    try {
      debugPrint("[MapViewModel] Camera idle event triggered.");
      if (this.mapboxMap != null) {
        // Check mapboxMap again as it's used
        final cameraState = await this.mapboxMap!.getCameraState();
        //BUG: Incorrect Lat
        final centerLat = cameraState.center.coordinates.lat;
        //BUG: Incorrect zoom
        double zoomLevel = cameraState.zoom;
        debugPrint(
          "[MapViewModel]Line 339 Initial center lat: $centerLat, zoom level: $zoomLevel",
        );
        final metersPerPixel = await this.mapboxMap!.projection
            .getMetersPerPixelAtLatitude(centerLat.toDouble(), zoomLevel);
        debugPrint("[MapViewModel] Line 338 meters per Pixel: $metersPerPixel");
        if (metersPerPixel > 0) {
          _currentHelperRadiusInPixels =
              _helperTargetRadiusMeters / metersPerPixel;
          debugPrint(
            "[MapViewModel] Initial helper radius calculated: $_currentHelperRadiusInPixels px for $_helperTargetRadiusMeters m at $centerLat, zoom $zoomLevel",
          );
        } else {
          debugPrint(
            "[MapViewModel] Could not calculate initial helper radius, metersPerPixel was 0 or less.",
          );
        }
      }
      cameraState = await mapboxMap!.getCameraState();
      await updateAllGeofenceVisualRadii();
      notifyListeners(); // Notify listeners to update UI if needed
    } catch (e) {
      debugPrint("[MapViewModel] Error in onCameraIdle: $e");
    }
  }

  onLongTap(MapContentGestureContext context) async {
    try {
      selectedPoint = context.point;
      latitude = context.point.coordinates.lat;
      longitude = context.point.coordinates.lng;

      debugPrint(
        "Creating GF Helper with Radius in Pix: $_currentHelperRadiusInPixels",
      );

      if (geofenceZoneHelper != null) {
        await geofenceZoneHelper!.deleteAll();
        geofenceZoneHelperIds.clear();

        final annotation = await geofenceZoneHelper!.create(
          CircleAnnotationOptions(
            geometry: context.point,
            circleRadius: _currentHelperRadiusInPixels,
            circleColor: Colors.lightBlue.toARGB32(),
            circleOpacity: 0.2,
            circleStrokeColor: Colors.black.toARGB32(),
            circleStrokeWidth: 1.0,
          ),
        );

        geofenceZoneHelperIds.add(annotation);
        isGeofenceHelperPlaced = true; // Mark the helper as placed
        debugPrint(
          "Geofence helper placed with radius in pixels: $_currentHelperRadiusInPixels",
        );
        notifyListeners();
      } else {
        debugPrint("Geofence zone helper is not yet initialized.");
      }
    } catch (e) {
      debugPrint("Error in onLongTap: $e");
    }
  }

  Future<double> currentZoomLevel() {
    if (mapboxMap == null) {
      debugPrint("MapboxMap is null");
      throw StateError("Error: MapboxMap not yet intialized.");
    }
    return mapboxMap!.getCameraState().then((cameraState) {
      return cameraState.zoom;
    });
  }

  onZoom(MapContentGestureContext context) async {
    try {
      startDebugLogging();
      latitude = context.point.coordinates.lat;

      final cameraState = await mapboxMap?.getCameraState();
      final centerLat = cameraState?.center.coordinates.lat;

      if (centerLat == null && latitude == null) {
        debugPrint(
          "Cannot calculate metersToPixels for zoom: latitude is null",
        );
        return;
      }

      final latForCalc = centerLat ?? latitude!;

      double radiusInMeters = 50;

      double currentMetersPerPixel = await mapboxMap!.projection
          .getMetersPerPixelAtLatitude(
            latForCalc.toDouble(),
            await currentZoomLevel(),
          );
      debugPrint("Current meters per pixel: $currentMetersPerPixel");

      if (currentMetersPerPixel == 0.0) {
        debugPrint(
          "Meters per pixel is 0.0, cannot calculate circle radius in pixels.",
        );
        return;
      }

      _currentHelperRadiusInPixels = radiusInMeters / currentMetersPerPixel;
      debugPrint(
        "Calculated geofenceHelperRadiusInPixels for 50m: $_currentHelperRadiusInPixels",
      );

      if (geofenceZoneHelper != null || geofenceZoneSymbol != null) {
        updateAllGeofenceVisualRadii();
        notifyListeners();
      } else {
        debugPrint("Geofence zone helper is not yet initialized.");
      }
    } catch (e) {
      debugPrint("Error in onZoom: $e");
    }
  }

  Future<void> updateAllGeofenceVisualRadii() async {
    if (mapboxMap == null) return;
    debugPrint("Updating all geofence visual radii due to zoom/map change.");

    final double metersPerPixel =
        await metersToPixelsAtCurrentLocationAndZoom();
    if (metersPerPixel == 0.0) {
      debugPrint("Cannot update radii: metersPerPixel is 0.");
      return;
    }

    List<Future> futures = [];

    // Update active helper if it's placed
    if (geofenceZoneHelper != null && geofenceZoneHelperIds.isNotEmpty) {
      _currentHelperRadiusInPixels = _helperTargetRadiusMeters / metersPerPixel;
      for (final annotation in geofenceZoneHelperIds) {
        // Should only be one helper
        annotation.circleRadius = _currentHelperRadiusInPixels;
        futures.add(geofenceZoneHelper!.update(annotation));
        debugPrint(
          "Updating helper to: $_currentHelperRadiusInPixels px for ${_helperTargetRadiusMeters}m",
        );
      }
    }

    // Update actual saved geofence symbols
    if (geofenceZoneSymbol != null &&
        _savedGeofences.isNotEmpty &&
        geofenceZoneSymbolIds.length == _savedGeofences.length) {
      for (int i = 0; i < _savedGeofences.length; i++) {
        final geofenceData = _savedGeofences[i];
        final annotation =
            geofenceZoneSymbolIds[i]; // Assuming lists are in sync
        annotation.circleRadius = geofenceData.radiusMeters / metersPerPixel;
        futures.add(geofenceZoneSymbol!.update(annotation));
      }
    } else if (geofenceZoneSymbol != null && _savedGeofences.isNotEmpty) {
      // Fallback: if lists are not in sync (should not happen ideally), re-display all from scratch.
      // This can happen if deleteAll was called on manager but local list not cleared, or vice-versa.
      debugPrint(
        "Mismatch between savedGeofences and geofenceZoneSymbolIds or one is empty. Re-displaying all.",
      );
      await _displaySavedGeofences();
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  Future<double> metersToPixelsAtCurrentLocationAndZoom() async {
    if (mapboxMap == null) {
      debugPrint(
        "MapboxMap not initialized in metersToPixelsAtCurrentLocationAndZoom",
      );
      return 0.0;
    }
    try {
      final cameraState = await mapboxMap!.getCameraState();
      final centerLat = cameraState.center.coordinates.lat;
      double zoomLevel = cameraState.zoom;

      debugPrint("METERS TO PIX lat_long:$centerLat, at zoom:$zoomLevel");
      return mapboxMap!.projection.getMetersPerPixelAtLatitude(
        centerLat.toDouble(),
        zoomLevel,
      );
    } catch (e) {
      debugPrint("Error in metersToPixelsAtCurrentLocationAndZoom: $e");
      return 0.0;
    }
  }

  Future<void> createGeofenceAtSelectedPoint(
    BuildContext context, {
    required String taskName,
  }) async {
    if (selectedPoint == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No point selected to create a geofence.'),
          ),
        );
      }
      return;
    }

    try {
      debugPrint('Creating geofence at ${selectedPoint!.coordinates}');

      // Generate a unique ID for the geofence
      final geofenceId = 'geofence_${DateTime.now().millisecondsSinceEpoch}';

      // Create the geofence data object
      final geofenceData = GeofenceData(
        id: geofenceId,
        latitude: selectedPoint!.coordinates.lat.toDouble(),
        longitude: selectedPoint!.coordinates.lng.toDouble(),
        radiusMeters: _helperTargetRadiusMeters,
        fillColor: Colors.amberAccent.value.toRadixString(16).padLeft(8, '0'),
        fillOpacity: 0.5,
        strokeColor: Colors.white.value.toRadixString(16).padLeft(8, '0'),
        strokeWidth: 2.0,
        task: taskName,
      );
      debugPrint(
        "[MapViewModel] GeofenceData to be saved: ${geofenceData.toJson()}",
      );

      // Save to database
      debugPrint('Saving geofence to database...');
      await _geofenceStorage.saveGeofence(geofenceData);
      debugPrint('Geofence saved to database');

      // Add to local list
      _savedGeofences.add(geofenceData);

      // Create the geofence in the native service
      debugPrint('Creating geofence in native service...');
      await _geofencingService.createGeofence(
        geometry: selectedPoint!,
        radiusMeters: _helperTargetRadiusMeters,
        customId: geofenceId,
        fillColor: Colors.amberAccent,
        fillOpacity: 0.5,
        strokeColor: Colors.white,
        strokeWidth: 2.0,
      );
      debugPrint('Geofence created in native service');

      // Clear the helper circle if it exists
      if (geofenceZoneHelper != null) {
        debugPrint('Clearing geofence zone helper');
        await geofenceZoneHelper!.deleteAll();
      }

      // Clear the selection
      selectedPoint = null;
      isGeofenceHelperPlaced = false;

      // Refresh the display
      if (mapboxMap != null) {
        debugPrint('Refreshing geofence display...');
        await _displaySavedGeofences();
      }

      // Show success message
      if (context.mounted) {
        _showSuccess(context, 'Geofence created successfully!');
      }

      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('Error creating geofence: $e\n$stackTrace');
      if (context.mounted) {
        _showError(context, 'Failed to create geofence: ${e.toString()}');
      }
    }
  }

  Future<void> displayExistingGeofence(Point point, double radiusMeters) async {
    if (mapboxMap == null ||
        geofenceZoneHelper == null ||
        geofenceZoneSymbol == null) {
      debugPrint(
        "Map, helper, or symbol manager not ready in displayExistingGeofence",
      );
      return;
    }

    // Update selectedPoint for the view model to know the current geofence center
    selectedPoint = point;
    latitude = point.coordinates.lat;
    longitude = point.coordinates.lng;

    // Calculate radius in pixels for the current zoom level
    final metersPerPixel = await metersToPixelsAtCurrentLocationAndZoom();
    if (metersPerPixel == 0.0) {
      debugPrint("Cannot display existing geofence: metersPerPixel is 0.");
      return;
    }
    _currentHelperRadiusInPixels = radiusMeters / metersPerPixel;

    // Clear any existing helper annotation
    await geofenceZoneHelper!.deleteAll();
    geofenceZoneHelperIds.clear();

    // Create the helper annotation at the geofence location
    final helperAnnotation = await geofenceZoneHelper!.create(
      CircleAnnotationOptions(
        geometry: point,
        circleRadius: _currentHelperRadiusInPixels,
        circleColor: Colors.lightBlue.toARGB32(),
        circleOpacity: 0.2,
        circleStrokeColor: Colors.black.toARGB32(),
        circleStrokeWidth: 1.0,
      ),
    );
    geofenceZoneHelperIds.add(helperAnnotation);
    isGeofenceHelperPlaced = true;

    // Also, ensure the persistent symbol for this geofence would be displayed correctly.
    // _displaySavedGeofences will handle drawing all persistent symbols,
    // but we need to ensure the helper reflects the one being edited.
    // No, _displaySavedGeofences shows ALL. For an edit view, we might want to show only the one being edited,
    // or highlight it. For now, the helper represents the editable area.
    // The persistent ones are handled by _loadSavedGeofences -> _displaySavedGeofences
    // which is fine, as the edit view will have its own map and won't call _displaySavedGeofences for *all* geofences.

    debugPrint(
      "Helper for existing geofence placed at ${point.coordinates} with radius ${_currentHelperRadiusInPixels}px for ${radiusMeters}m",
    );
    notifyListeners();
  }

  CircleAnnotationManager? getGeofenceZonePicker() => geofenceZoneHelper;
  CircleAnnotationManager? getGeofenceZoneSymbol() => geofenceZoneSymbol;

  @override
  void dispose() {
    // Stop any running timers
    _debugTimer?.cancel();
    _debugTimer = null;

    // Dispose of the geofencing service
    _geofencingService.dispose();

    // Clear any resources
    geofenceZoneHelper = null;
    geofenceZoneSymbol = null;
    mapboxMap = null;

    super.dispose();
  }
}

// Helper extension for color conversion if not available elsewhere
extension _ColorUtil on Color {
  int toARGB32() => value;
}
