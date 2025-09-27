import 'package:sqflite/sqflite.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:intelliboro/services/database_service.dart';
import 'dart:developer' as developer;

class TaskRepository {
  static const String _tableName = 'tasks';
  final Database? db;

  TaskRepository({this.db});

  // Function for inserting task into database
  Future<void> insertTask(TaskModel task) async {
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
      await db.insert(
        _tableName,
        task.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      developer.log(
        "[TaskRepository] insertTask: Task ${task.taskName} inserted successfully.",
      );
    } catch (e, stacktrace) {
      developer.log(
        "[TaskRepository] insertTask: FAILED to insert. DB Path: ${db.path}, isOpen: ${db.isOpen}. Error: $e\n$stacktrace",
      );
      rethrow;
    }
  }

  Future<List<TaskModel>> getTasks() async {
    final db = await DatabaseService().mainDb;
    final List<Map<String, dynamic>> maps = await db.query('tasks');
    return [
      // Converts the list of maps to a list of TaskModel objects
      for (final {
            'taskName': taskName,
            'taskPriority': taskPriority,
            'taskTime': taskTime,
            'taskDate': taskDate,
            'isRecurring': isRecurring,
            'isCompleted': isCompleted,
          }
          in maps)
        TaskModel(
          taskName: taskName,
          taskPriority: taskPriority,
          taskTime: TimeOfDay(
            hour: int.parse(taskTime.split(':')[0]),
            minute: int.parse(taskTime.split(':')[1]),
          ),
          taskDate: DateFormat('yyyy-MM-dd').parse(taskDate),
          isRecurring: isRecurring == 1,
          isCompleted: isCompleted == 1,
        ),
    ];
  }

  /// Get a task by name (returns the first match)
  Future<TaskModel?> getTaskByName(String taskName) async {
    final database = db ?? await DatabaseService().mainDb;

    try {
      final List<Map<String, dynamic>> maps = await database.query(
        _tableName,
        where: 'taskName = ?',
        whereArgs: [taskName],
        limit: 1,
      );

      if (maps.isEmpty) return null;

      final map = maps.first;
      return TaskModel(
        id: map['id'] as int?,
        taskName: map['taskName'] as String,
        taskPriority: map['taskPriority'] as int,
        taskTime: TimeOfDay(
          hour: int.parse((map['taskTime'] as String).split(':')[0]),
          minute: int.parse((map['taskTime'] as String).split(':')[1]),
        ),
        taskDate: DateTime.parse(map['taskDate'] as String),
        isRecurring: (map['isRecurring'] as int) == 1,
        isCompleted: (map['isCompleted'] as int) == 1,
      );
    } catch (e) {
      developer.log('[TaskRepository] Error getting task by name: $e');
      return null;
    }
  }
  // TODO: Edit a task
  // Future<void> updateTask(TaskModel task) async {
  //   debugPrint(
  //     "[TaskRepository] updateTask: Requesting DB from DatabaseService for task ID: ${task.id}...",
  //   );
  //   final db = await DatabaseService().mainDb;
  //   debugPrint(
  //     "[TaskRepository] updateTask: DB instance received. Updating task: ${task.id}",
  //   );
  //   await db.update(
  //     _tableName,
  //     task.toMap(),
  //     where: 'id = ?',
  //     whereArgs: [task.id],
  //   );
  //   debugPrint("[TaskRepository] updateTask: Task ${task.id} updated.");
  // }

  //TODO: Delete a task
  // Future<void> deleteTask(int id) async {
  //   debugPrint(
  //     "[TaskRepository] deleteTask: Requesting DB from DatabaseService for task ID: $id...",
  //   );
  //   final db = await DatabaseService().mainDb;
  //   debugPrint(
  //     "[TaskRepository] deleteTask: DB instance received. Deleting task: $id",
  //   );
  //   await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  //   debugPrint("[TaskRepository] deleteTask: Task $id deleted.");
  // }
}
