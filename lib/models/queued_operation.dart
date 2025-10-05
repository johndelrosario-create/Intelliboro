/// Priority levels for queued operations
enum OperationPriority {
  low(0),
  normal(1),
  high(2),
  critical(3);

  final int value;
  const OperationPriority(this.value);
}

/// Model for operations queued for execution when offline
class QueuedOperation {
  final String id;
  final String
  type; // 'task_create', 'task_update', 'task_delete', 'geofence_create', etc.
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final int retryCount;
  final String? error;
  final OperationPriority priority;
  final DateTime? nextRetryTime; // For exponential backoff

  const QueuedOperation({
    required this.id,
    required this.type,
    required this.data,
    required this.timestamp,
    this.retryCount = 0,
    this.error,
    this.priority = OperationPriority.normal,
    this.nextRetryTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'retryCount': retryCount,
      'error': error,
      'priority': priority.value,
      'nextRetryTime': nextRetryTime?.toIso8601String(),
    };
  }

  factory QueuedOperation.fromJson(Map<String, dynamic> json) {
    return QueuedOperation(
      id: json['id'] as String,
      type: json['type'] as String,
      data: Map<String, dynamic>.from(json['data'] as Map),
      timestamp: DateTime.parse(json['timestamp'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      error: json['error'] as String?,
      priority: OperationPriority.values.firstWhere(
        (p) =>
            p.value ==
            (json['priority'] as int? ?? OperationPriority.normal.value),
        orElse: () => OperationPriority.normal,
      ),
      nextRetryTime:
          json['nextRetryTime'] != null
              ? DateTime.parse(json['nextRetryTime'] as String)
              : null,
    );
  }

  QueuedOperation copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    int? retryCount,
    String? error,
    OperationPriority? priority,
    DateTime? nextRetryTime,
  }) {
    return QueuedOperation(
      id: id ?? this.id,
      type: type ?? this.type,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
      error: error ?? this.error,
      priority: priority ?? this.priority,
      nextRetryTime: nextRetryTime ?? this.nextRetryTime,
    );
  }

  @override
  String toString() {
    return 'QueuedOperation(id: $id, type: $type, timestamp: $timestamp, retryCount: $retryCount, priority: $priority)';
  }

  /// Generate a deduplication key for this operation
  /// Operations with the same key are considered duplicates
  String get deduplicationKey {
    switch (type) {
      case 'task_update':
      case 'task_delete':
        return '${type}_${data['id'] ?? data['taskId']}';
      case 'geofence_update':
      case 'geofence_delete':
        return '${type}_${data['id'] ?? data['geofenceId']}';
      default:
        // For create operations, use the full ID to allow multiple creates
        return id;
    }
  }
}
