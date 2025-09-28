import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intelliboro/services/geofencing_service.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as locator;
import 'package:intelliboro/services/location_service.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/services/offline_map_service.dart';
import 'package:intelliboro/repository/task_repository.dart';
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

  // Real-time location tracking
  StreamSubscription<locator.Position>? _locationStreamSubscription;
  bool _isLocationTrackingActive = false;

  // Pending/selected radius in meters for the helper circle (adjustable via UI).
  double pendingRadiusMeters = 50.0;
  // Padding to avoid edge-touch glitches when checking overlaps (in meters).
  static const double _overlapPaddingMeters = 0.2;
  // When editing an existing geofence, hold its id to exclude it from overlap checks.
  String? _editingGeofenceId;
  // This will store the calculated pixel radius for the helper, updated on zoom/tap.
  double _currentHelperRadiusInPixels =
      30.0; // Initial fallback if map not ready for calc.

  List<CircleAnnotation> geofenceZoneHelperIds = [];
  List<CircleAnnotation> geofenceZoneSymbolIds =
      []; // These are for the actual saved geofences
  bool isGeofenceHelperPlaced = false;
  bool _initialDisplayPending = false; // wait for camera idle before first draw

  Timer? _debugTimer;
  final GeofenceStorage _geofenceStorage = GeofenceStorage();
  List<GeofenceData> _savedGeofences = [];
  String? mapInitializationError; // To store any error message during map setup

  // Expose saved geofences for UI (read-only list)
  List<GeofenceData> get savedGeofences => List.unmodifiable(_savedGeofences);
  bool get isEditing => _editingGeofenceId != null;
  String? get editingGeofenceId => _editingGeofenceId;
  GeofenceData? get editingGeofence =>
      _editingGeofenceId == null
          ? null
          : _savedGeofences.firstWhere(
            (g) => g.id == _editingGeofenceId,
            orElse:
                () => GeofenceData(
                  id: _editingGeofenceId!,
                  latitude: latitude?.toDouble() ?? 0,
                  longitude: longitude?.toDouble() ?? 0,
                  radiusMeters: pendingRadiusMeters,
                  fillColor: Colors.amberAccent.value
                      .toRadixString(16)
                      .padLeft(8, '0'),
                  fillOpacity: 0.5,
                  strokeColor: Colors.white.value
                      .toRadixString(16)
                      .padLeft(8, '0'),
                  strokeWidth: 2.0,
                  task: null,
                ),
          );

  /// Clears the currently selected point and removes the helper geofence circle from the map.
  /// This also resets the geofence helper placement state.
  Future<void> clearSelectedPoint() async {
    selectedPoint = null;
    latitude = null;
    longitude = null;
    isGeofenceHelperPlaced = false;

    // Clear any existing helper annotation
    if (geofenceZoneHelper != null) {
      await geofenceZoneHelper!.deleteAll();
      geofenceZoneHelperIds.clear();
    }

    notifyListeners();
  }

  MapboxMapViewModel() : _locationService = LocationService() {
    // Register this view model with the singleton service
    _geofencingService.registerMapViewModel(this);
    // Ensure the service is initialized. It has internal guards to run only once.
    _geofencingService.init();
  }

  // Public method to force reload of saved geofences and redraw
  Future<void> refreshSavedGeofences() async {
    await _loadSavedGeofences(forceNativeRecreation: false);
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
    mapInitializationError = null;

    // Mark map as ready early so UI can hide the spinner. Remaining setup
    // tasks are executed in the background and errors are logged but do not
    // prevent the map from being displayed.
    try {
      isMapReady = true;
      debugPrint('[MapViewModel] Map marked ready (early).');
      notifyListeners();

      // Run remaining initialization without blocking the UI.
      () async {
        try {
          await OfflineMapService().init(
            styleUri: 'mapbox://styles/mapbox/streets-v12',
          );
          // Kick off home region caching in background
          // ignore: unawaited_futures
          OfflineMapService().ensureHomeRegion();
        } catch (e) {
          debugPrint('[MapViewModel] OfflineMapService init error: $e');
        }

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
        } catch (e, st) {
          debugPrint('[MapViewModel] Annotation managers init error: $e\n$st');
        }

        try {
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
        } catch (e) {
          debugPrint('[MapViewModel] Location component enable error: $e');
        }

        // Get user's current location
        locator.Position? userPosition;
        try {
          debugPrint('[MapViewModel] Getting current location...');
          userPosition = await _locationService.getCurrentLocation();
          debugPrint(
            '[MapViewModel] Current location: ${userPosition.latitude}, ${userPosition.longitude}',
          );
        } catch (e) {
          debugPrint('[MapViewModel] Error getting current location: $e');
          // Try to get last known location for offline scenarios
          try {
            debugPrint(
              '[MapViewModel] Attempting to get last known location for offline use...',
            );
            userPosition = await _locationService.getLastKnownLocation();
            if (userPosition != null) {
              debugPrint(
                '[MapViewModel] Got cached/last known location: ${userPosition.latitude}, ${userPosition.longitude}',
              );
            } else {
              debugPrint('[MapViewModel] No cached location available');
              mapInitializationError =
                  'Unable to get location: $e. Please ensure location services are enabled and try again when online.';
              notifyListeners();
            }
          } catch (cacheError) {
            debugPrint(
              '[MapViewModel] Error getting cached location: $cacheError',
            );
            mapInitializationError =
                'Failed to get current location: $e. Please ensure location services are enabled and permissions granted.';
            notifyListeners();
          }
        }

        try {
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
            debugPrint(
              '[MapViewModel] Camera moved to user location successfully',
            );
          } else {
            debugPrint(
              '[MapViewModel] No user location available for flyTo operation',
            );
          }
        } catch (e) {
          debugPrint('[MapViewModel] FlyTo error: $e');
          // Don't set mapInitializationError here as the map can still function without flyTo
        }

        // Defer initial display until camera is idle so zoom is final
        _initialDisplayPending = true;

        debugPrint('[MapViewModel] Background onMapCreated setup finished.');

        // Start real-time location tracking for smooth offline location updates
        await _startLocationTracking();

        // Fallback: if camera idle doesn't trigger promptly, ensure we render once
        // with the current camera center/zoom so sizes are accurate enough.
        Future.delayed(const Duration(milliseconds: 600), () async {
          if (_initialDisplayPending && isMapReady && !_isDisposed) {
            debugPrint('[MapViewModel] Fallback initial display after delay.');
            _initialDisplayPending = false;
            await _loadSavedGeofences(forceNativeRecreation: false);
          }
        });
      }();
    } catch (e, stackTrace) {
      debugPrint('Error in onMapCreated outer: $e\n$stackTrace');
      mapInitializationError = e.toString();
      notifyListeners();
    }
  }

  /// Start real-time location tracking for smooth offline/online location updates
  Future<void> _startLocationTracking() async {
    if (_isLocationTrackingActive || _locationStreamSubscription != null) {
      debugPrint('[MapViewModel] Location tracking already active');
      return;
    }

    try {
      // Check if real-time tracking is available
      final isAvailable = await _locationService.isRealTimeTrackingAvailable();
      if (!isAvailable) {
        debugPrint('[MapViewModel] Real-time location tracking not available');
        return;
      }

      // Start the location service tracking
      await _locationService.startLocationTracking();

      // Listen to location updates
      _locationStreamSubscription = _locationService.locationStream.listen(
        (locator.Position position) {
          debugPrint(
            '[MapViewModel] Received location update: ${position.latitude}, ${position.longitude}',
          );

          // Update the map's location component with new position
          _updateMapLocationComponent(position);

          // Optionally notify listeners for UI updates
          notifyListeners();
        },
        onError: (error) {
          debugPrint('[MapViewModel] Location stream error: $error');
        },
      );

      _isLocationTrackingActive = true;
      debugPrint('[MapViewModel] Real-time location tracking started');
    } catch (e) {
      debugPrint('[MapViewModel] Error starting location tracking: $e');
    }
  }

  /// Update the map's location component with new position
  /// This ensures smooth location updates even when offline
  Future<void> _updateMapLocationComponent(locator.Position position) async {
    if (mapboxMap == null) return;

    try {
      // The Mapbox location component should automatically update if it's enabled
      // and receiving location updates from the system. We just ensure it stays enabled.

      // Update our internal location state
      latitude = position.latitude;
      longitude = position.longitude;

      debugPrint(
        '[MapViewModel] Location component updated with position: ${position.latitude}, ${position.longitude}',
      );
    } catch (e) {
      debugPrint('[MapViewModel] Error updating location component: $e');
    }
  }

  /// Stop real-time location tracking
  Future<void> _stopLocationTracking() async {
    if (_locationStreamSubscription != null) {
      await _locationStreamSubscription!.cancel();
      _locationStreamSubscription = null;
    }

    await _locationService.stopLocationTracking();
    _isLocationTrackingActive = false;
    debugPrint('[MapViewModel] Location tracking stopped');
  }

  /// Check if location tracking is currently active
  bool get isLocationTrackingActive => _isLocationTrackingActive;

  /// Restart location tracking (useful for refreshing location services)
  Future<void> restartLocationTracking() async {
    debugPrint('[MapViewModel] Restarting location tracking...');
    await _stopLocationTracking();
    await _startLocationTracking();
  }

  // Update pending radius from UI slider and refresh helper circle. Auto-adjust center if needed.
  Future<void> setPendingRadius(double meters) async {
    pendingRadiusMeters = meters.clamp(1.0, 1000.0);
    // Use the helper's own latitude for accurate visual radius
    final lat = selectedPoint?.coordinates.lat.toDouble();

    // Use consistent calculation method with existing geofences
    double mpp = 0.0;
    if (lat != null && mapboxMap != null) {
      final zoomLevel = await currentZoomLevel();
      mpp = await mapboxMap!.projection.getMetersPerPixelAtLatitude(
        lat,
        zoomLevel,
      );
    }

    // Fallback to camera-center method if geofence-specific calculation fails
    if (mpp <= 0) {
      mpp = await metersToPixelsAtCurrentLocationAndZoom(latitudeOverride: lat);
    }

    if (mpp > 0) {
      _currentHelperRadiusInPixels = pendingRadiusMeters / mpp;
    }

    if (selectedPoint != null) {
      // Auto-adjust to avoid overlaps for the new radius
      selectedPoint = await _autoAdjustCenter(
        selectedPoint!,
        pendingRadiusMeters,
        excludeId: _editingGeofenceId,
      );
      // Update helper geometry
      if (geofenceZoneHelper != null && geofenceZoneHelperIds.isNotEmpty) {
        final a = geofenceZoneHelperIds.first;
        a.geometry = selectedPoint!;
        a.circleRadius = _currentHelperRadiusInPixels;
        await geofenceZoneHelper!.update(a);
      }
    }
    notifyListeners();
  }

  // Begin editing an existing geofence by id: shows helper at its center with its radius
  Future<void> beginEditGeofence(String geofenceId) async {
    final gf = _savedGeofences.firstWhere(
      (g) => g.id == geofenceId,
      orElse: () => throw StateError('Geofence not found: $geofenceId'),
    );
    _editingGeofenceId = geofenceId;
    final point = Point(coordinates: Position(gf.longitude, gf.latitude));
    await displayExistingGeofence(point, gf.radiusMeters);
  }

  // Save the edited geofence (radius and/or center) back to DB and native
  Future<void> saveEditedGeofence(BuildContext context) async {
    if (_editingGeofenceId == null || selectedPoint == null) {
      _showError(context, 'No geofence selected to edit.');
      return;
    }
    try {
      final idx = _savedGeofences.indexWhere((g) => g.id == _editingGeofenceId);
      if (idx < 0) {
        throw StateError('Geofence not found: $_editingGeofenceId');
      }

      final existing = _savedGeofences[idx];
      final updated = GeofenceData(
        id: existing.id,
        latitude: selectedPoint!.coordinates.lat.toDouble(),
        longitude: selectedPoint!.coordinates.lng.toDouble(),
        radiusMeters: pendingRadiusMeters,
        fillColor: existing.fillColor,
        fillOpacity: existing.fillOpacity,
        strokeColor: existing.strokeColor,
        strokeWidth: existing.strokeWidth,
        task: existing.task,
      );

      await _geofenceStorage.saveGeofence(updated);

      // Recreate native geofence with same id (createGeofence removes if exists)
      await _geofencingService.createGeofence(
        geometry: Point(
          coordinates: Position(updated.longitude, updated.latitude),
        ),
        radiusMeters: updated.radiusMeters,
        customId: updated.id,
        fillColor: _parseColor(updated.fillColor) ?? Colors.amberAccent,
        fillOpacity: updated.fillOpacity,
        strokeColor: _parseColor(updated.strokeColor) ?? Colors.white,
        strokeWidth: updated.strokeWidth,
      );

      _savedGeofences[idx] = updated;

      // Refresh visual display
      await _displaySavedGeofences();
      _showSuccess(context, 'Geofence updated.');
      // Exit editing mode
      _editingGeofenceId = null;
      notifyListeners();
    } catch (e, st) {
      debugPrint('Failed to save edited geofence: $e\n$st');
      _showError(context, 'Failed to update geofence: $e');
    }
  }

  // Compute geodesic distance between two lat/lng in meters (haversine)
  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            (math.sin(dLon / 2) * math.sin(dLon / 2));
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (3.141592653589793 / 180.0);

  // Offset a Point by meters in a given bearing (radians). Returns new Point.
  Point _offsetPoint(Point start, double meters, double bearingRad) {
    final lat = _deg2rad(start.coordinates.lat.toDouble());
    final lon = _deg2rad(start.coordinates.lng.toDouble());
    const R = 6371000.0;
    final dr = meters / R;
    final newLat = math.asin(
      math.sin(lat) * math.cos(dr) +
          math.cos(lat) * math.sin(dr) * math.cos(bearingRad),
    );
    final newLon =
        lon +
        math.atan2(
          math.sin(bearingRad) * math.sin(dr) * math.cos(lat),
          math.cos(dr) - math.sin(lat) * math.sin(newLat),
        );
    return Point(
      coordinates: Position(
        newLon * 180.0 / 3.141592653589793,
        newLat * 180.0 / 3.141592653589793,
      ),
    );
  }

  // Auto-adjust center to avoid overlaps with existing geofences
  Future<Point> _autoAdjustCenter(
    Point start,
    double radiusMeters, {
    String? excludeId,
  }) async {
    if (_savedGeofences.isEmpty) return start;
    // Check nearest overlap
    GeofenceData? nearest;
    double nearestDist = double.infinity;
    for (final g in _savedGeofences) {
      if (excludeId != null && g.id == excludeId) continue;
      final d = _distanceMeters(
        start.coordinates.lat.toDouble(),
        start.coordinates.lng.toDouble(),
        g.latitude,
        g.longitude,
      );
      final minAllowed = g.radiusMeters + radiusMeters + _overlapPaddingMeters;
      if (d < minAllowed && d < nearestDist) {
        nearest = g;
        nearestDist = d;
      }
    }
    if (nearest == null) return start; // no overlap

    // Compute bearing from nearest center to start and push outward
    final dy = (start.coordinates.lat.toDouble() - nearest.latitude);
    final dx = (start.coordinates.lng.toDouble() - nearest.longitude);
    double bearing = math.atan2(
      math.sin(_deg2rad(dx)) *
          math.cos(_deg2rad(start.coordinates.lat.toDouble())),
      math.cos(_deg2rad(nearest.latitude)) *
              math.sin(_deg2rad(start.coordinates.lat.toDouble())) -
          math.sin(_deg2rad(nearest.latitude)) *
              math.cos(_deg2rad(start.coordinates.lat.toDouble())) *
              math.cos(_deg2rad(dx)),
    );
    if (dy == 0 && dx == 0) {
      // Pick an arbitrary bearing if exactly overlapping
      bearing = 0.0;
    }
    final needed =
        (nearest.radiusMeters + radiusMeters + _overlapPaddingMeters) -
        nearestDist;
    final adjusted = _offsetPoint(start, needed, bearing);
    return adjusted;
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
          _currentHelperRadiusInPixels = pendingRadiusMeters / metersPerPixel;
          debugPrint(
            "[MapViewModel] onCameraIdle: Helper radius updated to: $_currentHelperRadiusInPixels px for ${pendingRadiusMeters} m (lat: $centerLat, zoom: $zoomLevel)",
          );
        } else {
          debugPrint(
            "[MapViewModel] Could not calculate initial helper radius, metersPerPixel was 0 or less.",
          );
        }
      }
      // If first time after map creation, render saved geofences now using final zoom
      if (_initialDisplayPending && isMapReady && mapboxMap != null) {
        _initialDisplayPending = false;
        await _loadSavedGeofences(forceNativeRecreation: false);
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

      // If nothing to display, do NOT clear existing visuals to avoid a flash-then-gone effect
      if (_savedGeofences.isEmpty) {
        debugPrint(
          'No saved geofences to display; preserving existing annotations.',
        );
        return;
      }

      // Clear existing geofences before re-adding
      debugPrint('Clearing existing geofence annotations...');
      await geofenceZoneSymbol!.deleteAll();
      geofenceZoneSymbolIds.clear();

      // Add all saved geofences
      // Compute per-feature meters-per-pixel at current zoom for accurate sizing
      final camera = await mapboxMap!.getCameraState();
      final currentZoom = camera.zoom;
      for (final geofence in _savedGeofences) {
        try {
          debugPrint(
            'Adding geofence ${geofence.id} at ${geofence.latitude}, ${geofence.longitude}',
          );

          final point = Point(
            coordinates: Position(geofence.longitude, geofence.latitude),
          );

          // Parse colors; fall back to defaults if unrecognized so geofence remains visible
          final parsedFill =
              _parseColor(geofence.fillColor) ?? Colors.amberAccent;
          final parsedStroke =
              _parseColor(geofence.strokeColor) ?? Colors.white;

          // Compute pixel radius using the geofence's latitude at the current zoom
          double mpp = await mapboxMap!.projection.getMetersPerPixelAtLatitude(
            geofence.latitude,
            currentZoom,
          );
          if (mpp <= 0) {
            // Fallback to camera-center MPP
            mpp = await metersToPixelsAtCurrentLocationAndZoom();
          }
          final safeMpp = mpp > 0 ? mpp : 1.0;
          double pixelRadius = geofence.radiusMeters / safeMpp;
          // Maintain a visibility floor without distorting too much
          if (pixelRadius < 2.5) pixelRadius = 2.5;

          final double visibleOpacity =
              geofence.fillOpacity.clamp(0.2, 1.0).toDouble();
          final visibleStrokeWidth =
              geofence.strokeWidth < 1.0 ? 1.0 : geofence.strokeWidth;

          final annotation = await geofenceZoneSymbol!.create(
            CircleAnnotationOptions(
              geometry: point,
              circleRadius: pixelRadius,
              circleColor: parsedFill.value,
              circleOpacity: visibleOpacity,
              circleStrokeColor: parsedStroke.value,
              circleStrokeWidth: visibleStrokeWidth,
            ),
          );

          geofenceZoneSymbolIds.add(annotation);
          debugPrint(
            'Added geofence ${geofence.id} to map (px=${pixelRadius.toStringAsFixed(2)}, opacity=$visibleOpacity, strokeW=$visibleStrokeWidth)',
          );
          // Queue offline region caching for this geofence (non-blocking)
          // ignore: unawaited_futures
          OfflineMapService().ensureRegionForGeofence(geofence);
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
      // Place selection and auto-adjust to avoid overlaps
      selectedPoint = await _autoAdjustCenter(
        context.point,
        pendingRadiusMeters,
        excludeId: _editingGeofenceId,
      );
      latitude = context.point.coordinates.lat;
      longitude = context.point.coordinates.lng;

      debugPrint(
        "Creating GF Helper with Radius in Pix: $_currentHelperRadiusInPixels",
      );

      if (geofenceZoneHelper != null) {
        // Recompute helper pixel radius for the selected latitude
        final lat = selectedPoint!.coordinates.lat.toDouble();
        final camera = await mapboxMap!.getCameraState();
        final mpp = await mapboxMap!.projection.getMetersPerPixelAtLatitude(
          lat,
          camera.zoom,
        );
        if (mpp > 0) {
          _currentHelperRadiusInPixels = pendingRadiusMeters / mpp;
        }
        await geofenceZoneHelper!.deleteAll();
        geofenceZoneHelperIds.clear();

        final annotation = await geofenceZoneHelper!.create(
          CircleAnnotationOptions(
            geometry: selectedPoint!,
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

      double radiusInMeters = pendingRadiusMeters;

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
        "Calculated geofenceHelperRadiusInPixels for ${radiusInMeters}m: $_currentHelperRadiusInPixels",
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

    List<Future> futures = [];

    // Update active helper if it's placed
    if (geofenceZoneHelper != null && geofenceZoneHelperIds.isNotEmpty) {
      final helperLat = selectedPoint?.coordinates.lat.toDouble();

      // Use consistent calculation method with existing geofences
      double mppHelper = 0.0;
      if (helperLat != null) {
        final camera = await mapboxMap!.getCameraState();
        mppHelper = await mapboxMap!.projection.getMetersPerPixelAtLatitude(
          helperLat,
          camera.zoom,
        );
      }

      // Fallback to camera-center method if helper-specific calculation fails
      if (mppHelper <= 0) {
        mppHelper = await metersToPixelsAtCurrentLocationAndZoom(
          latitudeOverride: helperLat,
        );
      }
      if (mppHelper == 0.0) {
        debugPrint("Cannot update helper radius: metersPerPixel is 0.");
      } else {
        _currentHelperRadiusInPixels = pendingRadiusMeters / mppHelper;
      }
      for (final annotation in geofenceZoneHelperIds) {
        // Should only be one helper
        annotation.circleRadius = _currentHelperRadiusInPixels;
        futures.add(geofenceZoneHelper!.update(annotation));
        debugPrint(
          "Updating helper to: $_currentHelperRadiusInPixels px for ${pendingRadiusMeters}m",
        );
      }
    }

    // Update actual saved geofence symbols
    if (geofenceZoneSymbol != null &&
        _savedGeofences.isNotEmpty &&
        geofenceZoneSymbolIds.length == _savedGeofences.length) {
      final camera = await mapboxMap!.getCameraState();
      final currentZoom = camera.zoom;
      for (int i = 0; i < _savedGeofences.length; i++) {
        final geofenceData = _savedGeofences[i];
        final annotation =
            geofenceZoneSymbolIds[i]; // Assuming lists are in sync
        // Per-feature meters-per-pixel at current zoom
        double mpp = await mapboxMap!.projection.getMetersPerPixelAtLatitude(
          geofenceData.latitude,
          currentZoom,
        );
        if (mpp <= 0) {
          mpp = await metersToPixelsAtCurrentLocationAndZoom();
        }
        final safeMpp = mpp > 0 ? mpp : 1.0;
        double px = geofenceData.radiusMeters / safeMpp;
        if (px < 2.5) px = 2.5; // minimal floor to avoid invisibility
        annotation.circleRadius = px;
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

  Future<double> metersToPixelsAtCurrentLocationAndZoom({
    double? latitudeOverride,
  }) async {
    if (mapboxMap == null) {
      debugPrint(
        "MapboxMap not initialized in metersToPixelsAtCurrentLocationAndZoom",
      );
      return 0.0;
    }
    try {
      final cameraState = await mapboxMap!.getCameraState();
      final double lat =
          (latitudeOverride ?? cameraState.center.coordinates.lat).toDouble();
      final double zoomLevel = cameraState.zoom;

      debugPrint("METERS TO PIX lat:$lat, at zoom:$zoomLevel");
      return mapboxMap!.projection.getMetersPerPixelAtLatitude(lat, zoomLevel);
    } catch (e) {
      debugPrint("Error in metersToPixelsAtCurrentLocationAndZoom: $e");
      return 0.0;
    }
  }

  Future<String?> createGeofenceAtSelectedPoint(
    BuildContext context, {
    required String taskName,
  }) async {
    if (_isCreatingGeofence) {
      debugPrint('Already creating a geofence, ignoring duplicate request');
      return null;
    }

    if (selectedPoint == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No point selected to create a geofence.'),
          ),
        );
      }
      return null;
    }

    _isCreatingGeofence = true;
    String? createdGeofenceId;
    try {
      debugPrint('Creating geofence at ${selectedPoint!.coordinates}');

      // Generate a unique ID for the geofence
      final geofenceId = 'geofence_${DateTime.now().millisecondsSinceEpoch}';
      createdGeofenceId = geofenceId;

      // Create the geofence data object
      final geofenceData = GeofenceData(
        id: geofenceId,
        latitude: selectedPoint!.coordinates.lat.toDouble(),
        longitude: selectedPoint!.coordinates.lng.toDouble(),
        radiusMeters: pendingRadiusMeters,
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

      // Link this geofence to the corresponding task by name in tasks table
      try {
        final affected = await TaskRepository().updateTaskGeofenceIdByName(
          taskName,
          geofenceId,
        );
        debugPrint(
          '[MapViewModel] Linked geofence "$geofenceId" to taskName="$taskName" (rows updated: $affected).',
        );
      } catch (e, st) {
        debugPrint(
          '[MapViewModel] Failed to link geofence to task "$taskName": $e\n$st',
        );
        // Continue; geofence exists but task linkage failed.
      }

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
        radiusMeters: pendingRadiusMeters,
        customId: geofenceId,
        fillColor: Colors.amberAccent,
        fillOpacity: 0.5,
        strokeColor: Colors.white,
        strokeWidth: 2.0,
      );
      debugPrint('Geofence created in native service');

      // After creation, perform a full refresh to ensure correct sizing immediately
      if (mapboxMap != null && !_isDisposed) {
        debugPrint(
          'Refreshing geofence display after creation to ensure correct sizing.',
        );
        await _displaySavedGeofences();
      }

      // Show success message
      if (context.mounted && !_isDisposed) {
        _showSuccess(context, 'Geofence created successfully!');
      }

      if (!_isDisposed) {
        notifyListeners();
      }

      // Return the created geofence ID
      return createdGeofenceId;
    } catch (e, stackTrace) {
      debugPrint('Error creating geofence: $e\n$stackTrace');
      if (context.mounted && !_isDisposed) {
        _showError(context, 'Failed to create geofence: ${e.toString()}');
      }
      return null;
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

    // Calculate radius in pixels for the current zoom level using geofence-specific latitude
    double metersPerPixel = 0.0;
    try {
      final camera = await mapboxMap!.getCameraState();
      metersPerPixel = await mapboxMap!.projection.getMetersPerPixelAtLatitude(
        point.coordinates.lat.toDouble(),
        camera.zoom,
      );
    } catch (e) {
      debugPrint("Error getting meters per pixel at geofence latitude: $e");
    }

    // Fallback to camera-center method if geofence-specific calculation fails
    if (metersPerPixel <= 0) {
      metersPerPixel = await metersToPixelsAtCurrentLocationAndZoom();
    }
    if (metersPerPixel == 0.0) {
      debugPrint("Cannot display existing geofence: metersPerPixel is 0.");
      return;
    }
    _currentHelperRadiusInPixels = radiusMeters / metersPerPixel;
    pendingRadiusMeters = radiusMeters;

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

  /// Manually fly to user's current or last known location
  /// This can be called when user taps a "locate me" button
  Future<bool> flyToUserLocation() async {
    if (mapboxMap == null) {
      debugPrint('[MapViewModel] Cannot fly to user location: map not ready');
      return false;
    }

    locator.Position? userPosition;
    try {
      debugPrint('[MapViewModel] Manually getting user location for flyTo...');
      userPosition = await _locationService.getCurrentLocation();
    } catch (e) {
      debugPrint(
        '[MapViewModel] Error getting current location for manual flyTo: $e',
      );
      // Try cached location
      try {
        userPosition = await _locationService.getLastKnownLocation();
        if (userPosition != null) {
          debugPrint('[MapViewModel] Using cached location for manual flyTo');
        }
      } catch (cacheError) {
        debugPrint(
          '[MapViewModel] Error getting cached location for manual flyTo: $cacheError',
        );
      }
    }

    if (userPosition != null) {
      try {
        await mapboxMap!.flyTo(
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
        debugPrint('[MapViewModel] Manual flyTo user location completed');
        return true;
      } catch (e) {
        debugPrint('[MapViewModel] Error during manual flyTo: $e');
      }
    } else {
      debugPrint('[MapViewModel] No location available for manual flyTo');
    }

    return false;
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

    // Stop location tracking
    _stopLocationTracking();

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