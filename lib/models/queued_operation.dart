/// Model for operations queued for execution when offline
class QueuedOperation {
  final String id;
  final String type; // 'task_create', 'task_update', 'task_delete', 'geofence_create', etc.
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final int retryCount;
  final String? error;

  const QueuedOperation({
    required this.id,
    required this.type,
    required this.data,
    required this.timestamp,
    this.retryCount = 0,
    this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'retryCount': retryCount,
      'error': error,
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
    );
  }

  QueuedOperation copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? data,
    DateTime? timestamp,
    int? retryCount,
    String? error,
  }) {
    return QueuedOperation(
      id: id ?? this.id,
      type: type ?? this.type,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      retryCount: retryCount ?? this.retryCount,
      error: error ?? this.error,
    );
  }

  @override
  String toString() {
    return 'QueuedOperation(id: $id, type: $type, timestamp: $timestamp, retryCount: $retryCount)';
  }
}
