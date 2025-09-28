/// Model representing the progress of an offline map download operation.
class DownloadProgress {
  /// Current phase of the download (e.g., "Initializing", "Downloading tiles", "Completing")
  final String phase;

  /// Overall progress as a percentage (0.0 to 1.0)
  final double progress;

  /// Total number of tiles to download
  final int totalTiles;

  /// Number of tiles already downloaded
  final int downloadedTiles;

  /// Download speed in tiles per second (optional)
  final double? tilesPerSecond;

  /// Estimated time remaining in seconds (optional)
  final Duration? estimatedTimeRemaining;

  /// Current download error, if any
  final String? error;

  /// Whether the download is completed successfully
  final bool isCompleted;

  /// Whether the download was cancelled
  final bool isCancelled;

  const DownloadProgress({
    required this.phase,
    required this.progress,
    required this.totalTiles,
    required this.downloadedTiles,
    this.tilesPerSecond,
    this.estimatedTimeRemaining,
    this.error,
    this.isCompleted = false,
    this.isCancelled = false,
  });

  /// Create a progress update for the initial phase
  factory DownloadProgress.initializing() {
    return const DownloadProgress(
      phase: 'Initializing download...',
      progress: 0.0,
      totalTiles: 0,
      downloadedTiles: 0,
    );
  }

  /// Create a progress update for active downloading
  factory DownloadProgress.downloading({
    required int totalTiles,
    required int downloadedTiles,
    double? tilesPerSecond,
    Duration? estimatedTimeRemaining,
  }) {
    final progress = totalTiles > 0 ? downloadedTiles / totalTiles : 0.0;
    return DownloadProgress(
      phase: 'Downloading tiles ($downloadedTiles of $totalTiles)...',
      progress: progress,
      totalTiles: totalTiles,
      downloadedTiles: downloadedTiles,
      tilesPerSecond: tilesPerSecond,
      estimatedTimeRemaining: estimatedTimeRemaining,
    );
  }

  /// Create a progress update for completion
  factory DownloadProgress.completed(int totalTiles) {
    return DownloadProgress(
      phase: 'Download completed successfully',
      progress: 1.0,
      totalTiles: totalTiles,
      downloadedTiles: totalTiles,
      isCompleted: true,
    );
  }

  /// Create a progress update for cancellation
  factory DownloadProgress.cancelled(int totalTiles, int downloadedTiles) {
    return DownloadProgress(
      phase: 'Download cancelled',
      progress: totalTiles > 0 ? downloadedTiles / totalTiles : 0.0,
      totalTiles: totalTiles,
      downloadedTiles: downloadedTiles,
      isCancelled: true,
    );
  }

  /// Create a progress update for errors
  factory DownloadProgress.error(
    String error,
    int totalTiles,
    int downloadedTiles,
  ) {
    return DownloadProgress(
      phase: 'Download failed',
      progress: totalTiles > 0 ? downloadedTiles / totalTiles : 0.0,
      totalTiles: totalTiles,
      downloadedTiles: downloadedTiles,
      error: error,
    );
  }

  /// Get a human-readable progress percentage
  String get progressPercentage => '${(progress * 100).toStringAsFixed(1)}%';

  /// Get estimated time remaining as a human-readable string
  String? get estimatedTimeRemainingText {
    if (estimatedTimeRemaining == null) return null;

    final duration = estimatedTimeRemaining!;
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m remaining';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s remaining';
    } else {
      return '${duration.inSeconds}s remaining';
    }
  }

  /// Get download speed as a human-readable string
  String? get downloadSpeedText {
    if (tilesPerSecond == null) return null;
    return '${tilesPerSecond!.toStringAsFixed(1)} tiles/sec';
  }

  @override
  String toString() {
    return 'DownloadProgress(phase: $phase, progress: $progressPercentage, tiles: $downloadedTiles/$totalTiles)';
  }
}