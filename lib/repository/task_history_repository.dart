import 'dart:developer' as developer;
import 'package:intelliboro/model/task_history_model.dart';
import 'package:intelliboro/services/database_service.dart';
import 'package:sqflite/sqflite.dart';

/// Repository for managing task history data
class TaskHistoryRepository {
  final DatabaseService _databaseService = DatabaseService();

  /// Get all task history entries for a specific task ID
  Future<List<TaskHistoryModel>> getTaskHistory(int taskId) async {
    try {
      final db = await _databaseService.mainDb;
      final historyData = await _databaseService.getTaskHistoryByTaskId(
        db,
        taskId,
      );

      return historyData.map((data) => TaskHistoryModel.fromMap(data)).toList();
    } catch (e, stackTrace) {
      developer.log(
        '[TaskHistoryRepository] Error getting task history for task $taskId',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get the total time spent on a specific task across all sessions
  Future<Duration> getTotalTimeSpent(int taskId) async {
    try {
      final historyEntries = await getTaskHistory(taskId);

      if (historyEntries.isEmpty) {
        return Duration.zero;
      }

      final totalSeconds = historyEntries.fold<int>(
        0,
        (sum, entry) => sum + entry.duration.inSeconds,
      );

      return Duration(seconds: totalSeconds);
    } catch (e, stackTrace) {
      developer.log(
        '[TaskHistoryRepository] Error calculating total time for task $taskId',
        error: e,
        stackTrace: stackTrace,
      );
      return Duration.zero;
    }
  }

  /// Get the last completion time for a task
  Future<DateTime?> getLastCompletionTime(int taskId) async {
    try {
      final historyEntries = await getTaskHistory(taskId);

      if (historyEntries.isEmpty) {
        return null;
      }

      // Sort by end time descending to get the most recent
      historyEntries.sort((a, b) => b.endTime.compareTo(a.endTime));

      return historyEntries.first.endTime;
    } catch (e, stackTrace) {
      developer.log(
        '[TaskHistoryRepository] Error getting last completion time for task $taskId',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Get completion count for a task
  Future<int> getCompletionCount(int taskId) async {
    try {
      final historyEntries = await getTaskHistory(taskId);
      return historyEntries.length;
    } catch (e, stackTrace) {
      developer.log(
        '[TaskHistoryRepository] Error getting completion count for task $taskId',
        error: e,
        stackTrace: stackTrace,
      );
      return 0;
    }
  }

  /// Get formatted total time string for display
  Future<String> getFormattedTotalTime(int taskId) async {
    try {
      final totalTime = await getTotalTimeSpent(taskId);

      if (totalTime == Duration.zero) {
        return 'No time tracked';
      }

      return _formatDuration(totalTime);
    } catch (e) {
      developer.log(
        '[TaskHistoryRepository] Error formatting total time for task $taskId: $e',
      );
      return 'Error loading time';
    }
  }

  /// Format duration to human readable string
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m';
    } else {
      final seconds = duration.inSeconds;
      return '${seconds}s';
    }
  }

  /// Get all task history entries (for analytics/history views)
  Future<List<TaskHistoryModel>> getAllTaskHistory() async {
    try {
      final db = await _databaseService.mainDb;
      final historyData = await _databaseService.getAllTaskHistory(db);

      return historyData.map((data) => TaskHistoryModel.fromMap(data)).toList();
    } catch (e, stackTrace) {
      developer.log(
        '[TaskHistoryRepository] Error getting all task history',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get paginated task history entries
  /// [limit] - Maximum number of records to return (default: 20)
  /// [offset] - Number of records to skip (default: 0)
  /// Returns a list of TaskHistoryModel with the specified pagination
  Future<List<TaskHistoryModel>> getTaskHistoryPaginated({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final db = await _databaseService.mainDb;
      final historyData = await _databaseService.getTaskHistoryPaginated(
        db,
        limit: limit,
        offset: offset,
      );

      developer.log(
        '[TaskHistoryRepository] Retrieved ${historyData.length} paginated task history records (limit: $limit, offset: $offset)',
      );

      return historyData.map((data) => TaskHistoryModel.fromMap(data)).toList();
    } catch (e, stackTrace) {
      developer.log(
        '[TaskHistoryRepository] Error getting paginated task history',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get total count of task history records
  Future<int> getTaskHistoryCount() async {
    try {
      final db = await _databaseService.mainDb;
      return await _databaseService.getTaskHistoryCount(db);
    } catch (e, stackTrace) {
      developer.log(
        '[TaskHistoryRepository] Error getting task history count',
        error: e,
        stackTrace: stackTrace,
      );
      return 0;
    }
  }

  /// Get paginated task history for a specific task
  Future<List<TaskHistoryModel>> getTaskHistoryByTaskIdPaginated(
    int taskId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final db = await _databaseService.mainDb;
      final historyData = await _databaseService
          .getTaskHistoryByTaskIdPaginated(
            db,
            taskId,
            limit: limit,
            offset: offset,
          );

      developer.log(
        '[TaskHistoryRepository] Retrieved ${historyData.length} paginated task history records for task $taskId (limit: $limit, offset: $offset)',
      );

      return historyData.map((data) => TaskHistoryModel.fromMap(data)).toList();
    } catch (e, stackTrace) {
      developer.log(
        '[TaskHistoryRepository] Error getting paginated task history by task ID',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get count of task history records for a specific task
  Future<int> getTaskHistoryCountByTaskId(int taskId) async {
    try {
      final db = await _databaseService.mainDb;
      return await _databaseService.getTaskHistoryCountByTaskId(db, taskId);
    } catch (e, stackTrace) {
      developer.log(
        '[TaskHistoryRepository] Error getting task history count by task ID',
        error: e,
        stackTrace: stackTrace,
      );
      return 0;
    }
  }

  /// Get paginated task history by date range
  Future<List<TaskHistoryModel>> getTaskHistoryByDateRangePaginated(
    String startDate,
    String endDate, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final db = await _databaseService.mainDb;
      final historyData = await _databaseService
          .getTaskHistoryByDateRangePaginated(
            db,
            startDate,
            endDate,
            limit: limit,
            offset: offset,
          );

      developer.log(
        '[TaskHistoryRepository] Retrieved ${historyData.length} paginated task history records for date range (limit: $limit, offset: $offset)',
      );

      return historyData.map((data) => TaskHistoryModel.fromMap(data)).toList();
    } catch (e, stackTrace) {
      developer.log(
        '[TaskHistoryRepository] Error getting paginated task history by date range',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Get task history aggregated by date
  Future<Map<DateTime, List<TaskHistoryModel>>> getTaskHistoryByDate() async {
    try {
      final allHistory = await getAllTaskHistory();
      final Map<DateTime, List<TaskHistoryModel>> groupedHistory = {};

      for (final entry in allHistory) {
        final dateKey = DateTime(
          entry.completionDate.year,
          entry.completionDate.month,
          entry.completionDate.day,
        );

        if (!groupedHistory.containsKey(dateKey)) {
          groupedHistory[dateKey] = [];
        }

        groupedHistory[dateKey]!.add(entry);
      }

      return groupedHistory;
    } catch (e, stackTrace) {
      developer.log(
        '[TaskHistoryRepository] Error grouping task history by date',
        error: e,
        stackTrace: stackTrace,
      );
      return {};
    }
  }

  Future<void> startSession({
    required int taskId,
    required DateTime startedAt,
  }) async {
    final db = await DatabaseService().mainDb;
    await db.insert('task_history', {
      'task_id': taskId,
      'start_time': (startedAt.millisecondsSinceEpoch ~/ 1000), // store seconds
      'end_time': null,
      'duration_seconds': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> endSession({
    required int taskId,
    required DateTime endedAt,
    required Duration duration,
  }) async {
    final db = await DatabaseService().mainDb;
    // Update the most recent open session for this task (end_time is NULL)
    await db.update(
      'task_history',
      {
        'end_time': (endedAt.millisecondsSinceEpoch ~/ 1000), // seconds
        'duration_seconds': duration.inSeconds,
      },
      where: 'task_id = ? AND end_time IS NULL',
      whereArgs: [taskId],
    );
  }
}
