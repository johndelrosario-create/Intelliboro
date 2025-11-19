import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/services/location_service.dart';
import 'package:intelliboro/services/mapbox_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Offline-capable search service that provides location search even without internet.
/// Falls back to cached search results, geofences, and tasks within 25km range.
class OfflineSearchService {
  static final OfflineSearchService _instance =
      OfflineSearchService._internal();
  factory OfflineSearchService() => _instance;
  OfflineSearchService._internal();

  static const String _cachedSearchKey = 'offline_search_cache';
  static const int _maxCacheSize = 500; // Max number of cached locations
  static const double _defaultSearchRadius = 25000.0; // 25km in meters

  /// Check if device is online by attempting a quick search
  Future<bool> _isOnline() async {
    try {
      final searchService = MapboxSearchService();
      // Quick timeout test
      await searchService
          .searchPlaces(query: 'test', limit: 1)
          .timeout(const Duration(seconds: 2));
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Search for places with offline fallback
  /// Returns results from online API if available, otherwise uses cached data
  Future<List<SearchResult>> searchPlaces({
    required String query,
    Point? proximity,
    String? country,
    int limit = 10,
  }) async {
    if (query.trim().isEmpty) {
      return [];
    }

    developer.log('[OfflineSearchService] Searching for: "$query"');

    // Get current location for proximity bias
    Point? currentLocation = proximity;
    if (currentLocation == null) {
      try {
        final loc = await LocationService().getCurrentLocation();
        currentLocation = Point(
          coordinates: Position(loc.longitude, loc.latitude),
        );
      } catch (e) {
        developer.log(
          '[OfflineSearchService] Could not get current location: $e',
        );
      }
    }

    // Try online search first
    final isOnline = await _isOnline();

    if (isOnline) {
      try {
        final searchService = MapboxSearchService();
        final onlineResults = await searchService.searchPlaces(
          query: query,
          proximity: currentLocation,
          country: country,
          limit: limit,
        );

        // Note: Don't cache search suggestions here because they don't have coordinates
        // Results will be cached when retrievePlace() is called with full details

        developer.log(
          '[OfflineSearchService] Found ${onlineResults.length} results online',
        );
        return onlineResults;
      } catch (e) {
        developer.log(
          '[OfflineSearchService] Online search failed: $e, falling back to offline',
        );
      }
    }

    // Fallback to offline search
    developer.log('[OfflineSearchService] Using offline search');
    return await _offlineSearch(
      query: query,
      proximity: currentLocation,
      limit: limit,
    );
  }

  /// Perform offline search using cached data, geofences, and tasks
  Future<List<SearchResult>> _offlineSearch({
    required String query,
    Point? proximity,
    int limit = 10,
  }) async {
    final results = <SearchResult>[];
    final queryLower = query.toLowerCase().trim();

    // 1. Search cached online results
    final cached = await _getCachedSearchResults();
    for (final result in cached) {
      if (_matchesQuery(result, queryLower)) {
        results.add(result);
      }
    }

    // 2. Search existing geofences and tasks
    try {
      final geofences = await GeofenceStorage().loadGeofences();
      for (final gf in geofences) {
        if (_matchesGeofenceQuery(gf, queryLower)) {
          final taskName = gf.task ?? 'Unnamed Location';
          final result = SearchResult(
            id: 'geofence_${gf.id}',
            name: taskName,
            fullName: '$taskName (Saved Geofence)',
            latitude: gf.latitude,
            longitude: gf.longitude,
            category: 'saved_location',
            address: 'Saved geofence location',
          );
          results.add(result);
        }
      }
    } catch (e) {
      developer.log('[OfflineSearchService] Error searching geofences: $e');
    }

    // Filter by distance if proximity is available
    if (proximity != null) {
      results.removeWhere((result) {
        final distance = _calculateDistance(
          proximity.coordinates.lat.toDouble(),
          proximity.coordinates.lng.toDouble(),
          result.latitude,
          result.longitude,
        );
        return distance > _defaultSearchRadius;
      });
    }

    // Sort by relevance (exact matches first, then by distance)
    results.sort((a, b) {
      // Prioritize exact name matches
      final aExact = a.name.toLowerCase() == queryLower;
      final bExact = b.name.toLowerCase() == queryLower;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;

      // Then sort by distance if proximity available
      if (proximity != null) {
        final aDist = _calculateDistance(
          proximity.coordinates.lat.toDouble(),
          proximity.coordinates.lng.toDouble(),
          a.latitude,
          a.longitude,
        );
        final bDist = _calculateDistance(
          proximity.coordinates.lat.toDouble(),
          proximity.coordinates.lng.toDouble(),
          b.latitude,
          b.longitude,
        );
        return aDist.compareTo(bDist);
      }

      return 0;
    });

    // Limit results
    final limitedResults = results.take(limit).toList();

    developer.log(
      '[OfflineSearchService] Found ${limitedResults.length} offline results',
    );
    return limitedResults;
  }

  /// Check if a search result matches the query
  bool _matchesQuery(SearchResult result, String queryLower) {
    return result.name.toLowerCase().contains(queryLower) ||
        result.fullName.toLowerCase().contains(queryLower) ||
        (result.address?.toLowerCase().contains(queryLower) ?? false) ||
        (result.category?.toLowerCase().contains(queryLower) ?? false);
  }

  /// Check if a geofence matches the query
  bool _matchesGeofenceQuery(GeofenceData geofence, String queryLower) {
    final taskName = geofence.task ?? '';
    return taskName.toLowerCase().contains(queryLower);
  }

  /// Calculate distance between two coordinates in meters
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }

  /// Cache search results for offline use
  /// Only caches results with valid coordinates (not 0.0, 0.0)
  Future<void> _cacheSearchResults(List<SearchResult> results) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingCache = await _getCachedSearchResults();

      // Merge new results with existing, avoid duplicates
      final Map<String, SearchResult> resultMap = {};
      for (final result in existingCache) {
        resultMap[result.id] = result;
      }

      // Only add results with valid coordinates
      int skippedCount = 0;
      for (final result in results) {
        if (result.latitude != 0.0 || result.longitude != 0.0) {
          resultMap[result.id] = result;
        } else {
          skippedCount++;
        }
      }

      if (skippedCount > 0) {
        developer.log(
          '[OfflineSearchService] Skipped caching $skippedCount results without coordinates',
        );
      }

      // Limit cache size (keep most recent)
      final cacheList = resultMap.values.toList();
      if (cacheList.length > _maxCacheSize) {
        cacheList.removeRange(0, cacheList.length - _maxCacheSize);
      }

      // Serialize and save
      final jsonList =
          cacheList
              .map(
                (r) => {
                  'id': r.id,
                  'name': r.name,
                  'fullName': r.fullName,
                  'latitude': r.latitude,
                  'longitude': r.longitude,
                  'category': r.category,
                  'address': r.address,
                },
              )
              .toList();

      await prefs.setString(_cachedSearchKey, jsonEncode(jsonList));

      developer.log(
        '[OfflineSearchService] Cached ${cacheList.length} search results',
      );
    } catch (e) {
      developer.log('[OfflineSearchService] Failed to cache results: $e');
    }
  }

  /// Get cached search results
  Future<List<SearchResult>> _getCachedSearchResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_cachedSearchKey);

      if (jsonString == null) {
        return [];
      }

      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map(
            (json) => SearchResult(
              id: json['id'] as String,
              name: json['name'] as String,
              fullName: json['fullName'] as String,
              latitude: (json['latitude'] as num).toDouble(),
              longitude: (json['longitude'] as num).toDouble(),
              category: json['category'] as String?,
              address: json['address'] as String?,
            ),
          )
          .toList();
    } catch (e) {
      developer.log('[OfflineSearchService] Failed to load cache: $e');
      return [];
    }
  }

  /// Clear cached search results
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedSearchKey);
      developer.log('[OfflineSearchService] Cache cleared');
    } catch (e) {
      developer.log('[OfflineSearchService] Failed to clear cache: $e');
    }
  }

  /// Get statistics about cached data
  Future<Map<String, dynamic>> getCacheStats() async {
    final cached = await _getCachedSearchResults();
    final geofences = await GeofenceStorage().loadGeofences();

    return {
      'cachedSearchResults': cached.length,
      'savedGeofences': geofences.length,
      'totalOfflineLocations': cached.length + geofences.length,
    };
  }

  /// Pre-populate cache with common places around home region
  /// This is useful to run once when downloading offline maps
  Future<void> prePopulateCacheForHomeRegion() async {
    try {
      developer.log(
        '[OfflineSearchService] Pre-populating cache for home region...',
      );

      // Get home region center
      final geofences = await GeofenceStorage().loadGeofences();
      if (geofences.isEmpty) {
        developer.log(
          '[OfflineSearchService] No geofences found for pre-population',
        );
        return;
      }

      final center = Point(
        coordinates: Position(
          geofences.first.longitude,
          geofences.first.latitude,
        ),
      );

      // Search for common categories near home
      final categories = [
        'restaurant',
        'cafe',
        'hospital',
        'pharmacy',
        'grocery',
        'gas station',
        'school',
        'park',
        'bank',
        'post office',
      ];

      final searchService = MapboxSearchService();
      final allResults = <SearchResult>[];

      for (final category in categories) {
        try {
          final results = await searchService.searchPlaces(
            query: category,
            proximity: center,
            limit: 10,
          );
          allResults.addAll(results);

          // Small delay to avoid rate limiting
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          developer.log(
            '[OfflineSearchService] Failed to search for $category: $e',
          );
        }
      }

      if (allResults.isNotEmpty) {
        await _cacheSearchResults(allResults);
        developer.log(
          '[OfflineSearchService] Pre-populated cache with ${allResults.length} locations',
        );
      }
    } catch (e) {
      developer.log('[OfflineSearchService] Pre-population failed: $e');
    }
  }

  /// Retrieve detailed information about a place by ID
  /// For offline mode, if the ID starts with 'geofence_', returns cached geofence
  /// Otherwise tries online retrieval and caches the result
  Future<SearchResult?> retrievePlace(String id) async {
    developer.log('[OfflineSearchService] Retrieving place: $id');

    // Check if this is a geofence reference
    if (id.startsWith('geofence_')) {
      try {
        final geofenceId = id.substring('geofence_'.length);
        final geofences = await GeofenceStorage().loadGeofences();
        final gf = geofences.firstWhere((g) => g.id.contains(geofenceId));
        final taskName = gf.task ?? 'Unnamed Location';
        return SearchResult(
          id: id,
          name: taskName,
          fullName: '$taskName (Saved Geofence)',
          latitude: gf.latitude,
          longitude: gf.longitude,
          category: 'saved_location',
          address: 'Saved geofence location',
        );
      } catch (e) {
        developer.log('[OfflineSearchService] Failed to retrieve geofence: $e');
        return null;
      }
    }

    // Check cache first
    final cached = await _getCachedSearchResults();
    try {
      final fromCache = cached.firstWhere((r) => r.id == id);
      developer.log('[OfflineSearchService] Found in cache: ${fromCache.name}');
      return fromCache;
    } catch (_) {
      // Not in cache, try online
    }

    // Try online retrieval
    final isOnline = await _isOnline();
    if (isOnline) {
      try {
        final searchService = MapboxSearchService();
        final result = await searchService.retrievePlace(id);
        if (result != null) {
          // Cache the full result with coordinates for offline use
          await _cacheSearchResults([result]);
          developer.log(
            '[OfflineSearchService] Retrieved and cached: ${result.name} at (${result.latitude}, ${result.longitude})',
          );
          return result;
        }
      } catch (e) {
        developer.log('[OfflineSearchService] Online retrieve failed: $e');
      }
    }

    developer.log('[OfflineSearchService] Could not retrieve place $id');
    return null;
  }

  /// Cancel pending searches (no-op for offline search, kept for compatibility)
  void cancelPendingSearches() {
    developer.log('[OfflineSearchService] cancelPendingSearches called');
  }

  /// Dispose resources (no-op for offline search, kept for compatibility)
  void dispose() {
    developer.log('[OfflineSearchService] dispose called');
  }
}
