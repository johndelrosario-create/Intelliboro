import 'package:sqflite/sqflite.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:intelliboro/services/database_service.dart';

class TaskRepository {
  static const String _tableName = 'tasks';

  // Function for inserting task into database
  Future<void> insertTask(TaskModel task) async {
    debugPrint("[TaskRepository] insertTask: Getting database instance...");
    // final db = await database;
    final db = await DatabaseService().mainDb;
    debugPrint(
      "[TaskRepository] insertTask: Database instance received. Inserting task: ${task.taskName}",
    );
    await db.insert(
      _tableName,
      task.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
