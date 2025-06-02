import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'dart:developer' as developer;

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _mainIsolateDatabase; // Renamed for clarity
  static const String _dbName = 'intelliboro.db';
  static const int _dbVersion = 2;
  static const String _tableName = 'geofences';

  // Lock to prevent concurrent initialization from main isolate
  static bool _isInitializingMainDB = false;

  factory DatabaseService() => _instance;

  DatabaseService._internal() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // This should ideally be called once per application start,
      // not necessarily in every isolate for ffi, but calling it here is generally safe.
      ffi.sqfliteFfiInit();
      developer.log("[DatabaseService] sqfliteFfiInit() called.");
    }
  }

  // For the main UI isolate, uses a shared instance
  Future<Database> get mainDb async {
    if (_mainIsolateDatabase != null && _mainIsolateDatabase!.isOpen)
      return _mainIsolateDatabase!;
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
    // Ensure FFI is initialized for this isolate if on desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
    }
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
        "[DatabaseService] DB opened. Verifying '$_tableName' table existence...",
      );

      // Verify table existence
      List<Map<String, dynamic>> tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$_tableName'",
      );

      // Only attempt to fix schema (delete/recreate) if this is a writable connection
      // and the primary geofences table is missing.
      if (!readOnly && tables.isEmpty) {
        developer.log(
          "[DatabaseService] (Writable) '$_tableName' table NOT found. Forcing DB deletion and re-creation.",
        );
        await db.close(); // Close the problematic DB instance
        await deleteDatabase(path); // Delete the physical DB file
        developer.log(
          "[DatabaseService] Database at $path deleted. Retrying openDatabase. This MUST trigger onCreate.",
        );

        // Retry opening. This MUST call onCreate.
        db = await openDatabase(
          path,
          version: _dbVersion,
          onCreate: _onCreate,
          // onUpgrade should not be called if onCreate is, as the DB is new.
          // If onUpgrade were to be called, it would be for future versions.
          readOnly: false, // Explicitly false for the recreate attempt
          singleInstance:
              true, // Explicitly true for the recreate attempt as well
        );
        developer.log(
          "[DatabaseService] DB re-opened after deletion (writable).",
        );

        // Re-verify (important for sanity and to catch deeper issues)
        tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='$_tableName'",
        );
        if (tables.isEmpty) {
          developer.log(
            "[DatabaseService] CRITICAL FAILURE: (Writable) '$_tableName' table STILL NOT found after delete and re-open.",
          );
          throw Exception(
            "Failed to create '$_tableName' table even after forced re-initialization for a writable database.",
          );
        } else {
          developer.log(
            "[DatabaseService] (Writable) '$_tableName' table confirmed after forced re-open.",
          );
        }
      } else if (tables.isEmpty && readOnly) {
        developer.log(
          "[DatabaseService] (ReadOnly) '$_tableName' table NOT found. Cannot fix in read-only mode. Operations might fail.",
        );
        // For a read-only connection, if the table is missing, we can't fix it here.
        // The caller will likely encounter errors. This is problematic and suggests
        // the DB wasn't correctly initialized by a prior writable connection.
      } else {
        developer.log(
          "[DatabaseService] '$_tableName' table found. Proceeding.",
        );
      }
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

  // _verifyTable is less relevant if each connection is fresh or onCreate/onUpgrade handles it.
  // Future<void> _verifyTable(Database db) async { ... }

  // onCreate and onUpgrade remain static or top-level like as they define schema
  static Future<void> _onCreate(Database db, int version) async {
    developer.log(
      '[DatabaseService] _onCreate: Creating table $_tableName for version $version',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableName (
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
      'CREATE INDEX IF NOT EXISTS idx_${_tableName}_id ON $_tableName (id)',
    );
    developer.log('[DatabaseService] _onCreate: Table and index created.');
  }

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
        await db.execute('ALTER TABLE $_tableName ADD COLUMN task TEXT');
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
      '[DatabaseService] Inserting geofence into $_tableName: $geofenceData using provided DB object',
    );
    return await db.insert(
      _tableName,
      geofenceData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllGeofences(Database db) async {
    developer.log(
      '[DatabaseService] Fetching all geofences using provided DB object',
    );
    return await db.query(_tableName);
  }

  Future<Map<String, dynamic>?> getGeofenceById(Database db, String id) async {
    developer.log(
      '[DatabaseService] Fetching geofence by ID: $id using provided DB object',
    );
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
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
