import 'dart:async';

/// Tracks whether any alarm is currently ringing to let the app
/// avoid playing competing notification sounds at the same time.
class AudioFocusGuard {
  AudioFocusGuard._internal();
  static final AudioFocusGuard instance = AudioFocusGuard._internal();

  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  // Track active alarm IDs so we correctly handle multiple concurrent alarms
  final Set<int> _activeAlarmIds = <int>{};

  bool get isAlarmActive => _activeAlarmIds.isNotEmpty;
  Stream<bool> get changes => _controller.stream;

  void onAlarmStart(int alarmId) {
    final added = _activeAlarmIds.add(alarmId);
    if (added) {
      _controller.add(true);
    }
  }

  void onAlarmStop([int? alarmId]) {
    if (alarmId != null) {
      _activeAlarmIds.remove(alarmId);
    } else {
      _activeAlarmIds.clear();
    }
    _controller.add(_activeAlarmIds.isNotEmpty);
  }

  void dispose() {
    _controller.close();
  }
}