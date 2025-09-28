import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intelliboro/services/database_service.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/services/task_timer_service.dart';

/// Exports and imports tasks and task statistics (task_history) as JSON.
///
/// Export structure (schemaVersion 1):
/// {
///   "schemaVersion": 1,
///   "exportedAt": "2025-09-10T07:00:00Z",
///   "tasks": [ { row... } ],
///   "task_history": [ { row... } ]
/// }
class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  Future<Database> get _db async => DatabaseService().mainDb;

  /// Export tasks, task_history, and geofences as JSON string.
  /// Includes metadata for validation and troubleshooting.
  Future<String> exportToJsonString() async {
    final db = await _db;
    final tasks = await db.query('tasks');
    final history = await db.query('task_history');
    final geofences = await GeofenceStorage().loadGeofences();

    final exportTime = DateTime.now().toUtc();
    final payload = {
      'schemaVersion': 2, // Version 2 includes geofences
      'exportedAt': exportTime.toIso8601String(),
      'appVersion': '1.0.0', // Could be made dynamic from package_info_plus
      'exportMetadata': {
        'totalTasks': tasks.length,
        'totalHistory': history.length,
        'totalGeofences': geofences.length,
        'exportSource': 'IntelliboroApp',
      },
      'tasks': tasks,
      'task_history': history,
      'geofences': geofences.map((g) => g.toMap()).toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(payload);
    developer.log(
      '[BackupService] Generated backup: ${tasks.length} tasks, ${history.length} history, ${geofences.length} geofences',
    );

    return jsonString;
  }

  /// Get the backup directory, creating it if it doesn't exist.
  Future<Directory> _getOrCreateBackupDir() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(appDocDir.path, 'intelliboro_backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Export to a default path in the app's backup directory with a timestamped filename.
  /// Returns the file path written.
  Future<String> exportToDefaultPath() async {
    final backupDir = await _getOrCreateBackupDir();
    final ts = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final filePath = p.join(backupDir.path, 'backup_$ts.json');
    final json = await exportToJsonString();
    final f = File(filePath);
    await f.writeAsString(json);
    developer.log('[BackupService] Exported backup to $filePath');
    return filePath;
  }

  /// Schedule a daily backup at the specified time.
  /// Returns the scheduled backup time.
  Future<DateTime> scheduleDailyBackup(DateTime time) async {
    // TODO: Implement background task scheduling
    // This is a placeholder - actual implementation would use WorkManager or similar
    // to schedule a background task that calls exportToDefaultPath()
    developer.log('[BackupService] Scheduled daily backup at $time');
    return time;
  }

  /// Export backup using the system file picker to let user choose where to save.
  /// Returns the path where the backup was saved, or null if cancelled.
  Future<String?> exportWithFilePicker() async {
    try {
      final backupData = await exportToJsonString();

      // Generate a default filename with timestamp
      final timestamp = DateTime.now().toLocal();
      final formattedDate =
          timestamp.toIso8601String().split('T')[0]; // YYYY-MM-DD
      final formattedTime = timestamp
          .toIso8601String()
          .split('T')[1]
          .split('.')[0]
          .replaceAll(':', '-'); // HH-MM-SS
      final defaultFileName =
          'intelliboro_backup_${formattedDate}_$formattedTime.json';

      // Convert string to bytes for platform compatibility
      final bytes = utf8.encode(backupData);

      // Use file picker to let user choose save location
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Intelliboro Backup',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes, // Required for Android and iOS
      );

      if (outputFile != null) {
        developer.log('[BackupService] Exported backup to: $outputFile');
        return outputFile;
      } else {
        developer.log('[BackupService] Export cancelled by user');
        return null;
      }
    } catch (e) {
      developer.log('[BackupService] Error exporting backup: $e');
      rethrow;
    }
  }

  /// Validate a backup file without importing it.
  /// Returns a map with validation results and metadata.
  Future<Map<String, dynamic>> validateBackupFile(String filePath) async {
    try {
      final f = File(filePath);
      if (!await f.exists()) {
        return {'isValid': false, 'error': 'File not found: $filePath'};
      }

      final contents = await f.readAsString();
      return validateBackupString(contents);
    } catch (e) {
      return {'isValid': false, 'error': 'Failed to read file: $e'};
    }
  }

  /// Validate a backup JSON string without importing it.
  /// Returns a map with validation results and metadata.
  Future<Map<String, dynamic>> validateBackupString(String jsonString) async {
    try {
      final Map<String, dynamic> data =
          json.decode(jsonString) as Map<String, dynamic>;

      // Check required fields
      if (!data.containsKey('schemaVersion')) {
        return {
          'isValid': false,
          'error': 'Missing required field: schemaVersion',
        };
      }

      final int schemaVersion = data['schemaVersion'] as int? ?? 1;
      if (schemaVersion < 1 || schemaVersion > 2) {
        return {
          'isValid': false,
          'error': 'Unsupported schemaVersion: $schemaVersion',
        };
      }

      final List<dynamic> tasks = (data['tasks'] as List<dynamic>? ?? []);
      final List<dynamic> history =
          (data['task_history'] as List<dynamic>? ?? []);
      final List<dynamic>? geofences =
          (schemaVersion >= 2) ? (data['geofences'] as List<dynamic>?) : null;

      final String? exportedAt = data['exportedAt'] as String?;
      final Map<String, dynamic>? metadata =
          data['exportMetadata'] as Map<String, dynamic>?;

      return {
        'isValid': true,
        'schemaVersion': schemaVersion,
        'tasksCount': tasks.length,
        'historyCount': history.length,
        'geofencesCount': geofences?.length ?? 0,
        'exportedAt': exportedAt,
        'metadata': metadata,
      };
    } catch (e) {
      return {'isValid': false, 'error': 'Invalid JSON format: $e'};
    }
  }

  /// Returns true if import was successful, false if cancelled.
  Future<bool> importWithFilePicker() async {
    try {
      // Use file picker with proper MIME type and extension filtering
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
        dialogTitle: 'Select Intelliboro Backup File',
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        String? filePath = file.path;

        developer.log('[BackupService] Starting import process...');

        // Handle both file path and bytes for better compatibility
        if (filePath != null) {
          // Direct file path available (most common case)
          await importFromFile(filePath);
        } else if (file.bytes != null) {
          // Handle case where only bytes are available (some Android scenarios)
          final jsonString = String.fromCharCodes(file.bytes!);
          await importFromJsonString(jsonString);
        } else {
          throw Exception('Unable to access selected file');
        }

        developer.log(
          '[BackupService] Successfully imported backup from: ${file.name}',
        );
        return true;
      }

      developer.log('[BackupService] Import cancelled by user');
      return false;
    } catch (e) {
      developer.log('[BackupService] Error importing with file picker: $e');
      rethrow;
    }
  }

  /// Import from a JSON file path and replace existing data.
  /// This will clear 'tasks' and 'task_history' then insert rows from file.
  Future<void> importFromFile(String filePath) async {
    final f = File(filePath);
    if (!await f.exists()) {
      throw ArgumentError('File not found: $filePath');
    }
    final contents = await f.readAsString();
    await importFromJsonString(contents);
  }

  /// Import from a JSON string and replace existing data.
  /// Validates the backup format before importing.
  Future<void> importFromJsonString(String jsonString) async {
    final db = await _db;

    // Validate JSON format first
    late Map<String, dynamic> data;
    try {
      data = json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('Invalid JSON format: $e');
    }

    // Validate required fields
    if (!data.containsKey('schemaVersion')) {
      throw FormatException('Missing required field: schemaVersion');
    }

    final int schemaVersion = data['schemaVersion'] as int? ?? 1;
    if (schemaVersion < 1 || schemaVersion > 2) {
      throw UnsupportedError(
        'Unsupported backup schemaVersion: $schemaVersion. Supported versions: 1-2',
      );
    }

    // Validate data structure
    final List<dynamic> tasks = (data['tasks'] as List<dynamic>? ?? []);
    final List<dynamic> history =
        (data['task_history'] as List<dynamic>? ?? []);
    final List<dynamic>? geofences =
        (schemaVersion >= 2) ? (data['geofences'] as List<dynamic>?) : null;

    developer.log(
      '[BackupService] Starting import: schema v$schemaVersion, ${tasks.length} tasks, ${history.length} history entries',
    );

    // Perform import within transaction for atomicity
    await db.transaction((txn) async {
      // Clear existing data
      await txn.delete('task_history');
      await txn.delete('tasks');
      developer.log('[BackupService] Cleared existing data');

      // Insert tasks with validation
      int tasksInserted = 0;
      for (final row in tasks) {
        try {
          final map = Map<String, Object?>.from(row as Map);
          await txn.insert(
            'tasks',
            map,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          tasksInserted++;
        } catch (e) {
          developer.log('[BackupService] Warning: Failed to import task: $e');
          // Continue with other tasks instead of failing completely
        }
      }

      // Insert task_history with validation
      int historyInserted = 0;
      for (final row in history) {
        try {
          final map = Map<String, Object?>.from(row as Map);
          await txn.insert(
            'task_history',
            map,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          historyInserted++;
        } catch (e) {
          developer.log(
            '[BackupService] Warning: Failed to import history entry: $e',
          );
          // Continue with other entries instead of failing completely
        }
      }

      developer.log(
        '[BackupService] Database import complete: $tasksInserted tasks, $historyInserted history entries',
      );
    });

    // Handle geofences (if present in backup)
    int geofencesImported = 0;
    if (geofences != null) {
      try {
        final geofenceStorage = GeofenceStorage();
        await geofenceStorage.clearAll();

        for (final g in geofences) {
          try {
            await geofenceStorage.saveGeofence(g);
            geofencesImported++;
          } catch (e) {
            developer.log(
              '[BackupService] Warning: Failed to import geofence: $e',
            );
            // Continue with other geofences
          }
        }

        developer.log('[BackupService] Imported $geofencesImported geofences');
      } catch (e) {
        developer.log(
          '[BackupService] Warning: Failed to import geofences: $e',
        );
        // Don't fail the entire import if just geofences fail
      }
    }

    // CRITICAL: Notify all app components that data has changed
    await _notifyDataChanged();

    developer.log('[BackupService] Import completed successfully');
  }

  /// Notify all app components that data has changed after import
  Future<void> _notifyDataChanged() async {
    try {
      // Get the TaskTimerService singleton instance
      final taskTimerService = TaskTimerService();

      // Trigger the tasksChanged notifier to refresh all UI components
      taskTimerService.tasksChanged.value = true;
      developer.log(
        '[BackupService] Notified TaskTimerService of data changes',
      );
    } catch (e) {
      developer.log(
        '[BackupService] Warning: Failed to notify services of data changes: $e',
      );
      // Don't fail the import if notification fails
    }
  }
}