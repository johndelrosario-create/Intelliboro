import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate' show ReceivePort, SendPort;
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:native_geofence/native_geofence.dart'
    show
        NativeGeofenceManager,
        Geofence,
        GeofenceEvent,
        IosGeofenceSettings,
        AndroidGeofenceSettings,
        Location,
        GeofenceCallbackParams,
        ActiveGeofence;
import 'package:intelliboro/viewModel/Geofencing/map_viewmodel.dart';
import 'package:intelliboro/viewModel/notifications/callback.dart'
    show geofenceTriggered;

class GeofencingService {
  // --- Singleton implementation ---
  static final GeofencingService _instance = GeofencingService._internal();

  factory GeofencingService() {
    return _instance;
  }
  // --- End Singleton implementation ---

  // A reference to the MapViewModel is problematic for a singleton service.
  // We will manage map interactions via methods instead.
  MapboxMapViewModel? _mapViewModel;

  // Track created geofence IDs for management
  final Set<String> _createdGeofenceIds = {};
  bool _isInitialized = false;
  final ReceivePort _port = ReceivePort();

  // Static flag to ensure native manager is initialized only once globally
  static bool _nativeManagerGloballyInitialized = false;

  // Private internal constructor
  GeofencingService._internal();

  // Allow a view model to register itself for map updates
  void registerMapViewModel(MapboxMapViewModel viewModel) {
    _mapViewModel = viewModel;
    developer.log('[GeofencingService] MapViewModel registered.');
  }

  // Allow a view model to unregister itself
  void unregisterMapViewModel() {
    _mapViewModel = null;
    developer.log('[GeofencingService] MapViewModel unregistered.');
  }

  CircleAnnotationManager? get geofenceZoneSymbol =>
      _mapViewModel?.getGeofenceZoneSymbol();
  CircleAnnotationManager? get geofenceZoneHelper =>
      _mapViewModel?.getGeofenceZonePicker();

  Future<void> init() async {
    // init() now guards against multiple executions
    if (_isInitialized) {
      developer.log('[GeofencingService] Already initialized, skipping.');
      return;
    }
    await _initialize();
  }

  Future<void> _initialize() async {
    try {
      // First, ensure any existing port mapping is removed
      IsolateNameServer.removePortNameMapping('geofence_send_port');

      // Register the port for geofence events
      final bool registered = IsolateNameServer.registerPortWithName(
        _port.sendPort,
        'geofence_send_port',
      );

      if (!registered) {
        developer.log(
          '[GeofencingService] WARNING: Failed to register port with name "geofence_send_port"',
        );
      } else {
        developer.log(
          '[GeofencingService] Successfully registered port with name "geofence_send_port"',
        );
      }

      // This listener will now live for the entire app lifecycle
      _port.listen((dynamic data) {
        developer.log('[GeofencingService] Received on port: $data');
      });

      // Initialize the native geofence plugin
      await NativeGeofenceManager.instance.initialize();
      developer.log(
        '[GeofencingService] NativeGeofenceManager.instance.initialize() called successfully.',
      );

      _isInitialized = true;
      developer.log('GeofencingService initialized');
    } catch (e, stackTrace) {
      developer.log(
        'Error initializing GeofencingService',
        error: e,
        stackTrace: stackTrace,
      );
      _isInitialized = false; // Ensure we can retry if init fails
      rethrow;
    }
  }

  // Reference to the top-level callback function for geofence events
  // static final geofenceCallback = geofenceTriggered;

