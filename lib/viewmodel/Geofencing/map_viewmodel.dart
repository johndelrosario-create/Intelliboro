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
  // Get the singleton instance of the GeofencingService
  final GeofencingService _geofencingService = GeofencingService();

  MapboxMap? mapboxMap;
  bool isMapReady = false;
  bool _isCreatingGeofence = false; // Add state tracking
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
    // Register this view model with the singleton service
    _geofencingService.registerMapViewModel(this);
    // Ensure the service is initialized. It has internal guards to run only once.
    _geofencingService.init();
  }

  Future<void> _loadSavedGeofences({bool forceNativeRecreation = false}) async {
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

      // Only recreate native geofences if explicitly requested
      if (forceNativeRecreation) {
        debugPrint('[MapViewModel] Recreating geofences in native service...');
        // Recreate geofences in the native service
        for (final geofence in _savedGeofences) {
          try {
            final point = Point(
              coordinates: Position(geofence.longitude, geofence.latitude),
            );

            await _geofencingService.createGeofence(
              geometry: point,
              radiusMeters: geofence.radiusMeters,
              customId: geofence.id,
              fillColor: _parseColor(geofence.fillColor) ?? Colors.transparent,
              fillOpacity: geofence.fillOpacity,
              strokeColor:
                  _parseColor(geofence.strokeColor) ?? Colors.transparent,
              strokeWidth: geofence.strokeWidth,
            );
            debugPrint(
              '[MapViewModel] Recreated geofence in native service: ${geofence.id}',
            );
          } catch (e, stackTrace) {
            debugPrint(
              'Error recreating native geofence ${geofence.id}: $e\n$stackTrace',
            );
          }
        }
        debugPrint('[MapViewModel] Finished recreating native geofences.');
      }

      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('Error in _loadSavedGeofences: $e\n$stackTrace');
      mapInitializationError = e.toString();
      notifyListeners();
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

  Future<void> onMapCreated(MapboxMap mapboxMap) async {
    debugPrint('[MapViewModel] onMapCreated called.');
    this.mapboxMap = mapboxMap;

    try {
      // Create annotation managers if they don't exist
      if (geofenceZoneHelper == null) {
        geofenceZoneHelper =
            await mapboxMap.annotations.createCircleAnnotationManager();
        debugPrint('[MapViewModel] Created geofence zone helper manager');
      }

      if (geofenceZoneSymbol == null) {
        geofenceZoneSymbol =
            await mapboxMap.annotations.createCircleAnnotationManager();
        debugPrint('[MapViewModel] Created geofence zone symbol manager');
      }

      // Enable location component
      await mapboxMap.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
          showAccuracyRing: true,
          puckBearingEnabled: true,
        ),
      );
      debugPrint('[MapViewModel] Location component enabled');

      // Get user's current location
      locator.Position? userPosition;
      try {
        debugPrint('[MapViewModel] Getting current location...');
        userPosition = await _locationService.getCurrentLocation();
        debugPrint(
          '[MapViewModel] Current location: ${userPosition.latitude}, ${userPosition.longitude}',
        );
      } catch (e) {
        debugPrint('[MapViewModel] Error getting location: $e');
        mapInitializationError =
            'Failed to get current location: $e. Please ensure location services are enabled and permissions granted.';
      }

      // Fly to user's location if available
      if (userPosition != null) {
        debugPrint('[MapViewModel] Flying to user location');
        await mapboxMap.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(
                userPosition.longitude,
                userPosition.latitude,
              ),
            ),
            zoom: 16,
            bearing: 0,
            pitch: 0,
          ),
          MapAnimationOptions(duration: 1500),
        );
        debugPrint('[MapViewModel] Camera moved to user location');
      }

      isMapReady = true;
      debugPrint('[MapViewModel] Map is ready');

      // Load and display saved geofences (visually only, don't recreate native geofences)
      await _loadSavedGeofences(forceNativeRecreation: false);

      debugPrint('[MapViewModel] onMapCreated finished.');
    } catch (e, stackTrace) {
      debugPrint('Error in onMapCreated: $e\n$stackTrace');
      mapInitializationError = e.toString();
    }
    notifyListeners();
  }

  onCameraIdle(MapIdleEventData eventData) async {
    try {
      debugPrint("[MapViewModel] Camera idle event triggered.");
      if (this.mapboxMap != null) {
        final cameraState = await mapboxMap!.getCameraState();
        final centerLat = cameraState.center.coordinates.lat;
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
            "[MapViewModel] onCameraIdle: Helper radius updated to: $_currentHelperRadiusInPixels px for $_helperTargetRadiusMeters m (lat: $centerLat, zoom: $zoomLevel)",
          );
        } else {
          debugPrint(
            "[MapViewModel] Could not calculate initial helper radius, metersPerPixel was 0 or less.",
          );
        }
      }
      await updateAllGeofenceVisualRadii();
      notifyListeners(); // Notify listeners to update UI if needed
    } catch (e) {
      debugPrint("[MapViewModel] Error in onCameraIdle: $e");
    }
  }

  Future<void> _displaySavedGeofences() async {
    try {
      debugPrint(
        '[MapViewModel] Displaying ${_savedGeofences.length} saved geofences',
      );

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

          final annotation = await geofenceZoneSymbol!.create(
            CircleAnnotationOptions(
              geometry: point,
              circleRadius: _currentHelperRadiusInPixels,
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
    if (_isCreatingGeofence) {
      debugPrint('Already creating a geofence, ignoring duplicate request');
      return;
    }

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

    _isCreatingGeofence = true;
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

      // Save to database first
      debugPrint('Saving geofence to database...');
      await _geofenceStorage.saveGeofence(geofenceData);
      debugPrint('Geofence saved to database');

      // Add to local list
      _savedGeofences.add(geofenceData);

      // Clear the helper circle if it exists - do this before creating native geofence
      if (geofenceZoneHelper != null) {
        debugPrint('Clearing geofence zone helper');
        await geofenceZoneHelper!.deleteAll();
        geofenceZoneHelperIds.clear();
      }

      // Clear the selection
      selectedPoint = null;
      isGeofenceHelperPlaced = false;

      // Notify UI of visual changes before heavy operation
      notifyListeners();

      // Create the geofence in the native service
      debugPrint('Creating geofence in native service...');
      await _geofencingService.createGeofence(
        geometry: Point(
          coordinates: Position(geofenceData.longitude, geofenceData.latitude),
        ),
        radiusMeters: _helperTargetRadiusMeters,
        customId: geofenceId,
        fillColor: Colors.amberAccent,
        fillOpacity: 0.5,
        strokeColor: Colors.white,
        strokeWidth: 2.0,
      );
      debugPrint('Geofence created in native service');

      // Refresh the display
      if (mapboxMap != null && !_isDisposed) {
        debugPrint('Refreshing geofence display...');
        await _displaySavedGeofences();
      }

      // Show success message
      if (context.mounted && !_isDisposed) {
        _showSuccess(context, 'Geofence created successfully!');
      }

      if (!_isDisposed) {
        notifyListeners();
      }
    } catch (e, stackTrace) {
      debugPrint('Error creating geofence: $e\n$stackTrace');
      if (context.mounted && !_isDisposed) {
        _showError(context, 'Failed to create geofence: ${e.toString()}');
      }
    } finally {
      _isCreatingGeofence = false;
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

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;

    // Stop any running timers
    _debugTimer?.cancel();
    _debugTimer = null;

    // IMPORTANT: Do NOT dispose the singleton geofencing service here.
    // Instead, unregister this view model so the service knows not to use it.
    _geofencingService.unregisterMapViewModel();

    // Clear any resources held by this specific view model
    geofenceZoneHelper?.deleteAll().then((_) {
      geofenceZoneHelper = null;
    });
    geofenceZoneSymbol?.deleteAll().then((_) {
      geofenceZoneSymbol = null;
    });
    mapboxMap = null;

    super.dispose();
  }
}

// Helper extension for color conversion if not available elsewhere
extension _ColorUtil on Color {
  int toARGB32() => value;
}
