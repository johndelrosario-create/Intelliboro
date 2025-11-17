import 'dart:developer' as developer;
import 'package:intelliboro/services/database_service.dart';

/// Diagnostic service to help debug geofence and task issues
class GeofenceDiagnosticService {
  /// Check all tasks in database and log their geofence associations
  Future<void> diagnoseGeofenceTasks() async {
    try {
      final db = await DatabaseService().mainDb;

      developer.log('=== GEOFENCE DIAGNOSTIC START ===');

      // Get all geofences
      final geofences = await db.query('geofences');
      developer.log('Found ${geofences.length} geofences in database:');
      for (final g in geofences) {
        developer.log(
          '  Geofence: id=${g['id']}, task=${g['task']}, '
          'lat=${g['latitude']}, lon=${g['longitude']}, radius=${g['radiusMeters']}m',
        );
      }

      developer.log('');

      // Get all tasks
      final tasks = await db.query('tasks');
      developer.log('Found ${tasks.length} tasks in database:');

      int completedCount = 0;
      int recurringCount = 0;
      int linkedCount = 0;
      int unlinkedCount = 0;

      for (final t in tasks) {
        final id = t['id'];
        final name = t['taskName'];
        final geofenceId = t['geofence_id'];
        final isCompleted = t['isCompleted'] == 1;
        final isRecurring = t['isRecurring'] == 1;
        final taskDate = t['taskDate'];
        final taskTime = t['taskTime'];
        final priority = t['taskPriority'];

        if (isCompleted) completedCount++;
        if (isRecurring) recurringCount++;
        if (geofenceId != null && geofenceId.toString().isNotEmpty) {
          linkedCount++;
        } else {
          unlinkedCount++;
        }

        developer.log('  Task $id: "$name"');
        developer.log('    geofence_id: ${geofenceId ?? "NULL/EMPTY"}');
        developer.log('    isCompleted: $isCompleted');
        developer.log('    isRecurring: $isRecurring');
        developer.log('    taskDate: $taskDate, taskTime: $taskTime');
        developer.log('    priority: $priority');

        if (isRecurring) {
          final pattern = t['recurring_pattern'];
          developer.log('    recurring_pattern: $pattern');
        }
        developer.log('');
      }

      developer.log('SUMMARY:');
      developer.log('  Total tasks: ${tasks.length}');
      developer.log('  Completed: $completedCount');
      developer.log('  Recurring: $recurringCount');
      developer.log('  Linked to geofence: $linkedCount');
      developer.log('  NOT linked to geofence: $unlinkedCount');
      developer.log('=== GEOFENCE DIAGNOSTIC END ===');
    } catch (e, st) {
      developer.log('Diagnostic failed: $e', error: e, stackTrace: st);
    }
  }

  /// Simulate what the background callback would find for a specific geofence
  Future<void> simulateGeofenceTrigger(String geofenceId) async {
    try {
      final db = await DatabaseService().mainDb;

      developer.log('=== SIMULATING GEOFENCE TRIGGER ===');
      developer.log('Geofence ID: $geofenceId');
      developer.log('');

      // This is the exact query the background callback uses
      final rows = await db.query(
        'tasks',
        columns: [
          'id',
          'geofence_id',
          'taskPriority',
          'taskName',
          'isCompleted',
          'isRecurring',
          'taskDate',
          'taskTime',
        ],
        where: 'geofence_id = ? AND isCompleted = 0',
        whereArgs: [geofenceId],
      );

      developer.log('Background callback would find ${rows.length} tasks:');

      if (rows.isEmpty) {
        developer.log('  NO TASKS FOUND!');
        developer.log('');
        developer.log(
          'Checking for tasks with this geofence_id (including completed):',
        );
        final allRows = await db.query(
          'tasks',
          columns: ['id', 'taskName', 'isCompleted', 'geofence_id'],
          where: 'geofence_id = ?',
          whereArgs: [geofenceId],
        );
        for (final r in allRows) {
          developer.log(
            '  Task ${r['id']}: "${r['taskName']}", '
            'isCompleted=${r['isCompleted']}, geofence_id=${r['geofence_id']}',
          );
        }
      } else {
        for (final r in rows) {
          developer.log('  Task ${r['id']}: "${r['taskName']}"');
          developer.log('    Priority: ${r['taskPriority']}');
          developer.log('    Completed: ${r['isCompleted']}');
          developer.log('    Recurring: ${r['isRecurring']}');
          developer.log('    Date/Time: ${r['taskDate']} ${r['taskTime']}');
        }
      }

      developer.log('=== SIMULATION END ===');
    } catch (e, st) {
      developer.log('Simulation failed: $e', error: e, stackTrace: st);
    }
  }
}
