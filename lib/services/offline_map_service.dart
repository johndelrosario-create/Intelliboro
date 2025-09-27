import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/services/location_service.dart';

/// OfflineMapService provides a single place to manage caching of offline tiles
/// for Mapbox. This scaffolds the flow and is safe to call even if offline APIs
/// are unavailable at runtime.
///
/// Default packs:
/// - Home region: 25 km radius, zooms 8–16.
/// - Per-geofence region: 3 km radius, zooms 10–17.
class OfflineMapService {
  static final OfflineMapService _instance = OfflineMapService._internal();
  factory OfflineMapService() => _instance;
  OfflineMapService._internal();

  bool _initialized = false;
  String? _styleUri;

  /// Initialize any required resources (style, tile store path, etc.).
  Future<void> init({required String styleUri}) async {
    if (_initialized && _styleUri == styleUri) return;
    _styleUri = styleUri;
    _initialized = true;
    developer.log('[OfflineMapService] Initialized with style=$_styleUri');
  }

  /// Ensure a home region is cached. Uses first saved geofence center or last known location.
  /// Radius=25km, zooms 8–16.
  Future<void> ensureHomeRegion() async {
    try {
      if (!_initialized) {
        developer.log('[OfflineMapService] ensureHomeRegion called before init; skipping');
        return;
      }
      final geofences = await GeofenceStorage().loadGeofences();
      double? lat;
      double? lng;
      if (geofences.isNotEmpty) {
        lat = geofences.first.latitude;
        lng = geofences.first.longitude;
      } else {
        try {
          final loc = await LocationService().getCurrentLocation();
          lat = loc.latitude;
          lng = loc.longitude;
        } catch (_) {}
      }
      if (lat == null || lng == null) {
        developer.log('[OfflineMapService] No center for home region; skipping');
        return;
      }
      await _downloadRegion(
        centerLat: lat,
        centerLng: lng,
        radiusMeters: 25 * 1000.0,
        minZoom: 8.0,
        maxZoom: 16.0,
        name: 'home_region',
      );
    } catch (e, st) {
      developer.log('[OfflineMapService] ensureHomeRegion error: $e', error: e, stackTrace: st);
    }
  }

  /// Ensure an offline region around a geofence center.
  /// Radius=3km, zooms 10–17.
  Future<void> ensureRegionForGeofence(GeofenceData gf) async {
    try {
      if (!_initialized) return;
      await _downloadRegion(
        centerLat: gf.latitude,
        centerLng: gf.longitude,
        radiusMeters: 3 * 1000.0,
        minZoom: 10.0,
        maxZoom: 17.0,
        name: 'gf_${gf.id.substring(0, math.min(8, gf.id.length))}',
      );
    } catch (e, st) {
      developer.log('[OfflineMapService] ensureRegionForGeofence error: $e', error: e, stackTrace: st);
    }
  }

  /// Clear all offline data. In a real implementation, this would clear TileStore.
  Future<void> clearAll() async {
    try {
      // TODO: Implement TileStore clearing when adding real offline API calls.
      developer.log('[OfflineMapService] clearAll requested (stub)');
    } catch (e, st) {
      developer.log('[OfflineMapService] clearAll error: $e', error: e, stackTrace: st);
    }
  }

  /// Internal method to perform the region download.
  /// This is a placeholder; integrate with mapbox_maps_flutter Offline APIs here.
  Future<void> _downloadRegion({
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
    required double minZoom,
    required double maxZoom,
    required String name,
  }) async {
    // TODO: Use Mapbox TileStore/OfflineManager once available in plugin scope.
    developer.log('[OfflineMapService] (stub) queue download: name=$name center=($centerLat,$centerLng) r=${radiusMeters.toStringAsFixed(0)}m z=$minZoom..$maxZoom style=$_styleUri');
  }
}