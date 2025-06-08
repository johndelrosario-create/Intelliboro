import 'dart:developer' as developer;
import 'package:intelliboro/services/database_service.dart';
import 'package:intelliboro/models/notification_record.dart';
import 'package:sqflite/sqflite.dart';

class NotificationHistoryRepository {
  final DatabaseService _databaseService;
  Database? _dbInstance;

  NotificationHistoryRepository({Database? db})
      : _databaseService = DatabaseService(),
        _dbInstance = db;

  Future<Database> get _db async {
    if (_dbInstance != null && _dbInstance!.isOpen) {
      return _dbInstance!;
    }
    return await _databaseService.mainDb;
  }

  Future<void> insert(NotificationRecord record) async {
    try {
      final db = await _db;
      final map = record.toMap()..remove('id'); // DB handles autoincrement
      await _databaseService.insertNotificationHistory(db, map);
      developer.log('[NotificationHistoryRepository] Inserted notification record for geofence: ${record.geofenceId}');
    } catch (e, stackTrace) {
      developer.log(
        '[NotificationHistoryRepository] Error inserting record',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<List<NotificationRecord>> getAll() async {
    try {
      final db = await _db;
      final maps = await _databaseService.getAllNotificationHistory(db);
      final records = maps.map((map) => NotificationRecord.fromMap(map)).toList();
      developer.log('[NotificationHistoryRepository] Fetched ${records.length} notification records.');
      return records;
    } catch (e, stackTrace) {
      developer.log(
        '[NotificationHistoryRepository] Error fetching records',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  Future<void> clearAll() async {
    try {
      final db = await _db;
      await _databaseService.clearAllNotificationHistory(db);
      developer.log('[NotificationHistoryRepository] Cleared all notification records.');
    } catch (e, stackTrace) {
      developer.log(
        '[NotificationHistoryRepository] Error clearing records',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
} 