/// Configuration constants for the Intelliboro app
class AppConfig {
  /// Mapbox access token for map and search services
  ///
  /// To use this app with Mapbox services, you need to:
  /// 1. Sign up for a Mapbox account at https://account.mapbox.com/
  /// 2. Create a new access token with the following scopes:
  ///    - Maps SDK for Flutter
  ///    - Search API
  /// 3. Replace the token below with your actual token
  ///
  /// For production apps, consider using environment variables or secure storage
  /// instead of hardcoding the token here.
  static const String mapboxAccessToken = 'pk.your_mapbox_access_token_here';

  /// Check if Mapbox is properly configured
  static bool get isMapboxConfigured =>
      mapboxAccessToken != 'pk.your_mapbox_access_token_here' &&
      mapboxAccessToken.startsWith('pk.') &&
      mapboxAccessToken.length > 20;

  /// Default map configuration
  static const String defaultMapStyle = 'mapbox://styles/mapbox/streets-v12';

  /// Search configuration
  static const int defaultSearchResultLimit = 5;
  static const Duration searchDebounceDelay = Duration(milliseconds: 300);

  /// Geofence configuration
  static const double minGeofenceRadius = 1.0;
  static const double maxGeofenceRadius = 1000.0;
  static const double defaultGeofenceRadius = 50.0;
}
