import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:developer' as developer;
import 'package:synchronized/synchronized.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._constructor();
  static Database? _mainIsolateDatabase; // Renamed for clarity
  static const String _dbName = 'intelliboro.db';
  static const int _dbVersion = 10;
  static const String _geofencesTableName = 'geofences';
  static const String _tasksTableName = 'tasks';
  static const String _notificationHistoryTableName = 'notification_history';
  static const String _taskHistoryTableName = 'task_history';

  final _lock = Lock();

  // Lock to prevent concurrent initialization from main isolate
  // static bool _isInitializingMainDB = false;
  static Completer<Database>? _dbInitializingCompleter;

  factory DatabaseService() => _instance;

  DatabaseService._constructor();

  // For the main UI isolate, uses a shared instance
  Future<Database> get mainDb async {
    if (_mainIsolateDatabase != null && _mainIsolateDatabase!.isOpen) {
      return _mainIsolateDatabase!;
    }

    return await _lock.synchronized(() async {
      // Check again inside the lock
      if (_mainIsolateDatabase != null && _mainIsolateDatabase!.isOpen) {
        return _mainIsolateDatabase!;
      }

      try {
        final db = await _openDatabaseConnection(
          readOnly: false,
          singleInstance: true,
        );
        _mainIsolateDatabase = db;
        return db;
      } catch (e) {
        developer.log("[DatabaseService] Failed to initialize database: $e");
        rethrow;
      }
    });
  }

  //Used in callback
  // For background isolates to get a fresh, independent connection
  Future<Database> openNewBackgroundConnection({bool readOnly = true}) async {
    developer.log(
      "[DatabaseService] Opening new background DB connection (readOnly: $readOnly, singleInstance: false).",
    );
    return await _openDatabaseConnection(
      readOnly: readOnly,
      singleInstance: false, // Explicitly false for background connections
    );
  }

  // Core method to open a database connection
  Future<Database> _openDatabaseConnection({
    required bool readOnly,
    required bool singleInstance,
  }) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    developer.log("[DatabaseService] Opening database at: $path");

    final db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onDowngrade: onDatabaseDowngradeDelete,
      readOnly: readOnly,
      singleInstance: singleInstance,
    );

    if (!db.isOpen) {
      throw Exception("Database failed to open");
    }

    return db;
  }

  // onCreate and onUpgrade remain static or top-level like as they define schema
  static Future<void> _onCreate(Database db, int version) async {
    developer.log(
      '[DatabaseService] _onCreate: Creating tables for version $version',
    );
    await _createAllTables(db);
  }

  static Future<void> _createAllTables(Database db) async {
    developer.log(
      '[DatabaseService] _createAllTables: Creating table $_geofencesTableName',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_geofencesTableName
       (
        id TEXT PRIMARY KEY,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        radius_meters REAL NOT NULL,
        fill_color TEXT NOT NULL,
        fill_opacity REAL NOT NULL,
        stroke_color TEXT NOT NULL,
        stroke_width REAL NOT NULL,
        task TEXT,
        created_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${_geofencesTableName}_id ON $_geofencesTableName (id)',
    );
    developer.log(
      '[DatabaseService] _onCreate: $_geofencesTableName and index created.',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tasksTableName
       (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        taskName TEXT NOT NULL,
        taskPriority INTEGER NOT NULL,
        taskTime TEXT,
        taskDate TEXT,
        isRecurring INTEGER NOT NULL,
        isCompleted INTEGER NOT NULL,
        recurring_pattern TEXT,
        geofence_id TEXT,
        notification_sound TEXT,
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        FOREIGN KEY (geofence_id) REFERENCES $_geofencesTableName(id) ON DELETE SET NULL
      )
    ''');
    developer.log('[DatabaseService] _onCreate: $_tasksTableName created.');

    // Create index for geofence_id for better query performance
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_geofence_id ON $_tasksTableName (geofence_id)',
    );

    developer.log(
      '[DatabaseService] _createAllTables: Creating table $_notificationHistoryTableName',
    );
    await db.execute(''' 
      CREATE TABLE IF NOT EXISTS $_notificationHistoryTableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        notification_id INTEGER NOT NULL,
        geofence_id TEXT NOT NULL,
        task_name TEXT,
        event_type TEXT NOT NULL,
        body TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    developer.log(
      '[DatabaseService] _onCreate: $_notificationHistoryTableName created.',
    );

    developer.log(
      '[DatabaseService] _createAllTables: Creating table $_taskHistoryTableName',
    );
    // Make end_time, duration_seconds and completion_date nullable so we can
    // create an open session (start_time present, end_time null) and update it later.
    await db.execute(''' 
      CREATE TABLE IF NOT EXISTS $_taskHistoryTableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER,
        task_name TEXT,
        task_priority INTEGER,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        duration_seconds INTEGER,
        completion_date TEXT,
        geofence_id TEXT,
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        FOREIGN KEY (task_id) REFERENCES $_tasksTableName(id) ON DELETE SET NULL,
        FOREIGN KEY (geofence_id) REFERENCES $_geofencesTableName(id) ON DELETE SET NULL
      )
    ''');
    developer.log(
      '[DatabaseService] _createAllTables: $_taskHistoryTableName created.',
    );
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    developer.log(
      '[DatabaseService] _onUpgrade: Upgrading from $oldVersion to $newVersion',
    );

    // Handle specific version upgrades step by step
    if (oldVersion < 2) {
      // Add upgrade logic for version 2 if needed
    }

    if (oldVersion < 3) {
      // Add upgrade logic for version 3 if needed
    }

    if (oldVersion < 4) {
      // Add geofence_id column to tasks table
      try {
        await db.execute('ALTER TABLE tasks ADD COLUMN geofence_id TEXT');
        developer.log(
          '[DatabaseService] Added geofence_id column to tasks table',
        );
      } catch (e) {
        developer.log(
          '[DatabaseService] Note: geofence_id column may already exist: $e',
        );
      }

      // Create index for geofence_id for better query performance
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_tasks_geofence_id ON tasks (geofence_id)',
        );
        developer.log('[DatabaseService] Created index for geofence_id column');
      } catch (e) {
        developer.log('[DatabaseService] Error creating geofence_id index: $e');
      }
    }

    if (oldVersion < 5) {
      // Add task_history table
      try {
        await db.execute(''' 
          CREATE TABLE IF NOT EXISTS $_taskHistoryTableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id INTEGER,
            task_name TEXT,
            task_priority INTEGER,
            start_time INTEGER NOT NULL,
            end_time INTEGER,
            duration_seconds INTEGER,
            completion_date TEXT,
            geofence_id TEXT,
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            FOREIGN KEY (task_id) REFERENCES $_tasksTableName(id) ON DELETE SET NULL,
            FOREIGN KEY (geofence_id) REFERENCES $_geofencesTableName(id) ON DELETE SET NULL
          )
        ''');
        developer.log('[DatabaseService] Added task_history table');

        // Create index for performance
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_task_history_completion_date ON $_taskHistoryTableName (completion_date)',
        );
        developer.log('[DatabaseService] Created index for task_history table');
      } catch (e) {
        developer.log(
          '[DatabaseService] Error creating task_history table: $e',
        );
      }
    }

    if (oldVersion < 6) {
      // Add recurring_pattern column to tasks table
      try {
        await db.execute(
          'ALTER TABLE $_tasksTableName ADD COLUMN recurring_pattern TEXT',
        );
        developer.log(
          '[DatabaseService] Added recurring_pattern column to tasks table',
        );
      } catch (e) {
        developer.log(
          '[DatabaseService] Note: recurring_pattern column may already exist: $e',
        );
      }
    }

    if (oldVersion < 7) {
      // Version 7: Ensure proper geofence_id column and index handling
      // This addresses any schema inconsistencies with the geofence_id column
      try {
        // First, check if the column exists by trying to query it
        await db.rawQuery('SELECT geofence_id FROM tasks LIMIT 1');
        developer.log('[DatabaseService] geofence_id column already exists');
      } catch (e) {
        // Column doesn't exist, add it
        try {
          await db.execute('ALTER TABLE tasks ADD COLUMN geofence_id TEXT');
          developer.log(
            '[DatabaseService] Added missing geofence_id column to tasks table',
          );
        } catch (alterError) {
          developer.log(
            '[DatabaseService] Error adding geofence_id column: $alterError',
          );
        }
      }

      // Always try to create the index (IF NOT EXISTS will handle duplicates)
      try {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_tasks_geofence_id ON tasks (geofence_id)',
        );
        developer.log(
          '[DatabaseService] Ensured idx_tasks_geofence_id index exists',
        );
      } catch (e) {
        developer.log('[DatabaseService] Error ensuring geofence_id index: $e');
      }
    }

    if (oldVersion < 8) {
      // Add notification_sound column to tasks table
      try {
        await db.execute(
          'ALTER TABLE $_tasksTableName ADD COLUMN notification_sound TEXT',
        );
        developer.log(
          '[DatabaseService] Added notification_sound column to tasks table',
        );
      } catch (e) {
        developer.log(
          '[DatabaseService] Note: notification_sound column may already exist: $e',
        );
      }
    }

    if (oldVersion < 9) {
      // Version 9: Ensure notification_sound column exists
      // This is a safety check for users who may have had issues with the v8 migration
      try {
        // Check if the column exists by trying to query it
        await db.rawQuery(
          'SELECT notification_sound FROM $_tasksTableName LIMIT 1',
        );
        developer.log(
          '[DatabaseService] notification_sound column already exists',
        );
      } catch (e) {
        // Column doesn't exist, add it
        try {
          await db.execute(
            'ALTER TABLE $_tasksTableName ADD COLUMN notification_sound TEXT',
          );
          developer.log(
            '[DatabaseService] Added missing notification_sound column to tasks table',
          );
        } catch (alterError) {
          developer.log(
            '[DatabaseService] Error adding notification_sound column: $alterError',
          );
        }
      }
    }

    if (oldVersion < 10) {
      // Fix taskTime and taskDate columns to allow NULL values
      // SQLite doesn't support ALTER COLUMN, so we need to recreate the table
      try {
        developer.log(
          '[DatabaseService] Migrating tasks table to allow NULL taskTime/taskDate (v10)',
        );

        // Create new table with correct schema
        await db.execute('''
          CREATE TABLE tasks_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            taskName TEXT NOT NULL,
            taskPriority INTEGER NOT NULL,
            taskTime TEXT,
            taskDate TEXT,
            isRecurring INTEGER NOT NULL,
            isCompleted INTEGER NOT NULL,
            recurring_pattern TEXT,
            geofence_id TEXT,
            notification_sound TEXT,
            created_at INTEGER DEFAULT (strftime('%s', 'now')),
            FOREIGN KEY (geofence_id) REFERENCES $_geofencesTableName(id) ON DELETE SET NULL
          )
        ''');

        // Copy data from old table to new table
        await db.execute('''
          INSERT INTO tasks_new (id, taskName, taskPriority, taskTime, taskDate, 
                                isRecurring, isCompleted, recurring_pattern, geofence_id, 
                                notification_sound, created_at)
          SELECT id, taskName, taskPriority, taskTime, taskDate, 
                 isRecurring, isCompleted, recurring_pattern, geofence_id, 
                 notification_sound, created_at
          FROM $_tasksTableName
        ''');

        // Drop old table and rename new table
        await db.execute('DROP TABLE $_tasksTableName');
        await db.execute('ALTER TABLE tasks_new RENAME TO $_tasksTableName');

        developer.log(
          '[DatabaseService] Successfully migrated tasks table to v10',
        );
      } catch (e) {
        developer.log('[DatabaseService] Error migrating tasks table: $e');
        // If migration fails, continue - the new schema in _createAllTables will be used for new installs
      }
    }

    // Ensure any missing tables are created (for safety)
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_notificationHistoryTableName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          notification_id INTEGER NOT NULL,
          geofence_id TEXT NOT NULL,
          task_name TEXT,
          event_type TEXT NOT NULL,
          body TEXT NOT NULL,
          timestamp INTEGER NOT NULL
        )
      ''');
      developer.log(
        '[DatabaseService] Ensured $_notificationHistoryTableName exists',
      );
    } catch (e) {
      developer.log(
        '[DatabaseService] Error ensuring notification_history table exists: $e',
      );
    }
  }

  //Handle downgrades
  static Future<void> onDatabaseDowngradeDelete(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    developer.log(
      '[DatabaseService] onDowngrade: Downgrading from $oldVersion to $newVersion. Deleting all tables and recreating. DB path: ${db.path}',
    );
    List<Map<String, dynamic>> tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_metadata'",
    );
    for (Map<String, dynamic> table in tables) {
      String tableName = table['name'];
      try {
        await db.execute('DROP TABLE IF EXISTS $tableName');
        developer.log(
          '[DatabaseService] onDowngrade: Dropped table $tableName',
        );
      } catch (e) {
        developer.log(
          '[DatabaseService] onDowngrade: Error dropping table $tableName: $e',
        );
      }
    }
    await _onCreate(
      db,
      newVersion,
    ); // Recreate schema for the new (lower) version
  }

  // Notification History Methods
  Future<void> insertNotificationHistory(
    Database db,
    Map<String, dynamic> notificationData,
  ) async {
    try {
      await db.insert(
        _notificationHistoryTableName,
        notificationData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      developer.log(
        '[DatabaseService] Inserted notification history: $notificationData',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[DatabaseService] Error inserting notification history',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAllNotificationHistory(
    Database db,
  ) async {
    try {
      final result = await db.query(
        _notificationHistoryTableName,
        orderBy: 'timestamp DESC',
      );
      developer.log(
        '[DatabaseService] Retrieved ${result.length} notification history records',
      );
      return result;
    } catch (e, stackTrace) {
      developer.log(
        '[DatabaseService] Error getting notification history',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> clearAllNotificationHistory(Database db) async {
    try {
      final count = await db.delete(_notificationHistoryTableName);
      developer.log(
        '[DatabaseService] Cleared $count notification history records',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[DatabaseService] Error clearing notification history',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // Task History Methods
  Future<void> insertTaskHistory(
    Database db,
    Map<String, dynamic> historyData,
  ) async {
    try {
      await db.insert(
        _taskHistoryTableName,
        historyData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      developer.log(
        '[DatabaseService] Inserted task history: ${historyData['task_name']}',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[DatabaseService] Error inserting task history',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAllTaskHistory(Database db) async {
    try {
      final result = await db.query(
        _taskHistoryTableName,
        orderBy: 'completion_date DESC, end_time DESC',
      );
      developer.log(
        '[DatabaseService] Retrieved ${result.length} task history records',
      );
      return result;
    } catch (e, stackTrace) {
      developer.log(
        '[DatabaseService] Error getting task history',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getTaskHistoryByDateRange(
    Database db,
    String startDate,
    String endDate,
  ) async {
    try {
      final result = await db.query(
        _taskHistoryTableName,
        where: 'completion_date >= ? AND completion_date <= ?',
        whereArgs: [startDate, endDate],
        orderBy: 'completion_date DESC, end_time DESC',
      );
      developer.log(
        '[DatabaseService] Retrieved ${result.length} task history records for date range $startDate to $endDate',
      );
      return result;
    } catch (e, stackTrace) {
      developer.log(
        '[DatabaseService] Error getting task history by date range',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getTaskHistoryByTaskId(
    Database db,
    int taskId,
  ) async {
    try {
      final result = await db.query(
        _taskHistoryTableName,
        where: 'task_id = ?',
        whereArgs: [taskId],
        orderBy: 'end_time DESC',
      );
      developer.log(
        '[DatabaseService] Retrieved ${result.length} task history records for task ID $taskId',
      );
      return result;
    } catch (e, stackTrace) {
      developer.log(
        '[DatabaseService] Error getting task history by task ID',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getTaskStatistics(Database db) async {
    try {
      // Get total completed tasks
      final totalResult = await db.rawQuery(
        'SELECT COUNT(*) as total_tasks FROM $_taskHistoryTableName',
      );

      // Get total time spent
      final timeResult = await db.rawQuery(
        'SELECT SUM(duration_seconds) as total_seconds FROM $_taskHistoryTableName',
      );

      // Get average task duration
      final avgResult = await db.rawQuery(
        'SELECT AVG(duration_seconds) as avg_seconds FROM $_taskHistoryTableName',
      );

      // Get tasks completed today
      final today = DateTime.now().toIso8601String().split('T')[0];
      final todayResult = await db.rawQuery(
        'SELECT COUNT(*) as today_tasks FROM $_taskHistoryTableName WHERE completion_date = ?',
        [today],
      );

      return {
        'total_tasks': totalResult.first['total_tasks'] ?? 0,
        'total_seconds': timeResult.first['total_seconds'] ?? 0,
        'avg_seconds': avgResult.first['avg_seconds'] ?? 0,
        'today_tasks': todayResult.first['today_tasks'] ?? 0,
      };
    } catch (e, stackTrace) {
      developer.log(
        '[DatabaseService] Error getting task statistics',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> clearAllTaskHistory(Database db) async {
    try {
      final count = await db.delete(_taskHistoryTableName);
      developer.log('[DatabaseService] Cleared $count task history records');
    } catch (e, stackTrace) {
      developer.log(
        '[DatabaseService] Error clearing task history',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // Instance methods for DB operations will now take a Database object
  Future<int> insertGeofence(
    Database db,
    Map<String, dynamic> geofenceData,
  ) async {
    // ... (validation logic as before) ...
    developer.log(
      '[DatabaseService] Inserting geofence into $_geofencesTableName: $geofenceData using provided DB object',
    );
    return await db.insert(
      _geofencesTableName,
      geofenceData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllGeofences(Database db) async {
    developer.log(
      '[DatabaseService] Fetching all geofences using provided DB object',
    );
    return await db.query(_geofencesTableName);
  }

  Future<Map<String, dynamic>?> getGeofenceById(Database db, String id) async {
    developer.log(
      '[DatabaseService] Fetching geofence by ID: $id using provided DB object',
    );
    final List<Map<String, dynamic>> maps = await db.query(
      _geofencesTableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<void> deleteGeofence(Database db, String id) async {
    developer.log(
      '[DatabaseService] Deleting geofence with ID: $id from $_geofencesTableName',
    );
    await db.delete(_geofencesTableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAllGeofences(Database db) async {
    developer.log(
      '[DatabaseService] Clearing all geofences from $_geofencesTableName',
    );
    await db.delete(_geofencesTableName);
  }

  Future<void> closeMainDb() async {
    developer.log("[DatabaseService] Attempting to close main DB.");
    // Wait for any ongoing initialization to complete before trying to close
    if (_dbInitializingCompleter != null &&
        !_dbInitializingCompleter!.isCompleted) {
      developer.log(
        "[DatabaseService] Waiting for ongoing DB initialization before closing...",
      );
      try {
        await _dbInitializingCompleter!.future;
      } catch (_) {
        /* If init failed, _mainIsolateDatabase might be null or closed already */
      }
    }

    if (_mainIsolateDatabase != null && _mainIsolateDatabase!.isOpen) {
      await _mainIsolateDatabase!.close();
      developer.log(
        "[DatabaseService] Main isolate database connection explicitly closed.",
      );
    } else {
      developer.log(
        "[DatabaseService] closeMainDb called, but DB was already null or not open.",
      );
    }
    _mainIsolateDatabase = null; // Clear the static instance
    _dbInitializingCompleter =
        null; // Reset completer so next mainDb call starts fresh
  }
}