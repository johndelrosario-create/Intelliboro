import 'package:flutter_test/flutter_test.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late GeofenceStorage storage;

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
          CREATE TABLE geofences(
            id TEXT PRIMARY KEY,
            latitude REAL,
            longitude REAL,
            radius_meters REAL,
            task TEXT,
            fill_color TEXT,
            fill_opacity REAL,
            stroke_color TEXT,
            stroke_width REAL
          )
        ''');
      },
    );

    storage = GeofenceStorage(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('GeofenceStorage', () {
    test('should load empty geofences list initially', () async {
      final geofences = await storage.loadGeofences();
      expect(geofences, isEmpty);
    });

    test('should save and load a geofence', () async {
      final geofence = GeofenceData(
        id: 'test_geo_1',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 100.0,
        task: 'Test Task',
        fillColor: '0xFF0000FF',
        fillOpacity: 0.3,
        strokeColor: '0xFF000000',
        strokeWidth: 2.0,
      );

      await storage.saveGeofence(geofence);

      final geofences = await storage.loadGeofences();
      expect(geofences.length, equals(1));
      expect(geofences[0].id, equals('test_geo_1'));
      expect(geofences[0].latitude, equals(40.7128));
      expect(geofences[0].longitude, equals(-74.0060));
      expect(geofences[0].radiusMeters, equals(100.0));
      expect(geofences[0].task, equals('Test Task'));
    });

    test('should save multiple geofences', () async {
      final geofence1 = GeofenceData(
        id: 'geo_1',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 100.0,
        task: 'Task 1',
        fillColor: '0xFF0000FF',
        fillOpacity: 0.3,
        strokeColor: '0xFF000000',
        strokeWidth: 2.0,
      );

      final geofence2 = GeofenceData(
        id: 'geo_2',
        latitude: 34.0522,
        longitude: -118.2437,
        radiusMeters: 200.0,
        task: 'Task 2',
        fillColor: '0xFFFF0000',
        fillOpacity: 0.5,
        strokeColor: '0xFF000000',
        strokeWidth: 3.0,
      );

      await storage.saveGeofence(geofence1);
      await storage.saveGeofence(geofence2);

      final geofences = await storage.loadGeofences();
      expect(geofences.length, equals(2));
    });

    test('should get geofence by ID', () async {
      final geofence = GeofenceData(
        id: 'test_geo_id',
        latitude: 37.7749,
        longitude: -122.4194,
        radiusMeters: 150.0,
        task: 'San Francisco Task',
        fillColor: '0xFF00FF00',
        fillOpacity: 0.4,
        strokeColor: '0xFF000000',
        strokeWidth: 2.5,
      );

      await storage.saveGeofence(geofence);

      final retrieved = await storage.getGeofenceById('test_geo_id');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals('test_geo_id'));
      expect(retrieved.latitude, equals(37.7749));
      expect(retrieved.task, equals('San Francisco Task'));
    });

    test('should return null for non-existent geofence ID', () async {
      final retrieved = await storage.getGeofenceById('non_existent_id');
      expect(retrieved, isNull);
    });

    test('should delete a geofence', () async {
      final geofence = GeofenceData(
        id: 'delete_me',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 100.0,
        task: 'Delete Test',
        fillColor: '0xFF0000FF',
        fillOpacity: 0.3,
        strokeColor: '0xFF000000',
        strokeWidth: 2.0,
      );

      await storage.saveGeofence(geofence);

      var geofences = await storage.loadGeofences();
      expect(geofences.length, equals(1));

      await storage.deleteGeofence('delete_me');

      geofences = await storage.loadGeofences();
      expect(geofences, isEmpty);
    });

    test('should clear all geofences', () async {
      final geofence1 = GeofenceData(
        id: 'geo_1',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 100.0,
        task: 'Task 1',
        fillColor: '0xFF0000FF',
        fillOpacity: 0.3,
        strokeColor: '0xFF000000',
        strokeWidth: 2.0,
      );

      final geofence2 = GeofenceData(
        id: 'geo_2',
        latitude: 34.0522,
        longitude: -118.2437,
        radiusMeters: 200.0,
        task: 'Task 2',
        fillColor: '0xFFFF0000',
        fillOpacity: 0.5,
        strokeColor: '0xFF000000',
        strokeWidth: 3.0,
      );

      await storage.saveGeofence(geofence1);
      await storage.saveGeofence(geofence2);

      var geofences = await storage.loadGeofences();
      expect(geofences.length, equals(2));

      await storage.clearGeofences();

      geofences = await storage.loadGeofences();
      expect(geofences, isEmpty);
    });

    test('should clear all geofences using clearAll alias', () async {
      final geofence = GeofenceData(
        id: 'geo_1',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 100.0,
        task: 'Task 1',
        fillColor: '0xFF0000FF',
        fillOpacity: 0.3,
        strokeColor: '0xFF000000',
        strokeWidth: 2.0,
      );

      await storage.saveGeofence(geofence);

      var geofences = await storage.loadGeofences();
      expect(geofences.length, equals(1));

      await storage.clearAll(); // Test alias method

      geofences = await storage.loadGeofences();
      expect(geofences, isEmpty);
    });

    test('should handle inactive geofences', () async {
      final geofence = GeofenceData(
        id: 'inactive_geo',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 100.0,
        task: 'Inactive Task',
        fillColor: '0xFF0000FF',
        fillOpacity: 0.3,
        strokeColor: '0xFF000000',
        strokeWidth: 2.0,
      );

      await storage.saveGeofence(geofence);

      final retrieved = await storage.getGeofenceById('inactive_geo');
      expect(retrieved, isNotNull);
    });

    test('should preserve geofence styling properties', () async {
      final geofence = GeofenceData(
        id: 'styled_geo',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 100.0,
        task: 'Styled Task',
        fillColor: '0xFFFF5733',
        fillOpacity: 0.65,
        strokeColor: '0xFF123456',
        strokeWidth: 4.5,
      );

      await storage.saveGeofence(geofence);

      final retrieved = await storage.getGeofenceById('styled_geo');
      expect(retrieved, isNotNull);
      expect(retrieved!.fillColor, equals('0xFFFF5733'));
      expect(retrieved.fillOpacity, equals(0.65));
      expect(retrieved.strokeColor, equals('0xFF123456'));
      expect(retrieved.strokeWidth, equals(4.5));
    });

    test('should handle geofence without task', () async {
      final geofence = GeofenceData(
        id: 'no_task_geo',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 100.0,
        task: null,
        fillColor: '0xFF0000FF',
        fillOpacity: 0.3,
        strokeColor: '0xFF000000',
        strokeWidth: 2.0,
      );

      await storage.saveGeofence(geofence);

      final retrieved = await storage.getGeofenceById('no_task_geo');
      expect(retrieved, isNotNull);
      expect(retrieved!.task, isNull);
    });

    test('should handle various radius values', () async {
      final smallGeofence = GeofenceData(
        id: 'small_geo',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 50.0,
        task: 'Small Zone',
        fillColor: '0xFF0000FF',
        fillOpacity: 0.3,
        strokeColor: '0xFF000000',
        strokeWidth: 2.0,
      );

      final largeGeofence = GeofenceData(
        id: 'large_geo',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 5000.0,
        task: 'Large Zone',
        fillColor: '0xFF0000FF',
        fillOpacity: 0.3,
        strokeColor: '0xFF000000',
        strokeWidth: 2.0,
      );

      await storage.saveGeofence(smallGeofence);
      await storage.saveGeofence(largeGeofence);

      final small = await storage.getGeofenceById('small_geo');
      final large = await storage.getGeofenceById('large_geo');

      expect(small!.radiusMeters, equals(50.0));
      expect(large!.radiusMeters, equals(5000.0));
    });

    test('should handle negative coordinates', () async {
      final geofence = GeofenceData(
        id: 'southern_hemisphere',
        latitude: -33.8688,
        longitude: 151.2093,
        radiusMeters: 100.0,
        task: 'Sydney Task',
        fillColor: '0xFF0000FF',
        fillOpacity: 0.3,
        strokeColor: '0xFF000000',
        strokeWidth: 2.0,
      );

      await storage.saveGeofence(geofence);

      final retrieved = await storage.getGeofenceById('southern_hemisphere');
      expect(retrieved, isNotNull);
      expect(retrieved!.latitude, equals(-33.8688));
      expect(retrieved.longitude, equals(151.2093));
    });

    test('should handle update of existing geofence', () async {
      final geofence = GeofenceData(
        id: 'update_geo',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 100.0,
        task: 'Original Task',
        fillColor: '0xFF0000FF',
        fillOpacity: 0.3,
        strokeColor: '0xFF000000',
        strokeWidth: 2.0,
      );

      await storage.saveGeofence(geofence);

      final updatedGeofence = GeofenceData(
        id: 'update_geo',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 200.0, // Changed
        task: 'Updated Task', // Changed
        fillColor: '0xFFFF0000', // Changed
        fillOpacity: 0.5, // Changed
        strokeColor: '0xFFFFFFFF', // Changed
        strokeWidth: 3.0, // Changed
      );

      await storage.saveGeofence(updatedGeofence);

      final retrieved = await storage.getGeofenceById('update_geo');
      expect(retrieved, isNotNull);
      expect(retrieved!.radiusMeters, equals(200.0));
      expect(retrieved.task, equals('Updated Task'));
    });
  });
}
