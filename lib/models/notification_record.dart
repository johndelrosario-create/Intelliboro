class NotificationRecord {
  final int id;
  final int notificationId;
  final String geofenceId;
  final String? taskName;
  final String eventType;
  final String body;
  final DateTime timestamp;

  NotificationRecord({
    required this.id,
    required this.notificationId,
    required this.geofenceId,
    this.taskName,
    required this.eventType,
    required this.body,
    required this.timestamp,
  });

  factory NotificationRecord.fromMap(Map<String, dynamic> map) {
    final timestampValue = map['timestamp'] as int;

    // Fix for timestamps stored as seconds instead of milliseconds
    // If timestamp is less than year 2000 in milliseconds (946684800000),
    // it's likely stored as seconds, so convert it
    final timestampMs =
        timestampValue < 946684800000 ? timestampValue * 1000 : timestampValue;

    return NotificationRecord(
      id: map['id'] as int,
      notificationId: map['notification_id'] as int,
      geofenceId: map['geofence_id'] as String,
      taskName: map['task_name'] as String?,
      eventType: map['event_type'] as String,
      body: map['body'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'notification_id': notificationId,
      'geofence_id': geofenceId,
      'task_name': taskName,
      'event_type': eventType,
      'body': body,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}
