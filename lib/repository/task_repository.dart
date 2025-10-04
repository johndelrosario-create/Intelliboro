import 'package:sqflite/sqflite.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:flutter/material.dart';
import 'package:intelliboro/services/database_service.dart';
import 'dart:developer' as developer;
import 'package:intelliboro/services/geofencing_service.dart';
import 'package:intelliboro/services/task_alarm_service.dart';
import 'package:synchronized/synchronized.dart';

class TaskRepository {
  static const String _tableName = 'tasks';
  final _lock = Lock();

  // Function for inserting task into database
  Future<void> insertTask(TaskModel task) async {
    return _lock.synchronized(() async {
      debugPrint("[TaskRepository] insertTask: Getting database instance...");
      // final db = await database;
      final db = await DatabaseService().mainDb;
      developer.log(
        "[TaskRepository] insertTask: Received DB. Path: ${db.path}, isOpen: ${db.isOpen}",
      ); // ADD THIS
      if (!db.isOpen) {
        developer.log(
          "[TaskRepository] insertTask: CRITICAL - DB IS CLOSED *IMMEDIATELY AFTER* receiving from DatabaseService.mainDb!",
        );
        throw Exception(
          "DatabaseService.mainDb returned a closed database to TaskRepository.insertTask",
        );
      }
      developer.log(
        "[TaskRepository] insertTask: DB is open. Inserting task: ${task.taskName}",
      );
      try {
        final insertedId = await db.insert(
          _tableName,
          task.toMap()..remove('id'),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        developer.log(
          "[TaskRepository] insertTask: Task ${task.taskName} inserted successfully with id=$insertedId.",
        );

        // Schedule time-based alarm for this task
        try {
          final taskWithId = task.copyWith(id: insertedId);
          await TaskAlarmService().scheduleForTask(taskWithId);
        } catch (e, st) {
          developer.log(
            '[TaskRepository] insertTask: Failed to schedule alarm for new task id=$insertedId: $e',
            error: e,
            stackTrace: st,
          );
        }
      } catch (e, stacktrace) {
        developer.log(
          "[TaskRepository] insertTask: FAILED to insert. DB Path: ${db.path}, isOpen: ${db.isOpen}. Error: $e\n$stacktrace",
        );
        rethrow;
      }
    });
  }

  Future<List<TaskModel>> getTasks() async {
    return _lock.synchronized(() async {
      final db = await DatabaseService().mainDb;
      final List<Map<String, dynamic>> maps = await db.query('tasks');
      return maps.map((map) => TaskModel.fromMap(map)).toList();
    });
  }

  // Update a task
  Future<void> updateTask(TaskModel task) async {
    return _lock.synchronized(() async {
      debugPrint(
        "[TaskRepository] updateTask: Requesting DB from DatabaseService for task ID: ${task.id}...",
      );
      final db = await DatabaseService().mainDb;
      debugPrint(
        "[TaskRepository] updateTask: DB instance received. Updating task: ${task.id}",
      );
      await db.update(
        _tableName,
        task.toMap()..remove('id'), // Remove id from update data
        where: 'id = ?',
        whereArgs: [task.id],
      );
      debugPrint("[TaskRepository] updateTask: Task ${task.id} updated.");

      // Reschedule alarm to reflect updated date/time/recurrence
      try {
        await TaskAlarmService().scheduleForTask(task);
      } catch (e, st) {
        developer.log(
          '[TaskRepository] updateTask: Failed to schedule alarm for task id=${task.id}: $e',
          error: e,
          stackTrace: st,
        );
      }
    });
  }

  Future<TaskModel?> getTaskById(int id) async {
    return _lock.synchronized(() async {
      final db = await DatabaseService().mainDb;
      final rows = await db.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return TaskModel.fromMap(rows.first);
    });
  }

  /// Update geofence_id for a task by its database id.
  Future<int> updateTaskGeofenceIdById(int id, String geofenceId) async {
    return _lock.synchronized(() async {
      final db = await DatabaseService().mainDb;
      developer.log(
        '[TaskRepository] updateTaskGeofenceIdById: id=$id -> geofence_id=$geofenceId',
      );
      final count = await db.update(
        _tableName,
        {'geofence_id': geofenceId},
        where: 'id = ?',
        whereArgs: [id],
      );
      developer.log(
        '[TaskRepository] updateTaskGeofenceIdById: updated $count row(s) for id=$id',
      );
      return count;
    });
  }

  /// Update geofence_id for task(s) by name. Returns number of rows affected.
  /// Note: If multiple tasks share the same name, this will update all of them.
  Future<int> updateTaskGeofenceIdByName(
    String taskName,
    String geofenceId,
  ) async {
    return _lock.synchronized(() async {
      final db = await DatabaseService().mainDb;
      developer.log(
        '[TaskRepository] updateTaskGeofenceIdByName: name="$taskName" -> geofence_id=$geofenceId',
      );
      final count = await db.update(
        _tableName,
        {'geofence_id': geofenceId},
        where: 'taskName = ?',
        whereArgs: [taskName],
      );
      developer.log(
        '[TaskRepository] updateTaskGeofenceIdByName: updated $count row(s) for name="$taskName"',
      );
      return count;
    });
  }

  /// Delete a task by id
  Future<void> deleteTask(int id) async {
    return _lock.synchronized(() async {
      debugPrint("[TaskRepository] deleteTask: Deleting task id: $id...");
      final db = await DatabaseService().mainDb;

      // Read the task row first to inspect geofence association
      try {
        // Cancel any scheduled alarm for this task id
        try {
          await TaskAlarmService().cancelForTaskId(id);
        } catch (e) {
          developer.log(
            '[TaskRepository] deleteTask: Failed to cancel alarm for task id=$id: $e',
          );
        }

        String? geofenceId;

        // Use transaction to ensure atomicity of task and geofence deletion
        await db.transaction((txn) async {
          final rows = await txn.query(
            _tableName,
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );

          if (rows.isNotEmpty) {
            final row = rows.first;
            geofenceId = row['geofence_id'] as String?;
            developer.log(
              '[TaskRepository] deleteTask: Found geofence_id=$geofenceId for task $id',
            );
          }

          // Delete the task row within transaction
          await txn.delete(_tableName, where: 'id = ?', whereArgs: [id]);
          debugPrint("[TaskRepository] deleteTask: Task $id deleted.");

          // If there was an associated geofence, remove it from DB within the same transaction
          if (geofenceId != null && geofenceId!.isNotEmpty) {
            try {
              developer.log(
                '[TaskRepository] deleteTask: Removing associated geofence $geofenceId from DB',
              );
              // Remove DB row for geofence using the transaction
              await txn.delete(
                'geofences',
                where: 'id = ?',
                whereArgs: [geofenceId!],
              );
            } catch (e, st) {
              developer.log(
                '[TaskRepository] deleteTask: Failed to remove geofence from DB: $e',
                error: e,
                stackTrace: st,
              );
              rethrow; // Rethrow to rollback transaction
            }
          }
        });

        // After successful database transaction, remove from native geofence service
        if (geofenceId != null && geofenceId!.isNotEmpty) {
          try {
            await GeofencingService().removeGeofence(geofenceId!);
            developer.log(
              '[TaskRepository] deleteTask: Removed geofence $geofenceId from native service',
            );
          } catch (e, st) {
            developer.log(
              '[TaskRepository] deleteTask: Failed to remove geofence from native service: $e',
              error: e,
              stackTrace: st,
            );
            // Don't rethrow - native service failure shouldn't fail the operation
          }
        }
      } catch (e, st) {
        developer.log(
          '[TaskRepository] deleteTask: Error during deletion flow for task $id: $e',
          error: e,
          stackTrace: st,
        );
        rethrow;
      }
    });
  }
}
