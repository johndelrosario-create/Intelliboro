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
    notifyListeners();

    try {
      _history = await _repository.getAll();
      developer.log(
        '[NotificationHistoryViewModel] Loaded ${_history.length} history records.',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[NotificationHistoryViewModel] Error loading history',
        error: e,
        stackTrace: stackTrace,
      );
      _errorMessage = "Failed to load history: ${e.toString()}";
      _history = [];
    } finally {
      _isLoading = false;
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
