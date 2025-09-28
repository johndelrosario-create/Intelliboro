import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:intelliboro/models/download_progress.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/services/location_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    // In a real implementation, set TileStore location and init offline manager here.
    // For now we just record the style.
    _initialized = true;
    developer.log('[OfflineMapService] Initialized with style=$_styleUri');
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

  /// Clear all offline data. In a real implementation, this would clear TileStore.
  Future<void> clearAll() async {
    try {
      // Clear downloaded regions tracking
      await _clearDownloadedRegions();
      // TODO: Implement TileStore clearing when adding real offline API calls.
      developer.log(
        '[OfflineMapService] clearAll requested - cleared download tracking',
      );
    } catch (e, st) {
      developer.log(
        '[OfflineMapService] clearAll error: $e',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Internal method to perform the region download.
  /// This implementation provides realistic progress tracking and simulates
  /// tile downloading with proper progress callbacks.
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
      // Calculate estimated number of tiles
      final totalTiles = _estimateTileCount(
        centerLat: centerLat,
        centerLng: centerLng,
        radiusMeters: radiusMeters,
        minZoom: minZoom,
        maxZoom: maxZoom,
      );

      developer.log(
        '[OfflineMapService] Starting download: $name (estimated $totalTiles tiles)',
      );

      // Initial progress
      _progressController.add(DownloadProgress.initializing());

      // Simulate initial setup delay
      await Future.delayed(const Duration(milliseconds: 500));

      if (_isCancelled) {
        _progressController.add(DownloadProgress.cancelled(totalTiles, 0));
        return;
      }

      // Simulate tile downloading with realistic progress
      int downloadedTiles = 0;
      final startTime = DateTime.now();

      while (downloadedTiles < totalTiles && !_isCancelled) {
        // Simulate downloading a batch of tiles (5-20 tiles per batch)
        final batchSize = math.min(
          totalTiles - downloadedTiles,
          5 + math.Random().nextInt(16), // 5-20 tiles
        );

        // Simulate network delay (100-500ms per batch)
        await Future.delayed(
          Duration(milliseconds: 100 + math.Random().nextInt(400)),
        );

        downloadedTiles += batchSize;

        // Calculate download speed and ETA
        final elapsed = DateTime.now().difference(startTime);
        final tilesPerSecond = downloadedTiles / elapsed.inSeconds;
        final remainingTiles = totalTiles - downloadedTiles;
        final etaSeconds = remainingTiles / tilesPerSecond;

        final progress = DownloadProgress.downloading(
          totalTiles: totalTiles,
          downloadedTiles: downloadedTiles,
          tilesPerSecond: tilesPerSecond,
          estimatedTimeRemaining: Duration(seconds: etaSeconds.round()),
        );

        _progressController.add(progress);

        developer.log(
          '[OfflineMapService] Progress: ${progress.progressPercentage} (${progress.downloadedTiles}/${progress.totalTiles})',
        );
      }

      if (_isCancelled) {
        _progressController.add(
          DownloadProgress.cancelled(totalTiles, downloadedTiles),
        );
        developer.log('[OfflineMapService] Download cancelled: $name');
      } else {
        // Mark region as downloaded before emitting completion
        await _markRegionAsDownloaded(name);
        _progressController.add(DownloadProgress.completed(totalTiles));
        developer.log('[OfflineMapService] Download completed: $name');
      }

      // TODO: Replace this simulation with real Mapbox TileStore/OfflineManager integration
      // Example integration:
      // final tileStore = await TileStore.create();
      // final downloadOptions = TilesetDescriptorOptions(
      //   styleUri: _styleUri,
      //   minZoom: minZoom.toInt(),
      //   maxZoom: maxZoom.toInt(),
      // );
      // await tileStore.loadTileRegion(name, downloadOptions, onProgress: (progress) {
      //   _progressController.add(DownloadProgress.downloading(...));
      // });
    } catch (e, st) {
      developer.log(
        '[OfflineMapService] Download error: $e',
        error: e,
        stackTrace: st,
      );
      _progressController.add(DownloadProgress.error(e.toString(), 0, 0));
    }
  }

  /// Estimate the number of tiles for a given region and zoom range.
  /// This provides a rough estimate for progress tracking.
  int _estimateTileCount({
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
    required double minZoom,
    required double maxZoom,
  }) {
    int totalTiles = 0;

    for (double zoom = minZoom; zoom <= maxZoom; zoom++) {
      // Calculate the number of tiles needed at this zoom level
      // This is a simplified calculation; real implementation would be more precise
      final tilesAtZoom = math.pow(2, zoom).toInt();
      final earthCircumference = 40075000.0; // meters
      final metersPerTile = earthCircumference / tilesAtZoom;
      final tilesNeeded = ((radiusMeters * 2) / metersPerTile).ceil();

      // Approximate square coverage
      totalTiles += tilesNeeded * tilesNeeded;
    }

    // Apply a realistic scaling factor (tiles don't cover the full theoretical grid)
    return (totalTiles * 0.4).round().clamp(50, 5000);
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