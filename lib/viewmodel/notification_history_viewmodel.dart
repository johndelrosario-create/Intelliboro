import 'package:flutter/foundation.dart';
import 'package:intelliboro/models/notification_record.dart';
import 'package:intelliboro/repository/notification_history_repository.dart';
import 'dart:developer' as developer;

class NotificationHistoryViewModel extends ChangeNotifier {
  final NotificationHistoryRepository _repository;
  List<NotificationRecord> _history = [];
  bool _isLoading = false;
  String? _errorMessage;

  NotificationHistoryViewModel({NotificationHistoryRepository? repository})
    : _repository = repository ?? NotificationHistoryRepository();

  List<NotificationRecord> get history => _history;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadHistory() async {
    _isLoading = true;
    _errorMessage = null;
    // notifyListeners(); // Optional: if you want UI to react to loading state immediately

    try {
      final List<NotificationRecord> loadedRecords = await _repository.getAll();
      _history = loadedRecords; // Assign to the class member
      developer.log(
        '[NotificationHistoryViewModel] loadHistory: Loaded ${_history.length} history records. First item ID if any: ${_history.isNotEmpty ? _history.first.id : 'N/A'}.',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[NotificationHistoryViewModel] Error loading history',
        error: e,
        stackTrace: stackTrace,
      );
      _errorMessage = "Failed to load history: ${e.toString()}";
      _history = []; // Ensure it's empty on error
    } finally {
      _isLoading = false;
      developer.log(
        '[NotificationHistoryViewModel] loadHistory finally: Calling notifyListeners. History count: ${_history.length}',
      );
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.clearAll();
      _history = []; // Clear local list
      developer.log('[NotificationHistoryViewModel] Cleared history.');
    } catch (e, stackTrace) {
      developer.log(
        '[NotificationHistoryViewModel] Error clearing history',
        error: e,
        stackTrace: stackTrace,
      );
      _errorMessage = "Failed to clear history: ${e.toString()}";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
