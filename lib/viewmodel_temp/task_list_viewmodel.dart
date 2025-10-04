import 'package:flutter/material.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'dart:developer' as developer;

class TaskListViewModel extends ChangeNotifier {
  final GeofenceStorage _geofenceStorage;
  List<GeofenceData> _tasks = [];
  bool _isLoading = false;
  String? _errorMessage;

  TaskListViewModel({GeofenceStorage? geofenceStorage})
    : _geofenceStorage = geofenceStorage ?? GeofenceStorage();

  List<GeofenceData> get tasks => _tasks;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadTasks() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _tasks = await _geofenceStorage.loadGeofences();
      // Sort tasks by creation date (newest first) or by task name if needed
      // For now, using default order from storage.
      developer.log('[TaskListViewModel] Loaded ${_tasks.length} tasks.');
    } catch (e, stackTrace) {
      developer.log(
        '[TaskListViewModel] Error loading tasks',
        error: e,
        stackTrace: stackTrace,
      );
      _errorMessage = "Failed to load tasks: ${e.toString()}";
      _tasks = []; // Ensure tasks list is empty on error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Placeholder for task deletion if needed in the future
  Future<void> deleteTask(String geofenceId) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _geofenceStorage.deleteGeofence(geofenceId);
      await loadTasks(); // Refresh the list
      developer.log(
        '[TaskListViewModel] Deleted task with geofence ID: $geofenceId',
      );
    } catch (e) {
      _errorMessage = "Failed to delete task: ${e.toString()}";
      developer.log('[TaskListViewModel] Error deleting task: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
