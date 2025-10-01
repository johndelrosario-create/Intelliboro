/// Configuration constants for the Intelliboro app
class AppConfig {
  /// Mapbox access token for map and search services
  ///
  /// This reads from the ACCESS_TOKEN environment variable defined in .vscode/launch.json
  /// or falls back to a placeholder. The token is passed via --dart-define arguments.
  ///
  /// For production apps, consider using environment variables or secure storage
  /// instead of hardcoding the token here.
  static const String mapboxAccessToken = String.fromEnvironment(
    'ACCESS_TOKEN',
    defaultValue: 'pk.your_mapbox_access_token_here',
  );

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
