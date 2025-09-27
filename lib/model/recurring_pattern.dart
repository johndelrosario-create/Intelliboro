import 'dart:convert';

/// Represents the recurring pattern for a task
class RecurringPattern {
  final RecurringType type;
  final List<int> weekdays; // 1=Monday, 2=Tuesday, ..., 7=Sunday
  final DateTime? endDate; // Optional end date for the recurring pattern

  const RecurringPattern({
    required this.type,
    this.weekdays = const [],
    this.endDate,
  });

  /// Creates a non-recurring pattern
  factory RecurringPattern.none() {
    return const RecurringPattern(type: RecurringType.none);
  }

  /// Creates a daily recurring pattern
  factory RecurringPattern.daily({DateTime? endDate}) {
    return RecurringPattern(
      type: RecurringType.daily,
      weekdays: [1, 2, 3, 4, 5, 6, 7], // All days
      endDate: endDate,
    );
  }

  /// Creates a weekly pattern for specific days
  factory RecurringPattern.weekly({
    required List<int> weekdays,
    DateTime? endDate,
  }) {
    assert(weekdays.isNotEmpty, 'At least one weekday must be selected');
    assert(weekdays.every((day) => day >= 1 && day <= 7), 'Weekdays must be between 1-7');
    
    return RecurringPattern(
      type: RecurringType.weekly,
      weekdays: List.from(weekdays)..sort(),
      endDate: endDate,
    );
  }

  /// Creates a pattern for weekdays only (Monday-Friday)
  factory RecurringPattern.weekdays({DateTime? endDate}) {
    return RecurringPattern(
      type: RecurringType.weekdays,
      weekdays: [1, 2, 3, 4, 5], // Monday to Friday
      endDate: endDate,
    );
  }

  /// Convert to JSON string for database storage
  String toJson() {
    return jsonEncode({
      'type': type.name,
      'weekdays': weekdays,
      'endDate': endDate?.toIso8601String(),
    });
  }

  /// Create from JSON string
  factory RecurringPattern.fromJson(String json) {
    try {
      final Map<String, dynamic> data = jsonDecode(json);
      
      return RecurringPattern(
        type: RecurringType.values.firstWhere(
          (t) => t.name == data['type'],
          orElse: () => RecurringType.none,
        ),
        weekdays: List<int>.from(data['weekdays'] ?? []),
        endDate: data['endDate'] != null 
          ? DateTime.parse(data['endDate'])
          : null,
      );
    } catch (e) {
      // Return none pattern if JSON parsing fails
      return RecurringPattern.none();
    }
  }

  /// Get human-readable description of the pattern
  String get description {
    switch (type) {
      case RecurringType.none:
        return 'One-time task';
      case RecurringType.daily:
        return 'Daily';
      case RecurringType.weekdays:
        return 'Weekdays (Mon-Fri)';
      case RecurringType.weekly:
        if (weekdays.length == 7) {
          return 'Daily';
        } else if (weekdays.length == 1) {
          return 'Weekly on ${_getWeekdayName(weekdays.first)}';
        } else {
          final dayNames = weekdays.map(_getWeekdayName).join(', ');
          return 'Weekly on $dayNames';
        }
    }
  }

  /// Get short description for UI display
  String get shortDescription {
    switch (type) {
      case RecurringType.none:
        return 'Once';
      case RecurringType.daily:
        return 'Daily';
      case RecurringType.weekdays:
        return 'Weekdays';
      case RecurringType.weekly:
        if (weekdays.length == 7) {
          return 'Daily';
        } else if (weekdays.length == 1) {
          return _getWeekdayAbbreviation(weekdays.first);
        } else {
          final dayAbbreviations = weekdays.map(_getWeekdayAbbreviation);
          return dayAbbreviations.join(', ');
        }
    }
  }

  /// Check if the pattern is active (not ended)
  bool get isActive {
    if (endDate == null) return true;
    return DateTime.now().isBefore(endDate!);
  }

  /// Check if the task should occur on a specific date
  bool shouldOccurOn(DateTime date) {
    if (!isActive) return false;
    if (type == RecurringType.none) return false;
    
    // Get the weekday (1=Monday, 7=Sunday)
    final weekday = date.weekday;
    return weekdays.contains(weekday);
  }

  /// Get the next occurrence date after the given date
  DateTime? getNextOccurrence(DateTime after) {
    if (!isActive || type == RecurringType.none) return null;
    
    // Start checking from the day after the given date
    DateTime checkDate = DateTime(after.year, after.month, after.day + 1);
    
    // Look for the next occurrence within the next 14 days
    for (int i = 0; i < 14; i++) {
      if (shouldOccurOn(checkDate)) {
        // Check if it's before the end date (if set)
        if (endDate != null && checkDate.isAfter(endDate!)) {
          return null;
        }
        return checkDate;
      }
      checkDate = checkDate.add(const Duration(days: 1));
    }
    
    return null;
  }

  /// Get all occurrence dates within a date range
  List<DateTime> getOccurrencesInRange(DateTime start, DateTime end) {
    if (!isActive || type == RecurringType.none) return [];
    
    List<DateTime> occurrences = [];
    DateTime checkDate = DateTime(start.year, start.month, start.day);
    DateTime rangeEnd = DateTime(end.year, end.month, end.day);
    
    while (!checkDate.isAfter(rangeEnd)) {
      if (shouldOccurOn(checkDate)) {
        // Check if it's before the pattern end date (if set)
        if (endDate == null || !checkDate.isAfter(endDate!)) {
          occurrences.add(checkDate);
        }
      }
      checkDate = checkDate.add(const Duration(days: 1));
    }
    
    return occurrences;
  }

  String _getWeekdayName(int weekday) {
    switch (weekday) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return 'Unknown';
    }
  }

  String _getWeekdayAbbreviation(int weekday) {
    switch (weekday) {
      case 1: return 'Mon';
      case 2: return 'Tue';
      case 3: return 'Wed';
      case 4: return 'Thu';
      case 5: return 'Fri';
      case 6: return 'Sat';
      case 7: return 'Sun';
      default: return '?';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RecurringPattern) return false;
    
    return type == other.type &&
           weekdays.length == other.weekdays.length &&
           weekdays.every((day) => other.weekdays.contains(day)) &&
           endDate == other.endDate;
  }

  @override
  int get hashCode {
    return Object.hash(
      type,
      Object.hashAll(weekdays),
      endDate,
    );
  }

  @override
  String toString() {
    return 'RecurringPattern(type: $type, weekdays: $weekdays, endDate: $endDate, description: "$description")';
  }

  /// Create a copy with modified values
  RecurringPattern copyWith({
    RecurringType? type,
    List<int>? weekdays,
    DateTime? endDate,
  }) {
    return RecurringPattern(
      type: type ?? this.type,
      weekdays: weekdays ?? this.weekdays,
      endDate: endDate ?? this.endDate,
    );
  }
}

/// Types of recurring patterns
enum RecurringType {
  none,     // One-time task
  daily,    // Every day
  weekly,   // Specific days of the week
  weekdays, // Monday to Friday only
}

/// Extension to get user-friendly names for recurring types
extension RecurringTypeExtension on RecurringType {
  String get displayName {
    switch (this) {
      case RecurringType.none:
        return 'One-time';
      case RecurringType.daily:
        return 'Daily';
      case RecurringType.weekly:
        return 'Custom Days';
      case RecurringType.weekdays:
        return 'Weekdays';
    }
  }
}