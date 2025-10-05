import 'package:flutter_test/flutter_test.dart';
import 'package:intelliboro/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late DatabaseService dbService;

  setUpAll(() {
    // Initialize FFI for testing
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Create in-memory database for testing
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE task_history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id INTEGER,
            task_name TEXT,
            task_priority INTEGER,
            start_time INTEGER,
            end_time INTEGER,
            duration_seconds INTEGER,
            completion_date TEXT,
            geofence_id TEXT
          )
        ''');
      },
    );

    dbService = DatabaseService();
  });

  tearDown(() async {
    await db.close();
  });

  group('TaskHistory Pagination Tests', () {
    Future<void> insertTestHistory(int count) async {
      final now = DateTime.now();
      for (int i = 0; i < count; i++) {
        final completionDate = now.subtract(Duration(days: i));
        await db.insert('task_history', {
          'task_id': 1,
          'task_name': 'Test Task $i',
          'task_priority': (i % 5) + 1,
          'start_time': completionDate.millisecondsSinceEpoch ~/ 1000,
          'end_time':
              completionDate
                  .add(const Duration(minutes: 30))
                  .millisecondsSinceEpoch ~/
              1000,
          'duration_seconds': 1800,
          'completion_date': completionDate.toIso8601String().split('T')[0],
        });
      }
    }

    test('should get paginated task history with default limit', () async {
      await insertTestHistory(30);

      final result = await dbService.getTaskHistoryPaginated(
        db,
        limit: 20,
        offset: 0,
      );

      expect(result.length, equals(20));
    });

    test('should get second page of task history', () async {
      await insertTestHistory(30);

      final firstPage = await dbService.getTaskHistoryPaginated(
        db,
        limit: 20,
        offset: 0,
      );
      final secondPage = await dbService.getTaskHistoryPaginated(
        db,
        limit: 20,
        offset: 20,
      );

      expect(firstPage.length, equals(20));
      expect(secondPage.length, equals(10)); // Only 10 remaining
    });

    test(
      'should return empty list when offset exceeds total records',
      () async {
        await insertTestHistory(10);

        final result = await dbService.getTaskHistoryPaginated(
          db,
          limit: 20,
          offset: 20,
        );

        expect(result, isEmpty);
      },
    );

    test('should get correct total count of task history', () async {
      await insertTestHistory(25);

      final count = await dbService.getTaskHistoryCount(db);

      expect(count, equals(25));
    });

    test('should paginate task history by task ID', () async {
      // Insert history for multiple tasks
      final now = DateTime.now();
      for (int i = 0; i < 15; i++) {
        await db.insert('task_history', {
          'task_id': 1,
          'task_name': 'Task 1 Entry $i',
          'task_priority': 3,
          'start_time': now.millisecondsSinceEpoch ~/ 1000,
          'end_time':
              now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/
              1000,
          'duration_seconds': 1800,
          'completion_date': now.toIso8601String().split('T')[0],
        });
      }

      for (int i = 0; i < 10; i++) {
        await db.insert('task_history', {
          'task_id': 2,
          'task_name': 'Task 2 Entry $i',
          'task_priority': 4,
          'start_time': now.millisecondsSinceEpoch ~/ 1000,
          'end_time':
              now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/
              1000,
          'duration_seconds': 1800,
          'completion_date': now.toIso8601String().split('T')[0],
        });
      }

      final firstPage = await dbService.getTaskHistoryByTaskIdPaginated(
        db,
        1,
        limit: 10,
        offset: 0,
      );
      final secondPage = await dbService.getTaskHistoryByTaskIdPaginated(
        db,
        1,
        limit: 10,
        offset: 10,
      );

      expect(firstPage.length, equals(10));
      expect(secondPage.length, equals(5));
    });

    test('should get correct count for specific task ID', () async {
      final now = DateTime.now();
      for (int i = 0; i < 12; i++) {
        await db.insert('task_history', {
          'task_id': 1,
          'task_name': 'Task 1',
          'task_priority': 3,
          'start_time': now.millisecondsSinceEpoch ~/ 1000,
          'end_time':
              now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/
              1000,
          'duration_seconds': 1800,
          'completion_date': now.toIso8601String().split('T')[0],
        });
      }

      for (int i = 0; i < 8; i++) {
        await db.insert('task_history', {
          'task_id': 2,
          'task_name': 'Task 2',
          'task_priority': 4,
          'start_time': now.millisecondsSinceEpoch ~/ 1000,
          'end_time':
              now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/
              1000,
          'duration_seconds': 1800,
          'completion_date': now.toIso8601String().split('T')[0],
        });
      }

      final count1 = await dbService.getTaskHistoryCountByTaskId(db, 1);
      final count2 = await dbService.getTaskHistoryCountByTaskId(db, 2);

      expect(count1, equals(12));
      expect(count2, equals(8));
    });

    test('should paginate task history by date range', () async {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 10));
      final endDate = now.subtract(const Duration(days: 5));

      // Insert 20 entries within range
      for (int i = 5; i <= 10; i++) {
        for (int j = 0; j < 4; j++) {
          final date = now.subtract(Duration(days: i));
          await db.insert('task_history', {
            'task_id': 1,
            'task_name': 'Test Task',
            'task_priority': 3,
            'start_time': date.millisecondsSinceEpoch ~/ 1000,
            'end_time':
                date.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/
                1000,
            'duration_seconds': 1800,
            'completion_date': date.toIso8601String().split('T')[0],
          });
        }
      }

      // Insert entries outside range
      for (int i = 0; i < 5; i++) {
        final date = now.subtract(Duration(days: i));
        await db.insert('task_history', {
          'task_id': 1,
          'task_name': 'Outside Range',
          'task_priority': 3,
          'start_time': date.millisecondsSinceEpoch ~/ 1000,
          'end_time':
              date.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/
              1000,
          'duration_seconds': 1800,
          'completion_date': date.toIso8601String().split('T')[0],
        });
      }

      final result = await dbService.getTaskHistoryByDateRangePaginated(
        db,
        startDate.toIso8601String().split('T')[0],
        endDate.toIso8601String().split('T')[0],
        limit: 15,
        offset: 0,
      );

      expect(result.length, lessThanOrEqualTo(15));
    });

    test('should handle pagination with custom page sizes', () async {
      await insertTestHistory(50);

      final page1 = await dbService.getTaskHistoryPaginated(
        db,
        limit: 5,
        offset: 0,
      );
      final page2 = await dbService.getTaskHistoryPaginated(
        db,
        limit: 5,
        offset: 5,
      );
      final page3 = await dbService.getTaskHistoryPaginated(
        db,
        limit: 5,
        offset: 10,
      );

      expect(page1.length, equals(5));
      expect(page2.length, equals(5));
      expect(page3.length, equals(5));
    });

    test('should maintain correct order in paginated results', () async {
      await insertTestHistory(30);

      final firstPage = await dbService.getTaskHistoryPaginated(
        db,
        limit: 10,
        offset: 0,
      );
      final secondPage = await dbService.getTaskHistoryPaginated(
        db,
        limit: 10,
        offset: 10,
      );

      // Results should be ordered by completion_date DESC, end_time DESC
      // First page should have more recent dates
      if (firstPage.isNotEmpty && secondPage.isNotEmpty) {
        final firstPageLastDate = firstPage.last['completion_date'] as String;
        final secondPageFirstDate =
            secondPage.first['completion_date'] as String;

        // First page's last item should be >= second page's first item (DESC order)
        expect(
          firstPageLastDate.compareTo(secondPageFirstDate),
          greaterThanOrEqualTo(0),
        );
      }
    });

    test('should handle empty database gracefully', () async {
      final result = await dbService.getTaskHistoryPaginated(
        db,
        limit: 20,
        offset: 0,
      );
      final count = await dbService.getTaskHistoryCount(db);

      expect(result, isEmpty);
      expect(count, equals(0));
    });

    test('should handle offset at exact boundary', () async {
      await insertTestHistory(20);

      final result = await dbService.getTaskHistoryPaginated(
        db,
        limit: 10,
        offset: 20,
      );

      expect(result, isEmpty);
    });

    test('should handle large offset values', () async {
      await insertTestHistory(10);

      final result = await dbService.getTaskHistoryPaginated(
        db,
        limit: 10,
        offset: 1000,
      );

      expect(result, isEmpty);
    });
  });
}
