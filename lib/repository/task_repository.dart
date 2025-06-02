import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

class TaskRepository {
  static Database? _database;
  static const String _dbName = 'intelliboro.db';
  static bool _onCreateExecuted =
      false; // Flag to check if onCreate was run in this session

  // For database
  Future<Database> get database async {
    debugPrint("[TaskRepository] Accessing database getter...");
    if (_database != null) {
      debugPrint("[TaskRepository] Database instance already exists.");
      return _database!;
    }
    debugPrint("[TaskRepository] Database instance is null, initializing...");

    String path = join(await getDatabasesPath(), _dbName);
    debugPrint("[TaskRepository] Database path: $path");

    _database = await openDatabase(
      path,
      onCreate: (db, version) async {
        debugPrint("[TaskRepository] onCreate: Creating tasks table...");
        await db.execute(
          'CREATE TABLE tasks(id INTEGER PRIMARY KEY AUTOINCREMENT, taskName TEXT, taskPriority INTEGER, taskTime TEXT, taskDate TEXT, isRecurring INTEGER, isCompleted INTEGER)',
        );
        debugPrint("[TaskRepository] onCreate: Tasks table created.");
        _onCreateExecuted = true; // Set flag
      },
      version: 1,
    );

    // After attempting to open, if onCreate wasn't run and table is still missing, something is wrong.
    if (!_onCreateExecuted) {
      var tableCheck = await _database!.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='tasks'",
      );
      if (tableCheck.isEmpty) {
        debugPrint(
          "[TaskRepository] onCreate was NOT executed and 'tasks' table still missing. Forcing delete and re-open.",
        );
        await _database!.close(); // Close first
        await deleteDatabase(path); // Delete the database file
        _database = null; // Reset static instance
        _onCreateExecuted = false; // Reset flag
        return await database; // Recurse to try opening again. Should now trigger onCreate.
      }
    }

    debugPrint("[TaskRepository] Database initialized and instance set.");
    return _database!;
  }

  // Function for inserting task into database
  Future<void> insertTask(TaskModel task) async {
    debugPrint("[TaskRepository] insertTask: Getting database instance...");
    final db = await database;
    debugPrint(
      "[TaskRepository] insertTask: Database instance received. Inserting task: ${task.taskName}",
    );
    await db.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<TaskModel>> getTasks() async {
    final db = await database;
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
}
