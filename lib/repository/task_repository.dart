import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intelliboro/model/task_model.dart';

class TaskRepository {
  static Database? _database;
  // For database
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await openDatabase(
      join(await getDatabasesPath(), 'intelliboro.db'),
      // When first created, create a table to store tasks
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE tasks(id INTEGER PRIMARY KEY, taskName TEXT, taskPriority INTEGER, taskTime TEXT, taskDate TEXT, isRecurring INTEGER, isCompleted INTEGER)',
        );
      },
      version: 1,
    );
    return _database!;
  }
  // Function for inserting task into database
  Future<void> insertTask(TaskModel task) async {
    final db = await database;
    await db.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

}
