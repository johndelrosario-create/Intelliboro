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
  // Static reference to the current instance
  static GeofencingService? _instance;
  // final CircleAnnotationManager? geofenceZoneHelper;
  // final CircleAnnotationManager? geofenceZoneSymbol;
  final MapboxMapViewModel mapViewModel;

  // Track created geofence IDs for management
  final Set<String> _createdGeofenceIds = {};
  bool _isInitialized = false;
  final ReceivePort _port = ReceivePort();

  GeofencingService(this.mapViewModel) {
    _instance = this;
  }
  CircleAnnotationManager? get geofenceZoneSymbol =>
      mapViewModel.getGeofenceZoneSymbol();
  CircleAnnotationManager? get geofenceZoneHelper =>
      mapViewModel.getGeofenceZonePicker();

  Future<void> init() async {
    await _initialize();
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;

    try {
      // Register the port for geofence events
      IsolateNameServer.removePortNameMapping('geofence_send_port');
      IsolateNameServer.registerPortWithName(
        _port.sendPort,
        'geofence_send_port',
      );

      // Listen for geofence events
      _port.listen((dynamic data) {
        if (data is String) {
          developer.log('Geofence event: $data');
          // You can handle the event here or forward it to your UI
        }
      });

      // Initialize the native geofence plugin
      await NativeGeofenceManager.instance.initialize();

      _isInitialized = true;
      developer.log('GeofencingService initialized');
    } catch (e, stackTrace) {
      developer.log(
        'Error initializing GeofencingService',
        error: e,
        stackTrace: stackTrace,
      );
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

      if (_createdGeofenceIds.contains(geofenceId)) {
        throw Exception('Geofence with ID $geofenceId already exists');
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
      final zoomLevel = await mapViewModel.currentZoomLevel();

      // Get the conversion factor
      final metersPerPixelConversionFactor =
          await mapViewModel.metersToPixelsAtCurrentLocationAndZoom();

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

      mapViewModel.geofenceZoneSymbolIds.add(annotation);
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

      // Register the geofence with the callback
      await NativeGeofenceManager.instance.createGeofence(
        geofence,
        geofenceTriggered,
      );

      // Cache the geofence for later removal
      _geofenceCache[geofence.id] = geofence;

      developer.log('Native geofence created: $id');
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
        developer.log('Geofence $id not found, skipping removal');
        return;
      }

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

      await NativeGeofenceManager.instance.removeGeofence(geofence);
      _createdGeofenceIds.remove(id);
      _geofenceCache.remove(id);
      developer.log('Geofence removed: $id');
    } catch (e, stackTrace) {
      developer.log(
        'Error removing geofence $id',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
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
      _port.close();
      IsolateNameServer.removePortNameMapping('geofence_send_port');
      _createdGeofenceIds.clear();
      _isInitialized = false;
      if (_instance == this) {
        _instance = null;
      }
      developer.log('GeofencingService disposed');
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
