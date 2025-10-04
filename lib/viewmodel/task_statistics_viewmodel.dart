import 'package:flutter/material.dart';
import 'package:intelliboro/repository/task_history_repository.dart';
import 'package:intelliboro/model/task_history_model.dart';
import 'dart:developer' as developer;

class TaskStatisticsViewModel extends ChangeNotifier {
  final TaskHistoryRepository _taskRepository = TaskHistoryRepository();

  // State variables
  bool _isLoading = false;
  String? _errorMessage;

  // Pagination state
  static const int _pageSize = 20;
  int _currentPage = 0;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;
  List<TaskHistoryModel> _allLoadedHistory = [];

  // Statistics data
  List<TaskHistoryModel> _weeklyHistory = [];
  List<TaskHistoryModel> _monthlyHistory = [];
  Map<String, int> _taskCountByDay = {};
  Map<String, Duration> _totalTimeByDay = {};
  Map<String, int> _taskCountByPriority = {};

  // Summary statistics
  int _totalTasksCompleted = 0;
  Duration _totalTimeSpent = Duration.zero;
  Duration _averageTaskDuration = Duration.zero;
  int _currentWeekTasks = 0;
  int _currentMonthTasks = 0;

  // Getters
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreData => _hasMoreData;
  String? get errorMessage => _errorMessage;
  List<TaskHistoryModel> get allLoadedHistory => _allLoadedHistory;
  List<TaskHistoryModel> get weeklyHistory => _weeklyHistory;
  List<TaskHistoryModel> get monthlyHistory => _monthlyHistory;
  Map<String, int> get taskCountByDay => _taskCountByDay;
  Map<String, Duration> get totalTimeByDay => _totalTimeByDay;
  Map<String, int> get taskCountByPriority => _taskCountByPriority;
  int get totalTasksCompleted => _totalTasksCompleted;
  Duration get totalTimeSpent => _totalTimeSpent;
  Duration get averageTaskDuration => _averageTaskDuration;
  int get currentWeekTasks => _currentWeekTasks;
  int get currentMonthTasks => _currentMonthTasks;
  int get currentPage => _currentPage;
  int get pageSize => _pageSize;

  TaskStatisticsViewModel() {
    loadStatistics();
  }

  Future<void> loadStatistics() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      developer.log('[TaskStatisticsViewModel] Loading statistics...');

      // Get current date for calculations
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final startOfMonth = DateTime(now.year, now.month, 1);

      // Load initial page of task history with pagination
      final initialHistory = await _taskRepository.getTaskHistoryPaginated(
        limit: _pageSize,
        offset: 0,
      );

      // Store the loaded history
      _allLoadedHistory = initialHistory;
      _currentPage = 0;
      _hasMoreData = initialHistory.length >= _pageSize;

      developer.log(
        '[TaskStatisticsViewModel] Loaded ${initialHistory.length} initial history records',
      );

      // For statistics calculations, we need data from the past 30 days
      // Filter the loaded data for the date range we care about
      final filteredHistory =
          initialHistory
              .where(
                (h) =>
                    h.completionDate.isAfter(
                      startOfMonth.subtract(const Duration(days: 30)),
                    ) &&
                    h.completionDate.isBefore(now.add(const Duration(days: 1))),
              )
              .toList();

      developer.log(
        '[TaskStatisticsViewModel] Filtered to ${filteredHistory.length} records for statistics',
      );

      // Filter for weekly and monthly data
      _weeklyHistory =
          filteredHistory
              .where(
                (h) => h.completionDate.isAfter(
                  startOfWeek.subtract(const Duration(days: 1)),
                ),
              )
              .toList();

      _monthlyHistory =
          filteredHistory
              .where(
                (h) => h.completionDate.isAfter(
                  startOfMonth.subtract(const Duration(days: 1)),
                ),
              )
              .toList();

      // Calculate statistics
      _calculateDailyStatistics();
      _calculatePriorityStatistics();
      _calculateSummaryStatistics();

      developer.log(
        '[TaskStatisticsViewModel] Statistics calculated successfully',
      );

