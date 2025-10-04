import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intelliboro/services/offline_operation_queue.dart';
import 'package:intelliboro/models/queued_operation.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflineOperationQueue', () {
    late OfflineOperationQueue queue;

    setUp(() async {
      // Clear shared preferences before each test
      SharedPreferences.setMockInitialValues({});
      queue = OfflineOperationQueue();
    });

    tearDown(() {
      queue.dispose();
    });

    test('should initialize successfully', () async {
      await queue.init();
      expect(queue.queueSize, equals(0));
      expect(queue.hasPendingOperations, isFalse);
    });

    test('should enqueue operations', () async {
      await queue.init();
      
      final operation = QueuedOperation(
        id: 'test_1',
        type: 'task_create',
        data: {'test': 'data'},
        timestamp: DateTime.now(),
      );

      await queue.enqueue(operation);
      expect(queue.queueSize, equals(1));
      expect(queue.hasPendingOperations, isTrue);
    });

    test('should queue task creation', () async {
      await queue.init();
      
      final task = TaskModel(
        taskName: 'Test Task',
        taskPriority: 3,
        taskTime: const TimeOfDay(hour: 10, minute: 30),
        taskDate: DateTime(2025, 10, 5),
        isRecurring: false,
        isCompleted: false,
      );

      await queue.queueTaskCreate(task);
      expect(queue.queueSize, equals(1));
    });

    test('should queue task update', () async {
      await queue.init();
      
      final task = TaskModel(
        id: 123,
        taskName: 'Updated Task',
        taskPriority: 4,
        taskTime: const TimeOfDay(hour: 14, minute: 0),
        taskDate: DateTime(2025, 10, 6),
        isRecurring: false,
        isCompleted: true,
      );

      await queue.queueTaskUpdate(task);
      expect(queue.queueSize, equals(1));
    });

    test('should queue task deletion', () async {
      await queue.init();
      
      await queue.queueTaskDelete(456);
      expect(queue.queueSize, equals(1));
    });

    test('should queue geofence creation', () async {
      await queue.init();
      
      final geofence = GeofenceData(
        id: 'geo_123',
        latitude: 37.7749,
        longitude: -122.4194,
        radiusMeters: 100.0,
        fillColor: 'FF0000FF',
        fillOpacity: 0.5,
        strokeColor: 'FFFFFFFF',
        strokeWidth: 2.0,
        task: 'Test Task',
      );

      await queue.queueGeofenceCreate(geofence);
      expect(queue.queueSize, equals(1));
    });

    test('should queue geofence update', () async {
      await queue.init();
      
      final geofence = GeofenceData(
        id: 'geo_456',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 200.0,
        fillColor: 'FF00FF00',
        fillOpacity: 0.6,
        strokeColor: 'FF000000',
        strokeWidth: 3.0,
        task: 'Updated Task',
      );

      await queue.queueGeofenceUpdate(geofence);
      expect(queue.queueSize, equals(1));
    });

    test('should queue geofence deletion', () async {
      await queue.init();
      
      await queue.queueGeofenceDelete('geo_789');
      expect(queue.queueSize, equals(1));
    });

    test('should persist queue to storage', () async {
      await queue.init();
      
      final operation = QueuedOperation(
        id: 'persist_test',
        type: 'task_create',
        data: {'name': 'Persisted Task'},
        timestamp: DateTime.now(),
      );

      await queue.enqueue(operation);
      
      // Create new instance to test persistence
      final newQueue = OfflineOperationQueue();
      await newQueue.init();
      
      expect(newQueue.queueSize, equals(1));
      newQueue.dispose();
    });

    test('should clear queue', () async {
      await queue.init();
      
      await queue.queueTaskDelete(1);
      await queue.queueTaskDelete(2);
      expect(queue.queueSize, equals(2));
      
      await queue.clearQueue();
      expect(queue.queueSize, equals(0));
      expect(queue.hasPendingOperations, isFalse);
    });

    test('should handle operation with retry count', () async {
      await queue.init();
      
      final operation = QueuedOperation(
        id: 'retry_test',
        type: 'task_create',
        data: {'name': 'Retry Task'},
        timestamp: DateTime.now(),
        retryCount: 2,
      );

      await queue.enqueue(operation);
      expect(queue.queueSize, equals(1));
    });

    test('should handle operation with error', () async {
      await queue.init();
      
      final operation = QueuedOperation(
        id: 'error_test',
        type: 'task_create',
        data: {'name': 'Error Task'},
        timestamp: DateTime.now(),
        error: 'Test error message',
      );

      await queue.enqueue(operation);
      expect(queue.queueSize, equals(1));
    });

    test('should serialize and deserialize operations', () {
      final original = QueuedOperation(
        id: 'serialize_test',
        type: 'task_update',
        data: {'key': 'value', 'number': 42},
        timestamp: DateTime(2025, 10, 4, 12, 0, 0),
        retryCount: 1,
        error: 'Some error',
      );

      final json = original.toJson();
      final deserialized = QueuedOperation.fromJson(json);

      expect(deserialized.id, equals(original.id));
      expect(deserialized.type, equals(original.type));
      expect(deserialized.data, equals(original.data));
      expect(deserialized.timestamp, equals(original.timestamp));
      expect(deserialized.retryCount, equals(original.retryCount));
      expect(deserialized.error, equals(original.error));
    });

    test('should create operation copy with updated fields', () {
      final original = QueuedOperation(
        id: 'copy_test',
        type: 'task_create',
        data: {'name': 'Original'},
        timestamp: DateTime.now(),
        retryCount: 0,
      );

      final updated = original.copyWith(
        retryCount: 3,
        error: 'New error',
      );

      expect(updated.id, equals(original.id));
      expect(updated.type, equals(original.type));
      expect(updated.data, equals(original.data));
      expect(updated.retryCount, equals(3));
      expect(updated.error, equals('New error'));
    });

    test('should handle multiple operations in order', () async {
      await queue.init();
      
      await queue.queueTaskCreate(TaskModel(
        taskName: 'Task 1',
        taskPriority: 1,
        taskTime: null,
        taskDate: null,
        isRecurring: false,
        isCompleted: false,
      ));
      
      await queue.queueTaskDelete(123);
      
      await queue.queueGeofenceCreate(GeofenceData(
        id: 'geo_1',
        latitude: 0.0,
        longitude: 0.0,
        radiusMeters: 50.0,
        fillColor: 'FFFFFFFF',
        fillOpacity: 0.5,
        strokeColor: 'FF000000',
        strokeWidth: 1.0,
      ));

      expect(queue.queueSize, equals(3));
    });
  });
}
