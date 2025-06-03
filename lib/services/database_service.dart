import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:developer' as developer;

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._constructor();
  static Database? _mainIsolateDatabase; // Renamed for clarity
  static const String _dbName = 'intelliboro.db';
  static const int _dbVersion = 1;
  static const String _geofencesTableName = 'geofences';
  static const String _tasksTableName = 'tasks';

  // Lock to prevent concurrent initialization from main isolate
  // static bool _isInitializingMainDB = false;
  static Completer<Database>? _dbInitializingCompleter;

  factory DatabaseService() => _instance;

  DatabaseService._constructor();

  // For the main UI isolate, uses a shared instance
  Future<Database> get mainDb async {
    if (_mainIsolateDatabase != null && _mainIsolateDatabase!.isOpen) {
      developer.log("[DatabaseService] Returning existing open DB instance.");
      return _mainIsolateDatabase!;
    }
    if (_dbInitializingCompleter != null) {
      developer.log(
        "[DatabaseService] DB initialization already in progress, awaiting active completer...",
      );
    }
    // No existing instance, and no initialization in progress; start it.
    developer.log("[DatabaseService] Starting new DB initialization process.");
    _dbInitializingCompleter =
        Completer<Database>(); // Create a new completer for this attempt

    try {
      final db = await _openDatabaseConnection(readOnly: false);
      // Check if the database is actually open after _openDatabaseConnection
      if (!db.isOpen) {
        developer.log(
          "[DatabaseService] CRITICAL: _openDatabaseConnection returned a closed DB during mainDb init.",
        );
        throw Exception("_openDatabaseConnection returned a closed DB");
      }
      _mainIsolateDatabase = db;
      developer.log(
        "[DatabaseService] DB initialization successful. Completing completer.",
      );
      if (!_dbInitializingCompleter!.isCompleted) {
        _dbInitializingCompleter!.complete(db);
      }
    } catch (e, stacktrace) {
      developer.log(
        "[DatabaseService] DB initialization failed: $e\n$stacktrace",
      );
      if (!_dbInitializingCompleter!.isCompleted) {
        _dbInitializingCompleter!.completeError(e, stacktrace);
      }
      _mainIsolateDatabase = null; // Ensure it's null on error
      // Important: Reset completer only after completing it with error,
      // so subsequent calls can attempt re-initialization.
      _dbInitializingCompleter = null;
      rethrow; // Rethrow to the original caller
    }
    return _mainIsolateDatabase!;
  }

  //Used in callback
  // For background isolates to get a fresh, independent connection
  Future<Database> openNewBackgroundConnection({bool readOnly = true}) async {
    developer.log(
      "[DatabaseService] Opening new background DB connection (readOnly: $readOnly).",
    );
    return await _openDatabaseConnection(readOnly: readOnly);
  }

  // Core method to open a database connection
  Future<Database> _openDatabaseConnection({required bool readOnly}) async {
    Database? db; // Declare db here to be accessible in catch
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    developer.log(
      "[DatabaseService] Attempting to open DB at path: $path, version: $_dbVersion, readOnly: $readOnly, singleInstance: true",
    );

    try {
      db = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate, // Static method
        onUpgrade: _onUpgrade, // Static method
        onDowngrade: onDatabaseDowngradeDelete,
        readOnly: readOnly,
        singleInstance:
            true, // Explicitly true for the main shared connection logic
      );
      developer.log(
        "[DatabaseService] DB object received. Path: $path. Verifying 'isOpne'...",
      );
      if (!db.isOpen) {
        developer.log(
          "[DatabaseService] (Simplified) CRITICAL: Database is not open after openDatabase call! Path: $path",
        );
        throw Exception(
          "Database not open after 'openDatabase' call. Path: $path",
        );
      }

      // Verify table existence
      List<Map<String, dynamic>> geofenceTableInfo = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$_geofencesTableName'",
      );
      developer.log(
        "[DatabaseService] DB opened. Verifying '$_geofencesTableName' table existence...",
      );
      List<Map<String, dynamic>> taskTableInfo = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$_tasksTableName'",
      );
      developer.log(
        "[DatabaseService] DB opened. Verifying '$_tasksTableName' table existence...",
      );

      if (taskTableInfo.isEmpty || geofenceTableInfo.isEmpty) {
        String missing = "";
        if (taskTableInfo.isEmpty) missing += "$_tasksTableName ";
        if (geofenceTableInfo.isEmpty) missing += _geofencesTableName;

        if (!readOnly) {
          developer.log(
            "[DatabaseService] CRITICAL (Writable): Essential table(s) '$missing' missing after _onCreate should have run. Path: $path",
          );
          await db.close(); // Close the problematic connection
          throw Exception(
            "Essential table(s) '$missing' missing in writable DB. Path: $path. This indicates _onCreate might have failed or an old DB file without these tables exists and wasn't upgraded.",
          );
        } else {
          developer.log(
            "[DatabaseService] WARNING (ReadOnly): Essential table(s) '$missing' missing. Operations likely to fail. Path: $path",
          );
        }
      } else {
        developer.log(
          "[DatabaseService] Both '$_tasksTableName' and '$_geofencesTableName' tables confirmed. Path: $path",
        );
      }
      return db;
    } catch (e, stacktrace) {
      developer.log(
        "[DatabaseService] Error in _openDatabaseConnection. Path: $path. Error: $e\n$stacktrace",
      );
      if (db != null && db.isOpen) {
        try {
          await db.close();
        } catch (closeError) {
          /* ignore */
        }
      }
      rethrow;
    }
  }

  // onCreate and onUpgrade remain static or top-level like as they define schema
  static Future<void> _onCreate(Database db, int version) async {
    developer.log(
      '[DatabaseService] _onCreate: Creating table $_geofencesTableName for version $version',
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
        taskTime TEXT NOT NULL,
        taskDate TEXT NOT NULL,
        isRecurring INTEGER NOT NULL,
        isCompleted INTEGER NOT NULL,
        created_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');
    developer.log('[DatabaseService] _onCreate: $_tasksTableName created.');
  }

  // Ununsed for now
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    developer.log(
      '[DatabaseService] _onUpgrade: Upgrading from $oldVersion to $newVersion',
    );
    // if (oldVersion < 2) {
    //   try {
    //     // await db.execute('ALTER TABLE $_tableName ADD COLUMN task TEXT');
    //     developer.log('[DatabaseService] _onUpgrade: task column added.');
    //   } catch (e) {
    //     developer.log(
    //       '[DatabaseService] _onUpgrade: Error adding task column: $e. Attempting full onCreate.',
    //     );
    //     await _onCreate(db, newVersion); // Fallback if ALTER fails
    //   }
    // }
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
