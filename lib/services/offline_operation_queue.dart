import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/queued_operation.dart';
import '../repository/task_repository.dart';
import '../services/geofence_storage.dart';
import '../model/task_model.dart';
import '../models/geofence_data.dart';

/// Service to manage offline operations queue
/// Stores operations when offline and syncs when connectivity is restored
class OfflineOperationQueue {
  static final OfflineOperationQueue _instance =
      OfflineOperationQueue._internal();
  factory OfflineOperationQueue() => _instance;
  OfflineOperationQueue._internal();

  static const String _queueKey = 'offline_operation_queue';
  static const int _maxRetries = 3;
  static const int _baseBackoffSeconds = 2; // Base delay for exponential backoff

  final List<QueuedOperation> _queue = [];
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isProcessing = false;
  bool _isOnline = true;

  /// Initialize the service and load persisted queue
  Future<void> init() async {
    await _loadQueue();
    await _checkConnectivity();
    _startConnectivityMonitoring();

    // Process queue if online
    if (_isOnline && _queue.isNotEmpty) {
      unawaited(_processQueue());
    }
  }

  /// Add an operation to the queue
  Future<void> enqueue(QueuedOperation operation) async {
    debugPrint('[OfflineQueue] Enqueuing operation: ${operation.type}');
    
    // Check for duplicates - remove older operations with same deduplication key
    final dedupKey = operation.deduplicationKey;
    _queue.removeWhere((existingOp) {
      if (existingOp.deduplicationKey == dedupKey) {
        debugPrint(
          '[OfflineQueue] Removing duplicate operation: ${existingOp.id}',
        );
        return true;
      }
      return false;
    });
    
    _queue.add(operation);
    
    // Sort queue by priority (high to low) and then by timestamp (old to new)
    _queue.sort((a, b) {
      final priorityCompare = b.priority.value.compareTo(a.priority.value);
      if (priorityCompare != 0) return priorityCompare;
      return a.timestamp.compareTo(b.timestamp);
    });
    
    await _saveQueue();

    // Try to process immediately if online
    if (_isOnline && !_isProcessing) {
      unawaited(_processQueue());
    }
  }

  /// Create a queued task creation operation
  Future<void> queueTaskCreate(TaskModel task) async {
    final operation = QueuedOperation(
      id: 'task_create_${DateTime.now().millisecondsSinceEpoch}',
      type: 'task_create',
      data: task.toMap(),
      timestamp: DateTime.now(),
    );
    await enqueue(operation);
  }

  /// Create a queued task update operation
  Future<void> queueTaskUpdate(TaskModel task) async {
    final operation = QueuedOperation(
      id: 'task_update_${task.id}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'task_update',
      data: task.toMap(),
      timestamp: DateTime.now(),
    );
    await enqueue(operation);
  }

  /// Create a queued task delete operation
  Future<void> queueTaskDelete(int taskId) async {
    final operation = QueuedOperation(
      id: 'task_delete_${taskId}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'task_delete',
      data: {'taskId': taskId},
      timestamp: DateTime.now(),
    );
    await enqueue(operation);
  }

  /// Create a queued geofence create operation
  Future<void> queueGeofenceCreate(GeofenceData geofence) async {
    final operation = QueuedOperation(
      id: 'geofence_create_${DateTime.now().millisecondsSinceEpoch}',
      type: 'geofence_create',
      data: geofence.toJson(),
      timestamp: DateTime.now(),
    );
    await enqueue(operation);
  }

  /// Create a queued geofence update operation
  Future<void> queueGeofenceUpdate(GeofenceData geofence) async {
    final operation = QueuedOperation(
      id:
          'geofence_update_${geofence.id}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'geofence_update',
      data: geofence.toJson(),
      timestamp: DateTime.now(),
    );
    await enqueue(operation);
  }

  /// Create a queued geofence delete operation
  Future<void> queueGeofenceDelete(String geofenceId) async {
    final operation = QueuedOperation(
      id:
          'geofence_delete_${geofenceId}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'geofence_delete',
      data: {'geofenceId': geofenceId},
      timestamp: DateTime.now(),
    );
    await enqueue(operation);
  }

  /// Get the current queue size
  int get queueSize => _queue.length;

  /// Check if there are pending operations
  bool get hasPendingOperations => _queue.isNotEmpty;

  /// Get online status
  bool get isOnline => _isOnline;

