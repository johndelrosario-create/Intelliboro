import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:intelliboro/config/app_config.dart';

/// A model to represent search results from Mapbox Search API
class SearchResult {
  final String id;
  final String name;
  final String fullName;
  final double latitude;
  final double longitude;
  final String? category;
  final String? address;

  SearchResult({
    required this.id,
    required this.name,
    required this.fullName,
    required this.latitude,
    required this.longitude,
    this.category,
    this.address,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    final properties = json['properties'] ?? {};
    final geometry = json['geometry'] ?? {};
    final coordinates = geometry['coordinates'] ?? [0.0, 0.0];

    return SearchResult(
      id: json['id']?.toString() ?? '',
      name: properties['name']?.toString() ?? 'Unknown',
      fullName:
          properties['full_address']?.toString() ??
          properties['name']?.toString() ??
          'Unknown',
      latitude: (coordinates[1] as num?)?.toDouble() ?? 0.0,
      longitude: (coordinates[0] as num?)?.toDouble() ?? 0.0,
      category: properties['category']?.toString(),
      address: properties['address']?.toString(),
    );
  }

  Point toMapboxPoint() {
    return Point(coordinates: Position(longitude, latitude));
  }

  @override
  String toString() {
    return 'SearchResult(name: $name, fullName: $fullName, lat: $latitude, lng: $longitude)';
  }
}

/// Service for handling Mapbox search functionality
class MapboxSearchService {
  static const String _baseUrl =
      'https://api.mapbox.com/search/searchbox/v1/suggest';
  static const String _retrieveUrl =
      'https://api.mapbox.com/search/searchbox/v1/retrieve';

  final http.Client _client;
  Timer? _debounceTimer;

  MapboxSearchService({http.Client? client})
    : _client = client ?? http.Client();

  /// Get the access token from configuration
  static String get _accessToken => AppConfig.mapboxAccessToken;

  /// Search for places using Mapbox Search API with debouncing
  /// Returns a list of search suggestions
  Future<List<SearchResult>> searchPlaces({
    required String query,
    Point? proximity,
    String? country,
    int limit = 5,
    Duration debounceDelay = const Duration(milliseconds: 300),
  }) async {
    if (query.trim().isEmpty) {
      return [];
    }

    // Cancel previous timer if exists
    _debounceTimer?.cancel();

    final Completer<List<SearchResult>> completer =
        Completer<List<SearchResult>>();

    _debounceTimer = Timer(debounceDelay, () async {
      try {
        final results = await _performSearch(
          query: query,
          proximity: proximity,
          country: country,
          limit: limit,
        );
        if (!completer.isCompleted) {
          completer.complete(results);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
    });

    return completer.future;
  }

  /// Perform the actual search without debouncing
  Future<List<SearchResult>> _performSearch({
    required String query,
    Point? proximity,
    String? country,
    int limit = 5,
  }) async {
    try {
      if (!AppConfig.isMapboxConfigured) {
        developer.log(
          '[MapboxSearchService] WARNING: Mapbox access token not configured. Please update lib/config/app_config.dart',
        );
        return [];
      }

      final Map<String, String> queryParams = {
        'q': query,
        'access_token': _accessToken,
        'session_token': _generateSessionToken(),
        'limit': limit.toString(),
        'types': 'address,poi',
        'language': 'en',
      };

      // Add proximity bias if provided (search near current location)
      if (proximity != null) {
        queryParams['proximity'] =
            '${proximity.coordinates.lng},${proximity.coordinates.lat}';
      }

      // Add country bias if provided
      if (country != null) {
        queryParams['country'] = country;
      }

      final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);

      developer.log(
        '[MapboxSearchService] Making search request: ${uri.toString().replaceAll(_accessToken, 'TOKEN_HIDDEN')}',
      );

      final response = await _client
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final suggestions = data['suggestions'] as List? ?? [];

        final List<SearchResult> results =
            suggestions
                .map((item) {
                  try {
                    return SearchResult.fromJson(item);
                  } catch (e) {
                    developer.log(
                      '[MapboxSearchService] Error parsing search result: $e',
                    );
                    return null;
                  }
                })
                .where((result) => result != null)
                .cast<SearchResult>()
                .toList();

        developer.log(
          '[MapboxSearchService] Found ${results.length} search results for "$query"',
        );
        return results;
      } else {
        developer.log(
          '[MapboxSearchService] Search API error: ${response.statusCode} - ${response.body}',
        );
        throw Exception(
          'Search failed with status ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      developer.log('[MapboxSearchService] Search error: $e');
      throw Exception('Failed to search places: $e');
    }
  }

  /// Retrieve detailed information about a specific search result
  Future<SearchResult?> retrievePlace(String mapboxId) async {
    try {
      if (!AppConfig.isMapboxConfigured) {
        developer.log(
          '[MapboxSearchService] WARNING: Mapbox access token not configured',
        );
        return null;
      }

      final Map<String, String> queryParams = {
        'access_token': _accessToken,
        'session_token': _generateSessionToken(),
      };

      final uri = Uri.parse(
        '$_retrieveUrl/$mapboxId',
      ).replace(queryParameters: queryParams);

      final response = await _client
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List? ?? [];

        if (features.isNotEmpty) {
          return SearchResult.fromJson(features.first);
        }
      } else {
        developer.log(
          '[MapboxSearchService] Retrieve API error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      developer.log('[MapboxSearchService] Retrieve error: $e');
    }

    return null;
  }

  /// Generate a session token for search API calls
  String _generateSessionToken() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  /// Cancel any pending search operations
  void cancelPendingSearches() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Clean up resources
  void dispose() {
    cancelPendingSearches();
    _client.close();
  }

  /// Static method to check if access token is configured
  static bool get isConfigured => AppConfig.isMapboxConfigured;

  /// Static method to get configured access token (for development only)
  static String get accessToken => _accessToken;
}

/// Extension to help with search functionality in the map view model
extension MapboxSearchExtension on MapboxSearchService {
  /// Search for places and return results with distance from a reference point
  Future<List<SearchResult>> searchNearLocation({
    required String query,
    required Point location,
    String? country,
    int limit = 5,
  }) async {
    return searchPlaces(
      query: query,
      proximity: location,
      country: country,
      limit: limit,
    );
  }
}
