import 'dart:developer' as developer;
import 'package:intelliboro/model/task_history_model.dart';
import 'package:intelliboro/services/database_service.dart';

/// Repository for managing task history data
class TaskHistoryRepository {
  final DatabaseService _databaseService = DatabaseService();

  /// Get all task history entries for a specific task ID
  Future<List<TaskHistoryModel>> getTaskHistory(int taskId) async {
    try {
      final db = await _databaseService.mainDb;
      final historyData = await _databaseService.getTaskHistoryByTaskId(db, taskId);
      
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
      developer.log('[TaskHistoryRepository] Error formatting total time for task $taskId: $e');
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
}