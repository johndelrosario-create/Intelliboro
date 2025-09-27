import 'package:sqflite/sqflite.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:flutter/material.dart';
import 'package:intelliboro/services/database_service.dart';
import 'dart:developer' as developer;

class TaskRepository {
  static const String _tableName = 'tasks';

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
    return maps.map((map) => TaskModel.fromMap(map)).toList();
  }

  // Update a task
  Future<void> updateTask(TaskModel task) async {
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
  }

  Future<TaskModel?> getTaskById(int id) async {
    final db = await DatabaseService().mainDb;
    final rows = await db.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TaskModel.fromMap(rows.first);
  }

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