  Future<void> createGeofence({
    required Point geometry,
    required double radiusMeters,
    String? customId,
    Color fillColor = Colors.amberAccent,
    Color strokeColor = Colors.white,
    double strokeWidth = 2.0,
    double fillOpacity = 0.5,
  }) async {
    if (!_isInitialized) {
      await _initialize();
    }

    try {
      developer.log('Creating geofence at ${geometry.coordinates}');

      // Generate a unique ID if not provided
      final geofenceId =
          customId ?? 'geofence_${DateTime.now().millisecondsSinceEpoch}';

      // If the geofence already exists in our tracking set, remove it first
      if (_createdGeofenceIds.contains(geofenceId)) {
        developer.log('Geofence $geofenceId already exists, removing it first');
        await removeGeofence(geofenceId);
      }

      // Create the visual representation on the map
      await _createGeofenceVisual(
        id: geofenceId,
        geometry: geometry,
        radiusMeters: radiusMeters,
        fillColor: fillColor,
        fillOpacity: fillOpacity,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
      );

      // Create the native geofence
      await _createNativeGeofence(
        id: geofenceId,
        geometry: geometry,
        radiusMeters: radiusMeters,
      );

      _createdGeofenceIds.add(geofenceId);
      developer.log('Geofence created successfully: $geofenceId');

      return Future.value();
    } catch (e, stackTrace) {
      developer.log(
        'Error in createGeofence',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _createGeofenceVisual({
    required String id,
    required Point geometry,
    required double radiusMeters,
    required Color fillColor,
    required double fillOpacity,
    required Color strokeColor,
    required double strokeWidth,
  }) async {
    try {
      // Check if a map view model is available before doing visual tasks
      if (_mapViewModel == null) {
        developer.log(
          '[GeofencingService] No MapViewModel registered, skipping visual creation.',
        );
        return; // Can't create visual without a map
      }

      final zoomLevel = await _mapViewModel!.currentZoomLevel();

      // Get the conversion factor
      final metersPerPixelConversionFactor =
          await _mapViewModel!.metersToPixelsAtCurrentLocationAndZoom();

      if (metersPerPixelConversionFactor == 0.0) {
        developer.log(
          'Error in _createGeofenceVisual: metersPerPixelConversionFactor is 0.0. Cannot calculate radius in pixels.',
        );
        // Potentially throw an error or return, as radiusInPixels will be invalid (Infinity or NaN)
        throw Exception(
          "Failed to calculate meters per pixel for geofence visual.",
        );
      }

      // Calculate radius in pixels
      final radiusInPixels = radiusMeters / metersPerPixelConversionFactor;

      developer.log('''
        Creating geofence visual:
        - ID: $id
        - Position: ${geometry.coordinates.lat}, ${geometry.coordinates.lng}
        - Radius: ${radiusMeters}m (${radiusInPixels.toStringAsFixed(2)}px)
        - Zoom: $zoomLevel
      ''');

      if (geofenceZoneHelper == null) {
        throw StateError('Geofence zone symbol helper is null');
      }

      final annotation = await geofenceZoneSymbol!.create(
        CircleAnnotationOptions(
          geometry: geometry,
          circleRadius: radiusInPixels,
          circleColor: fillColor.value,
          circleOpacity: fillOpacity,
          circleStrokeColor: strokeColor.value,
          circleStrokeWidth: strokeWidth,
        ),
      );

      _mapViewModel!.geofenceZoneSymbolIds.add(annotation);
      developer.log('Geofence visual created: $id');
    } catch (e, stackTrace) {
      developer.log(
        'Error creating geofence visual',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _createNativeGeofence({
    required String id,
    required Point geometry,
    required double radiusMeters,
  }) async {
    try {
      // Create location from geometry
      final location = Location(
        latitude: geometry.coordinates.lat.toDouble(),
        longitude: geometry.coordinates.lng.toDouble(),
      );

      // Create the geofence with all required parameters
      final geofence = Geofence(
        id: id,
        location: location,
        radiusMeters: radiusMeters,
        triggers: {GeofenceEvent.enter, GeofenceEvent.exit},
        iosSettings: IosGeofenceSettings(initialTrigger: false),
        androidSettings: AndroidGeofenceSettings(
          initialTriggers: {GeofenceEvent.enter, GeofenceEvent.exit},
          notificationResponsiveness: const Duration(seconds: 0),
          loiteringDelay: const Duration(seconds: 0),
        ),
      );

      developer.log(
        '[GeofencingService._createNativeGeofence] Attempting to create native geofence with params: ID=$id, Lat=${location.latitude}, Lon=${location.longitude}, Radius=${radiusMeters}m',
      );

      // Register the geofence with the callback
      await NativeGeofenceManager.instance.createGeofence(
        geofence,
        geofenceTriggered,
      );

      // Cache the geofence for later removal
      _geofenceCache[geofence.id] = geofence;

      developer.log(
        '[GeofencingService._createNativeGeofence] Native geofence creation requested for ID: $id. Checking monitored regions...',
      );

      // Log all monitored regions
      final List<ActiveGeofence> monitoredRegions =
          await NativeGeofenceManager.instance.getRegisteredGeofences();

      if (monitoredRegions.isEmpty) {
        developer.log(
          '[GeofencingService._createNativeGeofence] No monitored regions reported by the plugin.',
        );
      } else {
        developer.log(
          '[GeofencingService._createNativeGeofence] Currently monitored regions by plugin (${monitoredRegions.length}):',
        );
        for (var activeRegion in monitoredRegions) {
          developer.log(
            '  - ID: ${activeRegion.id}, Lat: ${activeRegion.location.latitude}, Lon: ${activeRegion.location.longitude}, Radius: ${activeRegion.radiusMeters}m',
          );
        }
      }

      final bool isJustCreatedActive = monitoredRegions.any(
        (ag) => ag.id == id,
      );
      developer.log(
        '[GeofencingService._createNativeGeofence] Is newly created geofence ($id) listed as monitored by plugin? $isJustCreatedActive',
      );
      if (!isJustCreatedActive) {
        developer.log(
          '[GeofencingService._createNativeGeofence] WARNING: Newly created geofence $id was NOT found in the list of monitored regions immediately after creation. This is a problem!',
        );
      }
    } catch (e, stackTrace) {
      developer.log(
        'Error creating native geofence',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // Store created geofences to be able to remove them later
  final Map<String, Geofence> _geofenceCache = {};

  Future<void> removeGeofence(String id) async {
    try {
      if (!_createdGeofenceIds.contains(id)) {
        developer.log(
          'Geofence $id not found in tracking set, skipping removal',
        );
        return;
      }

      developer.log('Attempting to remove geofence: $id');

      // Get the geofence from cache or create a minimal one
      final geofence =
          _geofenceCache[id] ??
          Geofence(
            id: id,
            location: const Location(latitude: 0, longitude: 0), // Dummy values
            radiusMeters: 100, // Dummy value
            triggers: {GeofenceEvent.enter, GeofenceEvent.exit},
            iosSettings: IosGeofenceSettings(initialTrigger: false),
            androidSettings: AndroidGeofenceSettings(
              initialTriggers: {GeofenceEvent.enter, GeofenceEvent.exit},
              notificationResponsiveness: const Duration(seconds: 0),
              loiteringDelay: const Duration(seconds: 0),
            ),
          );

      try {
        await NativeGeofenceManager.instance.removeGeofence(geofence);
        developer.log('Successfully removed native geofence: $id');
      } catch (e) {
        developer.log(
          'Error removing native geofence $id (this might be normal if it was already removed): $e',
        );
        // Don't rethrow - we want to continue with cleanup even if native removal fails
      }

      _createdGeofenceIds.remove(id);
      _geofenceCache.remove(id);
      developer.log('Completed removal of geofence: $id');
    } catch (e, stackTrace) {
      developer.log(
        'Error in removeGeofence for $id',
        error: e,
        stackTrace: stackTrace,
      );
      // Still don't rethrow - we want the calling code to continue even if removal fails
    }
  }

  Future<void> removeAllGeofences() async {
    try {
      final ids = List<String>.from(_createdGeofenceIds);
      for (final id in ids) {
        await removeGeofence(id);
      }
      developer.log('All geofences removed');
    } catch (e, stackTrace) {
      developer.log(
        'Error removing all geofences',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // Clean up resources
  void dispose() {
    try {
      developer.log(
        '[GeofencingService] Global dispose called. This should be rare.',
      );

      // Do NOT close the port or remove the port mapping here
      // as it needs to stay alive for geofence callbacks
      // _port.close();
      // IsolateNameServer.removePortNameMapping('geofence_send_port');

      _createdGeofenceIds.clear();
      _isInitialized = false;
    } catch (e, stackTrace) {
      developer.log(
        'Error disposing GeofencingService',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}

// Extension to convert Color to int value for Mapbox
// extension ColorExtension on Color {
//   int toMapboxColor() {
//     return (alpha & 0xff) << 24 | (red & 0xff) << 16 | (green & 0xff) << 8 | (blue & 0xff);
//   }
// }
