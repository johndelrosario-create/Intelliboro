import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:intelliboro/models/download_progress.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/services/location_service.dart';
import 'package:intelliboro/services/offline_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

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
  TileStore? _tileStore;

  // Progress tracking
  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  // Cancellation support
  bool _isCancelled = false;

  // Downloaded regions tracking
  static const String _downloadedRegionsKey = 'offline_downloaded_regions';

  /// Check if a region has already been downloaded
  Future<bool> _isRegionDownloaded(String regionName) async {
    final prefs = await SharedPreferences.getInstance();
    final downloadedRegions = prefs.getStringList(_downloadedRegionsKey) ?? [];
    return downloadedRegions.contains(regionName);
  }

  /// Mark a region as downloaded
  Future<void> _markRegionAsDownloaded(String regionName) async {
    final prefs = await SharedPreferences.getInstance();
    final downloadedRegions = prefs.getStringList(_downloadedRegionsKey) ?? [];
    if (!downloadedRegions.contains(regionName)) {
      downloadedRegions.add(regionName);
      await prefs.setStringList(_downloadedRegionsKey, downloadedRegions);
    }
  }

  /// Get list of downloaded regions
  Future<List<String>> getDownloadedRegions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_downloadedRegionsKey) ?? [];
  }

  /// Clear all downloaded region tracking (for testing/reset)
  Future<void> _clearDownloadedRegions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_downloadedRegionsKey);
  }

  /// Initialize any required resources (style, tile store path, etc.).
  Future<void> init({required String styleUri}) async {
    if (_initialized && _styleUri == styleUri) return;
    _styleUri = styleUri;

    try {
      // Initialize TileStore for offline caching
      // In Mapbox v11+, TileStore automatically caches style resources
      // when tiles are downloaded, making the map work offline
      _tileStore = await TileStore.createDefault();
      developer.log(
        '[OfflineMapService] TileStore initialized for offline caching',
      );

      _initialized = true;
      developer.log('[OfflineMapService] Initialized with style=$_styleUri');
    } catch (e, st) {
      developer.log(
        '[OfflineMapService] Failed to initialize TileStore: $e',
        error: e,
        stackTrace: st,
      );
      // Continue anyway - offline won't work but app shouldn't crash
      _initialized = true;
    }
  }

  /// Ensure a home region is cached. Uses first saved geofence center or last known location.
  /// Radius=25km, zooms 8–16.
  Future<void> ensureHomeRegion() async {
    try {
      if (!_initialized) {
        developer.log(
          '[OfflineMapService] ensureHomeRegion called before init; skipping',
        );
        _progressController.add(
          DownloadProgress.error('Service not initialized', 0, 0),
        );
        return;
      }

      // Start with initializing progress
      _progressController.add(DownloadProgress.initializing());

      // Check if home region is already downloaded
      const regionName = 'home_region';
      if (await _isRegionDownloaded(regionName)) {
        developer.log(
          '[OfflineMapService] Home region already downloaded, skipping',
        );
        _progressController.add(DownloadProgress.completed(0));
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
        developer.log(
          '[OfflineMapService] No center for home region; skipping',
        );
        _progressController.add(
          DownloadProgress.error(
            'No location available for home region. Please add a geofence or enable location services.',
            0,
            0,
          ),
        );
        return;
      }

      const radiusMeters = 25 * 1000.0; // 25km

      // Cache the hometown region info in LocationService for real-time tracking
      await LocationService().cacheHometownRegion(lat, lng, radiusMeters);

      await _downloadRegion(
        centerLat: lat,
        centerLng: lng,
        radiusMeters: radiusMeters,
        minZoom: 8.0,
        maxZoom: 16.0,
        name: 'home_region',
      );

      developer.log(
        '[OfflineMapService] Hometown region (25km) cached for offline use and real-time tracking',
      );

      // Optional: Pre-populate offline search cache
      // This runs in background and won't block the download completion
      _prePopulateSearchCache();
    } catch (e, st) {
      developer.log(
        '[OfflineMapService] ensureHomeRegion error: $e',
        error: e,
        stackTrace: st,
      );
      _progressController.add(
        DownloadProgress.error('Download failed: $e', 0, 0),
      );
    }
  }

  /// Pre-populate offline search cache in background
  void _prePopulateSearchCache() {
    Future.microtask(() async {
      try {
        developer.log(
          '[OfflineMapService] Starting background search cache pre-population',
        );
        final offlineSearchService = OfflineSearchService();
        await offlineSearchService.prePopulateCacheForHomeRegion();
        developer.log(
          '[OfflineMapService] Search cache pre-population completed',
        );
      } catch (e) {
        developer.log(
          '[OfflineMapService] Search cache pre-population failed (non-critical): $e',
        );
      }
    });
  }

  /// Ensure an offline region around a geofence center.
  /// Radius=3km, zooms 10–17.
  Future<void> ensureRegionForGeofence(GeofenceData gf) async {
    try {
      if (!_initialized) {
        _progressController.add(
          DownloadProgress.error('Service not initialized', 0, 0),
        );
        return;
      }

      final regionName = 'gf_${gf.id.substring(0, math.min(8, gf.id.length))}';

      // Check if this geofence region is already downloaded
      if (await _isRegionDownloaded(regionName)) {
        developer.log(
          '[OfflineMapService] Geofence region $regionName already downloaded, skipping',
        );
        _progressController.add(DownloadProgress.completed(0));
        return;
      }

      await _downloadRegion(
        centerLat: gf.latitude,
        centerLng: gf.longitude,
        radiusMeters: 3 * 1000.0,
        minZoom: 10.0,
        maxZoom: 17.0,
        name: regionName,
      );
    } catch (e, st) {
      developer.log(
        '[OfflineMapService] ensureRegionForGeofence error: $e',
        error: e,
        stackTrace: st,
      );
      _progressController.add(
        DownloadProgress.error('Geofence download failed: $e', 0, 0),
      );
    }
  }

  /// Clear all offline data tracking.
  Future<void> clearAll() async {
    try {
      // Clear downloaded regions tracking
      await _clearDownloadedRegions();

      // Note: Actual TileStore data persists in the system cache.
      // To completely clear, the app cache would need to be cleared from device settings.
      developer.log(
        '[OfflineMapService] clearAll completed - download tracking cleared',
      );
    } catch (e, st) {
      developer.log(
        '[OfflineMapService] clearAll error: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Internal method to perform the region download using Mapbox TileStore.
  Future<void> _downloadRegion({
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
    required double minZoom,
    required double maxZoom,
    required String name,
  }) async {
    _isCancelled = false;

    try {
      if (_tileStore == null || _styleUri == null) {
        throw Exception('OfflineMapService not properly initialized');
      }

      developer.log('[OfflineMapService] Starting download: $name');

      // Initial progress
      _progressController.add(DownloadProgress.initializing());

      // Calculate bounds for the region
      final bounds = _calculateBounds(centerLat, centerLng, radiusMeters);

      // Create tile region load options
      final tileRegionLoadOptions = TileRegionLoadOptions(
        geometry: {
          'type': 'Polygon',
          'coordinates': [
            [
              [bounds['west']!, bounds['south']!],
              [bounds['east']!, bounds['south']!],
              [bounds['east']!, bounds['north']!],
              [bounds['west']!, bounds['north']!],
              [bounds['west']!, bounds['south']!],
            ],
          ],
        },
        descriptorsOptions: [
          TilesetDescriptorOptions(
            styleURI: _styleUri!,
            minZoom: minZoom.toInt(),
            maxZoom: maxZoom.toInt(),
          ),
        ],
        metadata: {
          'name': name,
          'created_at': DateTime.now().toIso8601String(),
        },
        acceptExpired: true,
        networkRestriction: NetworkRestriction.NONE,
      );

      // Track progress
      int lastCompletedCount = 0;
      final startTime = DateTime.now();

      // Load tile region with progress tracking
      await _tileStore!.loadTileRegion(name, tileRegionLoadOptions, (progress) {
        if (_isCancelled) return;

        final totalTiles = progress.requiredResourceCount;
        final downloadedTiles = progress.completedResourceCount;

        // Calculate download speed
        final elapsed = DateTime.now().difference(startTime);
        final tilesPerSecond =
            elapsed.inSeconds > 0 ? downloadedTiles / elapsed.inSeconds : 0.0;
        final remainingTiles = totalTiles - downloadedTiles;
        final etaSeconds =
            tilesPerSecond > 0 ? remainingTiles / tilesPerSecond : 0.0;

        final downloadProgress = DownloadProgress.downloading(
          totalTiles: totalTiles,
          downloadedTiles: downloadedTiles,
          tilesPerSecond: tilesPerSecond,
          estimatedTimeRemaining: Duration(seconds: etaSeconds.round()),
        );

        _progressController.add(downloadProgress);
        lastCompletedCount = downloadedTiles;
      });

      if (_isCancelled) {
        _progressController.add(
          DownloadProgress.cancelled(lastCompletedCount, lastCompletedCount),
        );
        developer.log('[OfflineMapService] Download cancelled: $name');
      } else {
        // Mark region as downloaded
        await _markRegionAsDownloaded(name);
        _progressController.add(DownloadProgress.completed(lastCompletedCount));
        developer.log('[OfflineMapService] Download completed: $name');
      }
    } catch (e, st) {
      developer.log(
        '[OfflineMapService] Download error: $e',
        error: e,
        stackTrace: st,
      );
      _progressController.add(DownloadProgress.error(e.toString(), 0, 0));
    }
  }

  /// Calculate bounding box for a circle region
  Map<String, double> _calculateBounds(
    double centerLat,
    double centerLng,
    double radiusMeters,
  ) {
    const earthRadius = 6371000.0; // meters
    final latOffset = (radiusMeters / earthRadius) * (180 / math.pi);
    final lngOffset =
        (radiusMeters / earthRadius) *
        (180 / math.pi) /
        math.cos(centerLat * math.pi / 180);

    return {
      'north': centerLat + latOffset,
      'south': centerLat - latOffset,
      'east': centerLng + lngOffset,
      'west': centerLng - lngOffset,
    };
  }

  /// Cancel any ongoing download operation
  void cancelDownload() {
    _isCancelled = true;
    developer.log('[OfflineMapService] Download cancellation requested');
  }

  /// Dispose of resources
  void dispose() {
    _progressController.close();
  }
}
