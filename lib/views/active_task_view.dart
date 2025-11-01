import 'package:flutter/material.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/views/task_list_view.dart';
import 'dart:developer' as developer;

class ActiveTaskView extends StatefulWidget {
  const ActiveTaskView({Key? key}) : super(key: key);

  @override
  State<ActiveTaskView> createState() => _ActiveTaskViewState();
}

class _ActiveTaskViewState extends State<ActiveTaskView> {
  final TaskTimerService _timerService = TaskTimerService();

  @override
  void initState() {
    super.initState();
    _timerService.addListener(_onTimerChanged);
  }

  void _onTimerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timerService.removeListener(_onTimerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TaskModel? task = _timerService.activeTask;
    final bool hasActive = task != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Task'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child:
              hasActive
                  ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        task.taskName,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Priority: ${task.priorityString}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Started: ${_timerService.startTime != null ? _timerService.startTime!.toLocal().toString() : '-'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _timerService.getFormattedElapsedTime(),
                        style: Theme.of(
                          context,
                        ).textTheme.displaySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Pause / Resume
                          ElevatedButton.icon(
                            icon: Icon(
                              _timerService.isPaused
                                  ? Icons.play_arrow
                                  : Icons.pause,
                              color: Colors.white,
                            ),
                            label: Text(
                              _timerService.isPaused ? 'Resume' : 'Pause',
                              style: const TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              try {
                                if (_timerService.isPaused) {
                                  await _timerService.resumeTask();
                                } else {
                                  await _timerService.pauseTask();
                                }
                              } catch (e) {
                                developer.log(
                                  '[ActiveTaskView] Error toggling pause/resume: $e',
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () async {
                              try {
                                await _timerService.stopTask();
                                if (!mounted) return;
                                // Replace the stack with TaskListView to avoid pop-related navigator issues
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (_) => const TaskListView(),
                                  ),
                                  (r) => false,
                                );
                              } catch (e, st) {
                                developer.log(
                                  '[ActiveTaskView] Error stopping task: $e',
                                  error: e,
                                  stackTrace: st,
                                );
                                // Try a safe fallback navigation
                                if (mounted)
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => const TaskListView(),
                                    ),
                                  );
                              }
                            },
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.list),
                            label: const Text('Tasks'),
                            onPressed:
                                () => Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => const TaskListView(),
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ],
                  )
                  : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_off, size: 64),
                      const SizedBox(height: 12),
                      const Text('No active task'),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('Back'),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}