import 'dart:developer' as developer;
import 'package:intelliboro/services/database_service.dart';
import 'package:intelliboro/services/geofencing_service.dart';

/// Service for cleaning up orphaned geofences
class GeofenceCleanupService {
  /// Clean up orphaned geofences where all associated tasks are completed
  /// or no tasks exist. Should be called on app startup.
  static Future<void> cleanupOrphanedGeofences() async {
    try {
      developer.log('[GeofenceCleanup] Starting orphaned geofence cleanup...');

      final db = await DatabaseService().mainDb;

      // Find all geofence IDs
      final allGeofences = await db.query('geofences', columns: ['id']);

      if (allGeofences.isEmpty) {
        developer.log('[GeofenceCleanup] No geofences found in database');
        return;
      }

      developer.log(
        '[GeofenceCleanup] Found ${allGeofences.length} geofence(s) to check',
      );

      int orphansRemoved = 0;

      for (final geofenceRow in allGeofences) {
        final geofenceId = geofenceRow['id'] as String;

        // Check if this geofence has any active (non-completed) tasks
        final activeTasks = await db.query(
          'tasks',
          columns: ['id', 'taskName', 'isCompleted'],
          where: 'geofence_id = ? AND isCompleted = 0',
          whereArgs: [geofenceId],
        );

        // If no active tasks, check if ALL tasks for this geofence are completed
        if (activeTasks.isEmpty) {
          final allTasksForGeofence = await db.query(
            'tasks',
            columns: ['id', 'taskName', 'isCompleted'],
            where: 'geofence_id = ?',
            whereArgs: [geofenceId],
          );

          // Orphaned if: no tasks at all, OR all tasks are completed
          final isOrphaned =
              allTasksForGeofence.isEmpty ||
              allTasksForGeofence.every((t) => t['isCompleted'] == 1);

          if (isOrphaned) {
            developer.log(
              '[GeofenceCleanup] Removing orphaned geofence: $geofenceId '
              '(${allTasksForGeofence.isEmpty ? "no tasks" : "all tasks completed"})',
            );

            try {
              // Remove from native geofencing service
              await GeofencingService().removeGeofence(geofenceId);

              // Remove from database
              final deletedRows = await db.delete(
                'geofences',
                where: 'id = ?',
                whereArgs: [geofenceId],
              );

              if (deletedRows > 0) {
                orphansRemoved++;
                developer.log(
                  '[GeofenceCleanup] Successfully removed orphaned geofence: $geofenceId',
                );
              }
            } catch (e, st) {
              developer.log(
                '[GeofenceCleanup] Error removing orphaned geofence $geofenceId: $e',
                error: e,
                stackTrace: st,
              );
            }
          }
        }
      }

      developer.log(
        '[GeofenceCleanup] Cleanup complete. Removed $orphansRemoved orphaned geofence(s)',
      );
    } catch (e, st) {
      developer.log(
        '[GeofenceCleanup] Error during orphaned geofence cleanup: $e',
        error: e,
        stackTrace: st,
      );
    }
  }
}
