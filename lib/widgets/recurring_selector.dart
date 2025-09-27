import 'package:flutter/material.dart';
import 'package:intelliboro/model/recurring_pattern.dart';

/// Widget for selecting recurring patterns for tasks
class RecurringSelector extends StatefulWidget {
  final RecurringPattern initialPattern;
  final ValueChanged<RecurringPattern> onPatternChanged;

  const RecurringSelector({
    super.key,
    required this.initialPattern,
    required this.onPatternChanged,
  });

  @override
  State<RecurringSelector> createState() => _RecurringSelectorState();
}

class _RecurringSelectorState extends State<RecurringSelector> {
  late RecurringPattern _currentPattern;
  late Set<int> _selectedWeekdays;

  @override
  void initState() {
    super.initState();
    _currentPattern = widget.initialPattern;
    _selectedWeekdays = Set.from(_currentPattern.weekdays);
  }

  void _updatePattern(RecurringPattern newPattern) {
    setState(() {
      _currentPattern = newPattern;
      _selectedWeekdays = Set.from(newPattern.weekdays);
    });
    widget.onPatternChanged(newPattern);
  }

  void _onTypeChanged(RecurringType? type) {
    if (type == null) return;

    RecurringPattern newPattern;
    switch (type) {
      case RecurringType.none:
        newPattern = RecurringPattern.none();
        break;
      case RecurringType.daily:
        newPattern = RecurringPattern.daily();
        break;
      case RecurringType.weekdays:
        newPattern = RecurringPattern.weekdays();
        break;
      case RecurringType.weekly:
        // Keep current weekdays or default to current day if none selected
        final weekdays = _selectedWeekdays.isEmpty 
          ? [DateTime.now().weekday]
          : _selectedWeekdays.toList();
        newPattern = RecurringPattern.weekly(weekdays: weekdays);
        break;
    }
    _updatePattern(newPattern);
  }

  void _onWeekdayToggled(int weekday) {
    final newWeekdays = Set<int>.from(_selectedWeekdays);
    
    if (newWeekdays.contains(weekday)) {
      newWeekdays.remove(weekday);
    } else {
      newWeekdays.add(weekday);
    }

    // Ensure at least one day is selected for weekly type
    if (newWeekdays.isEmpty && _currentPattern.type == RecurringType.weekly) {
      return;
    }

    setState(() {
      _selectedWeekdays = newWeekdays;
    });

    if (_currentPattern.type == RecurringType.weekly) {
      final newPattern = RecurringPattern.weekly(
        weekdays: newWeekdays.toList(),
        endDate: _currentPattern.endDate,
      );
      _updatePattern(newPattern);
    }
  }

  Widget _buildWeekdaySelector() {
    if (_currentPattern.type != RecurringType.weekly) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    const weekdays = [
      (1, 'Mon'),
      (2, 'Tue'), 
      (3, 'Wed'),
      (4, 'Thu'),
      (5, 'Fri'),
      (6, 'Sat'),
      (7, 'Sun'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Select Days',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: weekdays.map((weekday) {
            final (dayNumber, dayName) = weekday;
            final isSelected = _selectedWeekdays.contains(dayNumber);
            
            return FilterChip(
              label: Text(dayName),
              selected: isSelected,
              onSelected: (_) => _onWeekdayToggled(dayNumber),
              backgroundColor: theme.colorScheme.surface,
              selectedColor: theme.colorScheme.primaryContainer,
              checkmarkColor: theme.colorScheme.onPrimaryContainer,
              labelStyle: TextStyle(
                color: isSelected 
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPatternPreview() {
    if (_currentPattern.type == RecurringType.none) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.repeat,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentPattern.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.repeat_rounded,
                    color: theme.colorScheme.onSecondaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recurring Pattern',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Set how often this task repeats',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Recurring type selection
            Column(
              children: RecurringType.values.map((type) {
                return RadioListTile<RecurringType>(
                  value: type,
                  groupValue: _currentPattern.type,
                  onChanged: _onTypeChanged,
                  title: Text(
                    type.displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: _currentPattern.type == type 
                        ? FontWeight.w600 
                        : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(_getTypeDescription(type)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: theme.colorScheme.primary,
                );
              }).toList(),
            ),

            // Weekday selector for custom weekly pattern
            _buildWeekdaySelector(),

            // Pattern preview
            _buildPatternPreview(),
          ],
        ),
      ),
    );
  }

  String _getTypeDescription(RecurringType type) {
    switch (type) {
      case RecurringType.none:
        return 'Task occurs only once';
      case RecurringType.daily:
        return 'Task repeats every day';
      case RecurringType.weekdays:
        return 'Task repeats Monday through Friday';
      case RecurringType.weekly:
        return 'Task repeats on selected days each week';
    }
  }
}