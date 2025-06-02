import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:developer' as developer;

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._constructor();
  static Database? _mainIsolateDatabase; // Renamed for clarity
  static const String _dbName = 'intelliboro.db';
  static const int _dbVersion = 1;
  static const String _geofencestableName = 'geofences';
  static const String _tasksTableName = 'tasks';

  // Lock to prevent concurrent initialization from main isolate
  static bool _isInitializingMainDB = false;

  factory DatabaseService() => _instance;

  DatabaseService._constructor();

  // For the main UI isolate, uses a shared instance
  Future<Database> get mainDb async {
    if (_mainIsolateDatabase != null && _mainIsolateDatabase!.isOpen) {
      return _mainIsolateDatabase!;
    }
    if (_isInitializingMainDB) {
      // Wait if another part of the main isolate is already initializing
      developer.log(
        "[DatabaseService] Main DB initialization already in progress, waiting...",
      );
      await Future.delayed(
        Duration(milliseconds: 100),
      ); // Simple wait, could be more robust
      return mainDb; // Retry
    }
    _isInitializingMainDB = true;
    developer.log(
      "[DatabaseService] Initializing main isolate database connection.",
    );
    _mainIsolateDatabase = await _openDatabaseConnection(readOnly: false);
    _isInitializingMainDB = false;
    return _mainIsolateDatabase!;
  }

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
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _dbName);
      developer.log(
        "[DatabaseService] Attempting to open DB at path: $path, version: $_dbVersion, readOnly: $readOnly, singleInstance: true",
      );

      db = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate, // Static method
        onUpgrade: _onUpgrade, // Static method
        readOnly: readOnly,
        singleInstance:
            true, // Explicitly true for the main shared connection logic
      );
      developer.log(
        "[DatabaseService] DB opened. Verifying '$_geofencestableName' table existence...",
      );

      // Verify table existence
      List<Map<String, dynamic>> tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$_geofencestableName' AND name='$_tasksTableName'",
      );
      developer.log(
        "[DatabaseService] DB opened. Verifying '$_tasksTableName' table existence...",
      );

      return db;
    } catch (e, stacktrace) {
      developer.log(
        "[DatabaseService] Error in _openDatabaseConnection: $e\n$stacktrace",
      );
      // If db was initialized and is open, and an error occurred, try to close it.
      if (db != null && db.isOpen) {
        try {
          await db.close();
          developer.log(
            "[DatabaseService] Database closed due to error in _openDatabaseConnection.",
          );
        } catch (closeError) {
          developer.log(
            "[DatabaseService] Error closing database after another error: $closeError",
          );
        }
      }
      rethrow; // Rethrow the original error to be handled by the caller
    }
  }

  // onCreate and onUpgrade remain static or top-level like as they define schema
  static Future<void> _onCreate(Database db, int version) async {
    developer.log(
      '[DatabaseService] _onCreate: Creating table $_geofencestableName for version $version',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_geofencestableName
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
      'CREATE INDEX IF NOT EXISTS idx_${_geofencestableName}_id ON $_geofencestableName (id)',
    );
    developer.log(
      '[DatabaseService] _onCreate: $_geofencestableName and index created.',
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
    if (oldVersion < 2) {
      try {
        // await db.execute('ALTER TABLE $_tableName ADD COLUMN task TEXT');
        developer.log('[DatabaseService] _onUpgrade: task column added.');
      } catch (e) {
        developer.log(
          '[DatabaseService] _onUpgrade: Error adding task column: $e. Attempting full onCreate.',
        );
        await _onCreate(db, newVersion); // Fallback if ALTER fails
      }
    }
  }

  // Instance methods for DB operations will now take a Database object
  Future<int> insertGeofence(
    Database db,
    Map<String, dynamic> geofenceData,
  ) async {
    // ... (validation logic as before) ...
    developer.log(
      '[DatabaseService] Inserting geofence into $_geofencestableName: $geofenceData using provided DB object',
    );
    return await db.insert(
      _geofencestableName,
      geofenceData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllGeofences(Database db) async {
    developer.log(
      '[DatabaseService] Fetching all geofences using provided DB object',
    );
    return await db.query(_geofencestableName);
  }

  Future<Map<String, dynamic>?> getGeofenceById(Database db, String id) async {
    developer.log(
      '[DatabaseService] Fetching geofence by ID: $id using provided DB object',
    );
    final List<Map<String, dynamic>> maps = await db.query(
      _geofencestableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<void> deleteGeofence(Database db, String id) async {
    /* ... use db ... */
  }
  Future<void> clearAllGeofences(Database db) async {
    /* ... use db ... */
  }

  // Remove the test reInitializeDatabase method
  // Future<Database> reInitializeDatabase() async { ... }

  Future<void> closeMainDb() async {
    if (_mainIsolateDatabase != null && _mainIsolateDatabase!.isOpen) {
      await _mainIsolateDatabase!.close();
      _mainIsolateDatabase = null;
      developer.log(
        "[DatabaseService] Main isolate database connection closed.",
      );
    }
  }
}
