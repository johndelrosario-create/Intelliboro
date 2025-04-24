import 'package:flutter/material.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:intelliboro/Geofencing/create_geofence.dart';
import 'dart:isolate';
import 'dart:ui';
import 'dart:async';

class GeoFence extends StatefulWidget {
  const GeoFence({super.key});

  @override
  GeoFenceState createState() => GeoFenceState();
}

class GeoFenceState extends State<GeoFence> {
  String geofenceState = 'N/A';
  ReceivePort port = ReceivePort();

  @override
  // init state is from stateless/stateful widget class
  void initState() {
    super.initState();
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      'native_geofence_send_port',
    );
    port.listen((dynamic data) {
      debugPrint('Event: data');
      // Set state is from create geofence
      setState(() {
        geofenceState = data;
      });
    });
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    debugPrint('Initializing...');
    await NativeGeofenceManager.instance.initialize();
    debugPrint('Initialization done');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Container(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Current State: $geofenceState'),
              const SizedBox(height: 20),
              CreateGeofence(),
            ],
          ),
        ),
      ),
    );
  }
}

final zone1 = Geofence(
  id: 'zone1',
  location: Location(latitude: 14.4381, longitude: 120.8972), // Times Square
  radiusMeters: 500,
  triggers: {GeofenceEvent.enter, GeofenceEvent.exit, GeofenceEvent.dwell},
  iosSettings: IosGeofenceSettings(initialTrigger: true),
  androidSettings: AndroidGeofenceSettings(
    initialTriggers: {GeofenceEvent.enter},
    expiration: const Duration(days: 7),
    loiteringDelay: const Duration(minutes: 5),
    notificationResponsiveness: const Duration(minutes: 5),
  ),
);

final zone2 = Geofence(
  id: 'zone2',
  location: Location(latitude: 14.4383, longitude: 120.8975), // Times Square
  radiusMeters: 500,
  triggers: {GeofenceEvent.enter, GeofenceEvent.exit, GeofenceEvent.dwell},
  iosSettings: IosGeofenceSettings(initialTrigger: true),
  androidSettings: AndroidGeofenceSettings(
    initialTriggers: {GeofenceEvent.enter},
    expiration: const Duration(days: 7),
    loiteringDelay: const Duration(minutes: 5),
    notificationResponsiveness: const Duration(minutes: 5),
  ),
);

final zone3 = Geofence(
  id: 'zone3',
  location: Location(latitude: 14.4376, longitude: 120.8965), // Times Square
  radiusMeters: 500,
  triggers: {GeofenceEvent.enter, GeofenceEvent.exit, GeofenceEvent.dwell},
  iosSettings: IosGeofenceSettings(initialTrigger: true),
  androidSettings: AndroidGeofenceSettings(
    initialTriggers: {GeofenceEvent.enter},
    expiration: const Duration(days: 7),
    loiteringDelay: const Duration(minutes: 5),
    notificationResponsiveness: const Duration(minutes: 5),
  ),
);

final zone4 = Geofence(
  id: 'zone4',
  location: Location(latitude: 14.4391, longitude: 120.8972), // Times Square
  radiusMeters: 500,
  triggers: {GeofenceEvent.enter, GeofenceEvent.exit, GeofenceEvent.dwell},
  iosSettings: IosGeofenceSettings(initialTrigger: true),
  androidSettings: AndroidGeofenceSettings(
    initialTriggers: {GeofenceEvent.enter},
    expiration: const Duration(days: 7),
    loiteringDelay: const Duration(minutes: 5),
    notificationResponsiveness: const Duration(minutes: 5),
  ),
);

final zone5 = Geofence(
  id: 'zone5',
  location: Location(latitude: 14.4404, longitude: 120.9006), // Times Square
  radiusMeters: 500,
  triggers: {GeofenceEvent.enter, GeofenceEvent.exit, GeofenceEvent.dwell},
  iosSettings: IosGeofenceSettings(initialTrigger: true),
  androidSettings: AndroidGeofenceSettings(
    initialTriggers: {GeofenceEvent.enter},
    expiration: const Duration(days: 7),
    loiteringDelay: const Duration(minutes: 5),
    notificationResponsiveness: const Duration(minutes: 5),
  ),
);

final zone6 = Geofence(
  id: 'zone6',
  location: Location(latitude: 14.4416, longitude: 120.9026), // Times Square
  radiusMeters: 500,
  triggers: {GeofenceEvent.enter, GeofenceEvent.exit, GeofenceEvent.dwell},
  iosSettings: IosGeofenceSettings(initialTrigger: true),
  androidSettings: AndroidGeofenceSettings(
    initialTriggers: {GeofenceEvent.enter},
    expiration: const Duration(days: 7),
    loiteringDelay: const Duration(minutes: 5),
    notificationResponsiveness: const Duration(minutes: 5),
  ),
);
