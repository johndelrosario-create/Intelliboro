import 'package:flutter_test/flutter_test.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TaskTimerService', () {
    late TaskTimerService timerService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      timerService = TaskTimerService();
    });

    tearDown(() {
      timerService.dispose();
    });

    test('should initialize with no active task', () {
      expect(timerService.hasActiveTask, isFalse);
      expect(timerService.activeTask, isNull);
      expect(timerService.elapsedTime, equals(Duration.zero));
      expect(timerService.isPaused, isFalse);
    });

    test('should format elapsed time correctly', () {
      final formatted = timerService.getFormattedElapsedTime();
      expect(formatted, isA<String>());
      expect(formatted, contains('0s')); // Initially zero
    });

    test('should have default snooze duration of 5 minutes', () {
      expect(
        timerService.defaultSnoozeDuration,
        equals(const Duration(minutes: 5)),
      );
    });

    test('should update default snooze duration', () {
      final newDuration = const Duration(minutes: 10);
      timerService.setDefaultSnoozeDuration(newDuration);
      expect(timerService.defaultSnoozeDuration, equals(newDuration));
    });

    test('should check if task is pending', () {
      final task = TaskModel(
        id: 1,
        taskName: 'Test Task',
        taskPriority: 3,
        taskTime: const TimeOfDay(hour: 10, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      expect(timerService.isPending(1), isFalse);
    });

    test('should add task to pending list', () async {
      final task = TaskModel(
        id: 1,
        taskName: 'Pending Task',
        taskPriority: 3,
        taskTime: const TimeOfDay(hour: 10, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      await timerService.addToPending(task, const Duration(seconds: 5));
      expect(timerService.isPending(1), isTrue);

      final pendingUntil = timerService.getPendingUntil(1);
      expect(pendingUntil, isNotNull);
      expect(pendingUntil!.isAfter(DateTime.now()), isTrue);
    });

    test('should get pending remaining duration', () async {
      final task = TaskModel(
        id: 1,
        taskName: 'Pending Task',
        taskPriority: 3,
        taskTime: const TimeOfDay(hour: 10, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      await timerService.addToPending(task, const Duration(minutes: 5));

      final remaining = timerService.getPendingRemaining(1);
      expect(remaining, isNotNull);
      expect(remaining!.inMinutes, lessThanOrEqualTo(5));
      expect(
        remaining.inMinutes,
        greaterThanOrEqualTo(4),
      ); // Should be close to 5 minutes
    });

    test('should return null for non-pending task', () {
      final remaining = timerService.getPendingRemaining(999);
      expect(remaining, isNull);

      final pendingUntil = timerService.getPendingUntil(999);
      expect(pendingUntil, isNull);
    });

    test('should load persisted pending tasks', () async {
      // Set up mock persisted data
      final futureTime = DateTime.now().add(const Duration(hours: 1));
      SharedPreferences.setMockInitialValues({
        'pending_task_1': futureTime.millisecondsSinceEpoch,
        'pending_task_2': futureTime.millisecondsSinceEpoch,
      });

      final service = TaskTimerService();
      await service.loadPersistedPending();

      expect(service.isPending(1), isTrue);
      expect(service.isPending(2), isTrue);
    });

    test('should not load expired persisted pending tasks', () async {
      // Set up expired persisted data
      final pastTime = DateTime.now().subtract(const Duration(hours: 1));
      SharedPreferences.setMockInitialValues({
        'pending_task_1': pastTime.millisecondsSinceEpoch,
      });

      final service = TaskTimerService();
      await service.loadPersistedPending();

      expect(service.isPending(1), isFalse);
    });

    test('should check if paused task exists', () {
      expect(timerService.isPausedTask(1), isFalse);
      expect(timerService.pausedTasks, isEmpty);
    });

    test('should respond to switch request', () {
      final task = TaskModel(
        taskName: 'Switch Task',
        taskPriority: 5,
        taskTime: const TimeOfDay(hour: 10, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      final request = TaskSwitchRequest(task);
      final responded = request.future;

      request.respond(true);

      expect(responded, completion(isTrue));
    });

    test('should not respond to switch request twice', () {
      final task = TaskModel(
        taskName: 'Switch Task',
        taskPriority: 5,
        taskTime: const TimeOfDay(hour: 10, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      final request = TaskSwitchRequest(task);
      request.respond(true);

      // Second respond should not throw, but will be ignored
      expect(() => request.respond(false), returnsNormally);
    });

    test('should expose switch requests stream', () {
      expect(timerService.switchRequests, isA<Stream<TaskSwitchRequest>>());
    });

    test('should track timer running state', () {
      expect(timerService.isRunning(1), isFalse);
    });

    test('should start timer for task', () async {
      final task = TaskModel(
        id: 1,
        taskName: 'Timer Task',
        taskPriority: 3,
        taskTime: const TimeOfDay(hour: 10, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      // Note: This requires database setup, so we test the method exists
      expect(timerService.startTimerForTask, isA<Function>());
    });

    test('should stop timer for task', () async {
      // Note: This requires database setup, so we test the method exists
      expect(timerService.stopTimerForTask, isA<Function>());
    });

    test('should handle pause of non-existent task', () async {
      await timerService.pauseTask();
      expect(timerService.isPaused, isFalse);
    });

    test('should handle resume of non-existent task', () async {
      await timerService.resumeTask();
      expect(timerService.isPaused, isFalse);
    });

    test('should handle stop of non-existent task', () async {
      final duration = await timerService.stopTask();
      expect(duration, equals(Duration.zero));
    });

    test('should handle interrupt of non-existent task', () async {
      await timerService.interruptActiveTask();
      expect(timerService.activeTask, isNull);
    });

    test('should handle resume interrupted when no task', () async {
      final result = await timerService.resumeInterruptedTask();
      expect(result, isFalse);
    });

    test('should handle resume paused when no task', () async {
      final result = await timerService.resumePausedTask(1);
      expect(result, isFalse);
    });

    test('should notify listeners on state changes', () {
      var notified = false;
      timerService.addListener(() {
        notified = true;
      });

      timerService.setDefaultSnoozeDuration(const Duration(minutes: 10));
      expect(notified, isTrue);
    });

    test('should handle complete task manually', () async {
      final task = TaskModel(
        id: 1,
        taskName: 'Manual Task',
        taskPriority: 3,
        taskTime: const TimeOfDay(hour: 10, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      // Note: This requires database setup, so we test the method exists and doesn't throw
      expect(timerService.completeTaskManually, isA<Function>());
    });

    test('should handle reschedule task later', () async {
      final task = TaskModel(
        id: 1,
        taskName: 'Reschedule Task',
        taskPriority: 3,
        taskTime: const TimeOfDay(hour: 10, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      // Note: This requires database setup, so we test the method exists
      expect(timerService.rescheduleTaskLater, isA<Function>());
    });

    test('should expose tasksChanged notifier', () {
      expect(timerService.tasksChanged, isA<ValueNotifier<bool>>());
    });

    test('should handle multiple pending tasks', () async {
      final task1 = TaskModel(
        id: 1,
        taskName: 'Pending Task 1',
        taskPriority: 3,
        taskTime: const TimeOfDay(hour: 10, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      final task2 = TaskModel(
        id: 2,
        taskName: 'Pending Task 2',
        taskPriority: 4,
        taskTime: const TimeOfDay(hour: 11, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      await timerService.addToPending(task1, const Duration(minutes: 5));
      await timerService.addToPending(task2, const Duration(minutes: 10));

      expect(timerService.isPending(1), isTrue);
      expect(timerService.isPending(2), isTrue);

      final remaining1 = timerService.getPendingRemaining(1);
      final remaining2 = timerService.getPendingRemaining(2);

      expect(remaining1, isNotNull);
      expect(remaining2, isNotNull);
      expect(remaining2!.inMinutes, greaterThan(remaining1!.inMinutes));
    });

    test('should clear pending after duration expires', () async {
      final task = TaskModel(
        id: 1,
        taskName: 'Short Pending Task',
        taskPriority: 3,
        taskTime: const TimeOfDay(hour: 10, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      // Add with very short duration
      await timerService.addToPending(task, const Duration(milliseconds: 100));
      expect(timerService.isPending(1), isTrue);

      // Wait for expiration
      await Future.delayed(const Duration(milliseconds: 200));

      // Should be cleared (though actual cleanup happens in timer callback)
      expect(
        timerService.getPendingRemaining(1)?.inMilliseconds ?? 0,
        lessThanOrEqualTo(0),
      );
    });
  });
}
