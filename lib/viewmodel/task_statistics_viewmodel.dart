// import 'package:flutter/material.dart';
// import 'package:intelliboro/repository/task_repository.dart';
// import 'package:intelliboro/model/task_history_model.dart';
// import 'dart:developer' as developer;

// class TaskStatisticsViewModel extends ChangeNotifier {
//   final TaskRepository _taskRepository = TaskRepository();
  
//   // State variables
//   bool _isLoading = false;
//   String? _errorMessage;
  
//   // Statistics data
//   List<TaskHistoryModel> _weeklyHistory = [];
//   List<TaskHistoryModel> _monthlyHistory = [];
//   Map<String, int> _taskCountByDay = {};
//   Map<String, Duration> _totalTimeByDay = {};
//   Map<String, int> _taskCountByPriority = {};
  
//   // Summary statistics
//   int _totalTasksCompleted = 0;
//   Duration _totalTimeSpent = Duration.zero;
//   Duration _averageTaskDuration = Duration.zero;
//   int _currentWeekTasks = 0;
//   int _currentMonthTasks = 0;
  
//   // Getters
//   bool get isLoading => _isLoading;
//   String? get errorMessage => _errorMessage;
//   List<TaskHistoryModel> get weeklyHistory => _weeklyHistory;
//   List<TaskHistoryModel> get monthlyHistory => _monthlyHistory;
//   Map<String, int> get taskCountByDay => _taskCountByDay;
//   Map<String, Duration> get totalTimeByDay => _totalTimeByDay;
//   Map<String, int> get taskCountByPriority => _taskCountByPriority;
//   int get totalTasksCompleted => _totalTasksCompleted;
//   Duration get totalTimeSpent => _totalTimeSpent;
//   Duration get averageTaskDuration => _averageTaskDuration;
//   int get currentWeekTasks => _currentWeekTasks;
//   int get currentMonthTasks => _currentMonthTasks;

//   TaskStatisticsViewModel() {
//     loadStatistics();
//   }

//   Future<void> loadStatistics() async {
//     _isLoading = true;
//     _errorMessage = null;
//     notifyListeners();

//     try {
//       developer.log('[TaskStatisticsViewModel] Loading statistics...');
      
//       // Get current date for calculations
//       final now = DateTime.now();
//       final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
//       final startOfMonth = DateTime(now.year, now.month, 1);
      
//       // Load task history for the past 30 days
//        final allHistory = await _taskRepository.getTaskHistoryForDateRange(
//          startOfMonth.subtract(const Duration(days: 30)),
//          now,
//       / );
      
//       developer.log('[TaskStatisticsViewModel] Loaded ${allHistory.length} history records');
      
//       // Filter for weekly and monthly data
//       _weeklyHistory = allHistory.where((h) => 
//         h.completionDate.isAfter(startOfWeek.subtract(const Duration(days: 1)))
//       ).toList();
      
//       _monthlyHistory = allHistory.where((h) => 
//         h.completionDate.isAfter(startOfMonth.subtract(const Duration(days: 1)))
//       ).toList();
      
//       // Calculate statistics
//       _calculateDailyStatistics();
//       _calculatePriorityStatistics();
//       _calculateSummaryStatistics();
      
//       developer.log('[TaskStatisticsViewModel] Statistics calculated successfully');
      
//       _isLoading = false;
//       notifyListeners();
//     } catch (e, stackTrace) {
//       developer.log(
//         '[TaskStatisticsViewModel] Error loading statistics',
//         error: e,
//         stackTrace: stackTrace,
//       );
//       _errorMessage = 'Failed to load statistics: ${e.toString()}';
//       _isLoading = false;
//       notifyListeners();
//     }
//   }

//   void _calculateDailyStatistics() {
//     _taskCountByDay.clear();
//     _totalTimeByDay.clear();
    
//     // Initialize last 7 days
//     for (int i = 6; i >= 0; i--) {
//       final date = DateTime.now().subtract(Duration(days: i));
//       final key = _getDateKey(date);
//       _taskCountByDay[key] = 0;
//       _totalTimeByDay[key] = Duration.zero;
//     }
    
//     // Populate with actual data
//     for (final history in _weeklyHistory) {
//       final key = _getDateKey(history.completionDate);
//       _taskCountByDay[key] = (_taskCountByDay[key] ?? 0) + 1;
//       _totalTimeByDay[key] = (_totalTimeByDay[key] ?? Duration.zero) + history.duration;
//     }
//   }

//   void _calculatePriorityStatistics() {
//     _taskCountByPriority.clear();
    
//     for (final history in _monthlyHistory) {
//       final priorityKey = 'P${history.taskPriority}';
//       _taskCountByPriority[priorityKey] = (_taskCountByPriority[priorityKey] ?? 0) + 1;
//     }
//   }

//   void _calculateSummaryStatistics() {
//     // Total tasks completed (all time)
//     _totalTasksCompleted = _monthlyHistory.length;
    
//     // Current week and month tasks
//     _currentWeekTasks = _weeklyHistory.length;
//     _currentMonthTasks = _monthlyHistory.length;
    
//     // Total time spent
//     _totalTimeSpent = _monthlyHistory.fold(
//       Duration.zero,
//       (total, history) => total + history.duration,
//     );
    
//     // Average task duration
//     if (_monthlyHistory.isNotEmpty) {
//       final totalMinutes = _totalTimeSpent.inMinutes;
//       _averageTaskDuration = Duration(minutes: totalMinutes ~/ _monthlyHistory.length);
//     } else {
//       _averageTaskDuration = Duration.zero;
//     }
//   }

//   String _getDateKey(DateTime date) {
//     final weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
//     return weekDays[date.weekday - 1];
//   }

//   String formatDuration(Duration duration) {
//     final hours = duration.inHours;
//     final minutes = duration.inMinutes.remainder(60);
    
//     if (hours > 0) {
//       return '${hours}h ${minutes}m';
//     } else {
//       return '${minutes}m';
//     }
//   }

//   // Get productivity score (0-100)
//   int getProductivityScore() {
//     if (_currentWeekTasks == 0) return 0;
    
//     // Simple scoring: based on tasks completed and average duration
//     // More tasks with shorter average duration = higher score
//     final tasksScore = (_currentWeekTasks * 10).clamp(0, 50);
//     final efficiencyScore = _averageTaskDuration.inMinutes > 0
//         ? ((60 / _averageTaskDuration.inMinutes) * 50).clamp(0, 50)
//         : 0;
    
//     return (tasksScore + efficiencyScore).toInt().clamp(0, 100);
//   }

//   // Get streak of consecutive days with completed tasks
//   int getStreak() {
//     int streak = 0;
//     final now = DateTime.now();
    
//     for (int i = 0; i < 30; i++) {
//       final date = now.subtract(Duration(days: i));
//       final hasTask = _monthlyHistory.any((h) => 
//         h.completionDate.year == date.year &&
//         h.completionDate.month == date.month &&
//         h.completionDate.day == date.day
//       );
      
//       if (hasTask) {
//         streak++;
//       } else if (i > 0) {
//         // Don't break streak for today if no tasks yet
//         break;
//       }
//     }
    
//     return streak;
//   }

//   @override
//   void dispose() {
//     super.dispose();
//   }
// }