  /// Process all queued operations
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty || !_isOnline) {
      return;
    }

    _isProcessing = true;
    debugPrint('[OfflineQueue] Processing ${_queue.length} queued operations');

    final operationsToProcess = List<QueuedOperation>.from(_queue);
    final now = DateTime.now();

    for (final operation in operationsToProcess) {
      // Check if operation is ready for retry (respects exponential backoff)
      if (operation.nextRetryTime != null &&
          now.isBefore(operation.nextRetryTime!)) {
        debugPrint(
          '[OfflineQueue] Skipping ${operation.type} - backoff until ${operation.nextRetryTime}',
        );
        continue;
      }

      try {
        await _executeOperation(operation);
        _queue.remove(operation);
        debugPrint('[OfflineQueue] Successfully executed: ${operation.type}');
      } catch (e) {
        debugPrint('[OfflineQueue] Error executing ${operation.type}: $e');

        // Update retry count and calculate exponential backoff
        final index = _queue.indexOf(operation);
        if (index >= 0) {
          final newRetryCount = operation.retryCount + 1;
          
          // Calculate exponential backoff: 2^retryCount * base seconds
          final backoffSeconds =
              _baseBackoffSeconds * (1 << newRetryCount.clamp(0, 5));
          final nextRetry = DateTime.now().add(
            Duration(seconds: backoffSeconds),
          );

          final updated = operation.copyWith(
            retryCount: newRetryCount,
            error: e.toString(),
            nextRetryTime: nextRetry,
          );

          if (updated.retryCount >= _maxRetries) {
            debugPrint(
              '[OfflineQueue] Max retries reached for ${operation.type}, removing from queue',
            );
            _queue.removeAt(index);
          } else {
            debugPrint(
              '[OfflineQueue] Will retry ${operation.type} after ${backoffSeconds}s (attempt ${newRetryCount + 1}/$_maxRetries)',
            );
            _queue[index] = updated;
          }
        }
      }
    }

    await _saveQueue();
    _isProcessing = false;

    debugPrint(
      '[OfflineQueue] Queue processing complete. Remaining: ${_queue.length}',
    );
  }

  /// Execute a single operation
  Future<void> _executeOperation(QueuedOperation operation) async {
    switch (operation.type) {
      case 'task_create':
        final task = TaskModel.fromMap(operation.data);
        await TaskRepository().insertTask(task);
        break;

      case 'task_update':
        final task = TaskModel.fromMap(operation.data);
        await TaskRepository().updateTask(task);
        break;

      case 'task_delete':
        final taskId = operation.data['taskId'] as int;
        await TaskRepository().deleteTask(taskId);
        break;

      case 'geofence_create':
        final geofence = GeofenceData.fromJson(operation.data);
        await GeofenceStorage().saveGeofence(geofence);
        break;

      case 'geofence_update':
        final geofence = GeofenceData.fromJson(operation.data);
        await GeofenceStorage().saveGeofence(geofence);
        break;

      case 'geofence_delete':
        final geofenceId = operation.data['geofenceId'] as String;
        await GeofenceStorage().deleteGeofence(geofenceId);
        break;

      default:
        debugPrint('[OfflineQueue] Unknown operation type: ${operation.type}');
    }
  }

  /// Load queue from persistent storage
  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString(_queueKey);

      if (queueJson != null) {
        final List<dynamic> decoded = jsonDecode(queueJson);
        _queue.clear();
        _queue.addAll(
          decoded.map(
            (json) => QueuedOperation.fromJson(json as Map<String, dynamic>),
          ),
        );
        debugPrint(
          '[OfflineQueue] Loaded ${_queue.length} operations from storage',
        );
      }
    } catch (e) {
      debugPrint('[OfflineQueue] Error loading queue: $e');
    }
  }

  /// Save queue to persistent storage
  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = jsonEncode(_queue.map((op) => op.toJson()).toList());
      await prefs.setString(_queueKey, queueJson);
      debugPrint('[OfflineQueue] Saved ${_queue.length} operations to storage');
    } catch (e) {
      debugPrint('[OfflineQueue] Error saving queue: $e');
    }
  }

  /// Check current connectivity status
  Future<void> _checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _isOnline = result.any((r) => r != ConnectivityResult.none);
      debugPrint(
        '[OfflineQueue] Connectivity check: ${_isOnline ? "Online" : "Offline"}',
      );
    } catch (e) {
      debugPrint('[OfflineQueue] Error checking connectivity: $e');
      _isOnline = true; // Assume online on error
    }
  }

  /// Start monitoring connectivity changes
  void _startConnectivityMonitoring() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final wasOnline = _isOnline;
        _isOnline = results.any((r) => r != ConnectivityResult.none);

        debugPrint(
          '[OfflineQueue] Connectivity changed: ${_isOnline ? "Online" : "Offline"}',
        );

        // If we just came online and have queued operations, process them
        if (!wasOnline && _isOnline && _queue.isNotEmpty) {
          debugPrint('[OfflineQueue] Connection restored, processing queue');
          unawaited(_processQueue());
        }
      },
      onError: (error) {
        debugPrint('[OfflineQueue] Connectivity monitoring error: $error');
      },
    );
  }

  /// Clear all queued operations
  Future<void> clearQueue() async {
    _queue.clear();
    await _saveQueue();
    debugPrint('[OfflineQueue] Queue cleared');
  }

  /// Manually trigger queue processing
  Future<void> processQueueManually() async {
    await _checkConnectivity();
    if (_isOnline) {
      await _processQueue();
    } else {
      debugPrint('[OfflineQueue] Cannot process queue: device is offline');
    }
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }
}

/// Helper to avoid await warnings for fire-and-forget futures
void unawaited(Future<void> future) {
  // Intentionally empty - just prevents linter warnings
}