      _isLoading = false;
      notifyListeners();
    } catch (e, stackTrace) {
      developer.log(
        '[TaskStatisticsViewModel] Error loading statistics',
        error: e,
        stackTrace: stackTrace,
      );
      _errorMessage = 'Failed to load statistics: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  void _calculateDailyStatistics() {
    _taskCountByDay.clear();
    _totalTimeByDay.clear();

    // Initialize last 7 days
    for (int i = 6; i >= 0; i--) {
      final date = DateTime.now().subtract(Duration(days: i));
      final key = _getDateKey(date);
      _taskCountByDay[key] = 0;
      _totalTimeByDay[key] = Duration.zero;
    }

    // Populate with actual data
    for (final history in _weeklyHistory) {
      final key = _getDateKey(history.completionDate);
      _taskCountByDay[key] = (_taskCountByDay[key] ?? 0) + 1;
      _totalTimeByDay[key] =
          (_totalTimeByDay[key] ?? Duration.zero) + history.duration;
    }
  }

  void _calculatePriorityStatistics() {
    _taskCountByPriority.clear();

    for (final history in _monthlyHistory) {
      final priorityKey = 'P${history.taskPriority}';
      _taskCountByPriority[priorityKey] =
          (_taskCountByPriority[priorityKey] ?? 0) + 1;
    }
  }

  void _calculateSummaryStatistics() {
    // Total tasks completed (period)
    _totalTasksCompleted = _monthlyHistory.length;

    // Current week and month tasks
    _currentWeekTasks = _weeklyHistory.length;
    _currentMonthTasks = _monthlyHistory.length;

    // Total time spent
    _totalTimeSpent = _monthlyHistory.fold(
      Duration.zero,
      (total, history) => total + history.duration,
    );

    // Average task duration
    if (_monthlyHistory.isNotEmpty) {
      final totalMinutes = _totalTimeSpent.inMinutes;
      _averageTaskDuration = Duration(
        minutes: totalMinutes ~/ _monthlyHistory.length,
      );
    } else {
      _averageTaskDuration = Duration.zero;
    }
  }

  String _getDateKey(DateTime date) {
    final weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekDays[date.weekday - 1];
  }

  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  // Get productivity score (0-100)
  int getProductivityScore() {
    if (_currentWeekTasks == 0) return 0;

    // Simple scoring: based on tasks completed and average duration
    // More tasks with shorter average duration = higher score
    final tasksScore = (_currentWeekTasks * 10).clamp(0, 50);
    final efficiencyScore =
        _averageTaskDuration.inMinutes > 0
            ? ((60 / _averageTaskDuration.inMinutes) * 50).clamp(0, 50)
            : 0;

    return (tasksScore + efficiencyScore).toInt().clamp(0, 100);
  }

  // Get streak of consecutive days with completed tasks
  int getStreak() {
    int streak = 0;
    final now = DateTime.now();

    for (int i = 0; i < 30; i++) {
      final date = now.subtract(Duration(days: i));
      final hasTask = _monthlyHistory.any(
        (h) =>
            h.completionDate.year == date.year &&
            h.completionDate.month == date.month &&
            h.completionDate.day == date.day,
      );

      if (hasTask) {
        streak++;
      } else if (i > 0) {
        // Don't break streak for today if no tasks yet
        break;
      }
    }

    return streak;
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Load more task history (for pagination)
  Future<void> loadMoreHistory() async {
    if (_isLoadingMore || !_hasMoreData || _isLoading) {
      developer.log(
        '[TaskStatisticsViewModel] Skipping loadMoreHistory - isLoadingMore: $_isLoadingMore, hasMoreData: $_hasMoreData, isLoading: $_isLoading',
      );
      return;
    }

    _isLoadingMore = true;
    notifyListeners();

    try {
      developer.log(
        '[TaskStatisticsViewModel] Loading more history - page: ${_currentPage + 1}, pageSize: $_pageSize',
      );

      final offset = (_currentPage + 1) * _pageSize;
      final newHistory = await _taskRepository.getTaskHistoryPaginated(
        limit: _pageSize,
        offset: offset,
      );

      developer.log(
        '[TaskStatisticsViewModel] Loaded ${newHistory.length} more history records',
      );

      if (newHistory.isEmpty || newHistory.length < _pageSize) {
        _hasMoreData = false;
        developer.log('[TaskStatisticsViewModel] No more data to load');
      }

      if (newHistory.isNotEmpty) {
        _allLoadedHistory.addAll(newHistory);
        _currentPage++;
        developer.log(
          '[TaskStatisticsViewModel] Current page: $_currentPage, Total records: ${_allLoadedHistory.length}',
        );
      }

      _isLoadingMore = false;
      notifyListeners();
    } catch (e, stackTrace) {
      developer.log(
        '[TaskStatisticsViewModel] Error loading more history',
        error: e,
        stackTrace: stackTrace,
      );
      _errorMessage = 'Failed to load more history: ${e.toString()}';
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Reset pagination and reload from the beginning
  Future<void> resetPagination() async {
    developer.log('[TaskStatisticsViewModel] Resetting pagination');
    _currentPage = 0;
    _hasMoreData = true;
    _allLoadedHistory.clear();
    await loadStatistics();
  }

  /// Get total count of all task history records
  Future<int> getTotalHistoryCount() async {
    try {
      return await _taskRepository.getTaskHistoryCount();
    } catch (e, stackTrace) {
      developer.log(
        '[TaskStatisticsViewModel] Error getting total history count',
        error: e,
        stackTrace: stackTrace,
      );
      return 0;
    }
  }
}
