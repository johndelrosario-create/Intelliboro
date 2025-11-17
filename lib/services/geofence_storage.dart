import 'dart:developer' as developer;
import 'package:intelliboro/services/database_service.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:sqflite/sqflite.dart'; // Import sqflite

class GeofenceStorage {
  final DatabaseService _databaseService;
  // This field will hold the DB connection passed to the constructor, or the mainDb.
  Database? _dbInstance;

  // Optional Database for use by background isolates primarily.
  GeofenceStorage({Database? db})
    : _databaseService = DatabaseService(),
      _dbInstance = db;

  // Helper to get the appropriate DB instance.
  // If _dbInstance (from constructor) is available, use it.
  // Otherwise, use the mainDb from DatabaseService.
  Future<Database> get _db async {
    if (_dbInstance != null && _dbInstance!.isOpen) {
      // developer.log('[GeofenceStorage] Using provided DB instance.');
      return _dbInstance!;
    }
    // developer.log('[GeofenceStorage] Using mainDb from DatabaseService.');
    return await _databaseService.mainDb;
  }

  Future<List<GeofenceData>> loadGeofences({
    bool includeCompleted = false,
  }) async {
    try {
      final db = await _db; // Use the getter
      developer.log('[GeofenceStorage] Loading geofences from database...');

      final geofences = await _databaseService.getAllGeofences(db); // Pass db
      developer.log('[GeofenceStorage] Raw geofences from DB: $geofences');

      final result =
          geofences.map<GeofenceData>((json) {
            try {
              return GeofenceData.fromJson(Map<String, dynamic>.from(json));
            } catch (e, stackTrace) {
              developer.log(
                '[GeofenceStorage] Error parsing geofence: $json',
                error: e,
                stackTrace: stackTrace,
              );
              rethrow;
            }
          }).toList();

      developer.log(
        '[GeofenceStorage] Successfully loaded ${result.length} geofences',
      );

      // Filter out geofences with only completed tasks unless explicitly requested
      if (!includeCompleted) {
        final filteredResult = <GeofenceData>[];
        for (final geofence in result) {
          try {
            // Check if this geofence has any non-completed tasks
            final tasks = await db.query(
              'tasks',
              columns: ['id', 'isCompleted'],
              where: 'geofence_id = ?',
              whereArgs: [geofence.id],
            );

            if (tasks.isEmpty) {
              // No tasks linked - keep the geofence (might be orphaned, user can manage it)
              filteredResult.add(geofence);
            } else {
              // Check if at least one task is not completed
              final hasActiveTask = tasks.any((t) => t['isCompleted'] != 1);
              if (hasActiveTask) {
                filteredResult.add(geofence);
              } else {
                developer.log(
                  '[GeofenceStorage] Filtering out geofence ${geofence.id} - all tasks completed',
                );
              }
            }
          } catch (e) {
            developer.log(
              '[GeofenceStorage] Error checking tasks for geofence ${geofence.id}: $e',
            );
            // On error, include the geofence to be safe
            filteredResult.add(geofence);
          }
        }
        developer.log(
          '[GeofenceStorage] Filtered to ${filteredResult.length} active geofences',
        );
        return filteredResult;
      }

      return result;
    } catch (e, stackTrace) {
      developer.log(
        '[GeofenceStorage] Error in loadGeofences',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> saveGeofence(GeofenceData geofence) async {
    try {
      final db = await _db; // Use the getter
      developer.log('[GeofenceStorage] Saving geofence: ${geofence.id}');

      final json = geofence.toJson();
      developer.log('[GeofenceStorage] Geofence JSON to save: $json');

      await _databaseService.insertGeofence(db, json); // Pass db
      developer.log('[GeofenceStorage] Geofence saved successfully');
    } catch (e, stackTrace) {
      developer.log(
        '[GeofenceStorage] Error saving geofence: $e',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> deleteGeofence(String id) async {
    try {
      final db = await _db; // Use the getter
      developer.log('[GeofenceStorage] Deleting geofence: $id');
      await _databaseService.deleteGeofence(db, id); // Pass db
    } catch (e) {
      developer.log('[GeofenceStorage] Error deleting geofence: $e', error: e);
      rethrow;
    }
  }

  /// Clear all geofences from storage.
  /// This is an alias for [clearGeofences] for backward compatibility.
  Future<void> clearAll() async {
    return clearGeofences();
  }

  /// Clear all geofences from storage.
  Future<void> clearGeofences() async {
    try {
      final db = await _db; // Use the getter
      developer.log('[GeofenceStorage] Clearing all geofences');
      await _databaseService.clearAllGeofences(db); // Pass db
    } catch (e) {
      developer.log('[GeofenceStorage] Error clearing geofences: $e', error: e);
      rethrow;
    }
  }

  Future<GeofenceData?> getGeofenceById(
    String id, {
    Database? providedDb,
  }) async {
    try {
      // If a DB is explicitly provided (e.g., from a background isolate), use it.
      // Otherwise, use the default _db getter (which might be _dbInstance or mainDb).
      final db = providedDb ?? await _db;
      developer.log('[GeofenceStorage] Fetching geofence by ID: $id');
      final geofenceJson = await _databaseService.getGeofenceById(
        db,
        id,
      ); // Pass db
      if (geofenceJson != null) {
        developer.log('[GeofenceStorage] Found geofence JSON: $geofenceJson');
        return GeofenceData.fromJson(Map<String, dynamic>.from(geofenceJson));
      }
      developer.log('[GeofenceStorage] No geofence found for ID: $id');
      return null;
    } catch (e, stackTrace) {
      developer.log(
        '[GeofenceStorage] Error fetching geofence by ID: $id',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  // Removed _initialize and _ensureInitialized as DB management is now more direct
  // via the _db getter or passed-in DB instance.
}
