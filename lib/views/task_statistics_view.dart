import 'package:flutter/material.dart';
import 'package:intelliboro/viewModel/task_statistics_viewmodel.dart';

class TaskStatisticsView extends StatefulWidget {
  const TaskStatisticsView({Key? key}) : super(key: key);

  @override
  State<TaskStatisticsView> createState() => _TaskStatisticsViewState();
}

class _TaskStatisticsViewState extends State<TaskStatisticsView> {
  final TaskStatisticsViewModel _vm = TaskStatisticsViewModel();

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onVmChanged);
  }

  void _onVmChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    _vm.dispose();
    super.dispose();
  }

  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Completed (30d)', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 8),
                  Text(
                    '${_vm.totalTasksCompleted}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total time: ${_vm.formatDuration(_vm.totalTimeSpent)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This Week', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 8),
                  Text(
                    '${_vm.currentWeekTasks}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Streak: ${_vm.getStreak()}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyBars(BuildContext context) {
    final theme = Theme.of(context);
    final labels = _vm.taskCountByDay.keys.toList();
    final values = _vm.taskCountByDay.values.toList();
    final maxVal =
        (values.isEmpty)
            ? 1
            : values.reduce((a, b) => a > b ? a : b).clamp(1, 10);

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last 7 days', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(labels.length, (i) {
                final v = values[i];
                final height = (v / maxVal) * 48.0 + 8.0;
                return Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: height,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(labels[i], style: theme.textTheme.labelSmall),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityBreakdown(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _vm.taskCountByPriority.entries.toList();

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('By Priority', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Text('No data', style: theme.textTheme.bodySmall)
            else
              Column(
                children:
                    entries.map((e) {
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text(e.key.replaceAll('P', '')),
                        ),
                        title: Text('Priority ${e.key.replaceAll('P', '')}'),
                        trailing: Text('${e.value}'),
                      );
                    }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentList(BuildContext context) {
    final theme = Theme.of(context);
    final recent = _vm.monthlyHistory.take(10).toList();

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Completions', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (recent.isEmpty)
              Text('No completions yet', style: theme.textTheme.bodySmall)
            else
              Column(
                children:
                    recent.map((r) {
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.task_alt_rounded),
                        title: Text(r.taskName),
                        subtitle: Text(
                          '${r.completionDate.day}/${r.completionDate.month}/${r.completionDate.year} • ${_vm.formatDuration(r.duration)}',
                        ),
                      );
                    }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Task Statistics',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 4,
      ),
      backgroundColor: theme.colorScheme.surface,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child:
            _vm.isLoading
                ? Center(
                  child: CircularProgressIndicator(
                    color: theme.colorScheme.primary,
                  ),
                )
                : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummary(context),
                      const SizedBox(height: 12),
                      _buildDailyBars(context),
                      const SizedBox(height: 12),
                      _buildPriorityBreakdown(context),
                      const SizedBox(height: 12),
                      _buildRecentList(context),
                      const SizedBox(height: 24),
                      Center(
                        child: FilledButton.tonal(
                          onPressed: () => _vm.loadStatistics(),
                          child: const Text('Refresh'),
                        ),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}