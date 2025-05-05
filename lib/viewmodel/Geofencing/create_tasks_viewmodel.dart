import 'package:flutter/material.dart';
import 'package:native_geofence/native_geofence.dart';



// class Geofence extends ChangeNotifier {
//   //Geofence
//   List<String> activeGeofences = [];
//   // field data has not been initalized
//   late Geofence data;

//   static const Location _initialLocation = Location(
//     latitude: 0.00,
//     longitude: 0.00,
//   );

//   @override
//   void initState() {
//     super.initState();
//     data = Geofence(
//       id: 'zone1',
//       location: _initialLocation,
//       radiusMeters: 500,
//       triggers: {GeofenceEvent.enter, GeofenceEvent.exit},
//       iosSettings: IosGeofenceSettings(initialTrigger: true),
//       androidSettings: AndroidGeofenceSettings(
//         initialTriggers: {GeofenceEvent.enter},
//       ),
//     );
//     _updateRegisteredGeofences();
//   }
// }

// extension ModifyGeofence on Geofence {
//   Geofence copyWith({
//     String Function()? id,
//     Location Function()? location,
//     double Function()? radiusMeters,
//     Set<GeofenceEvent> Function()? triggers,
//     IosGeofenceSettings Function()? iosSettings,
//     AndroidGeofenceSettings Function()? androidSettings,
//   }) {
//     return Geofence(
//       id: id?.call() ?? this.id,
//       location: location?.call() ?? this.location,
//       radiusMeters: radiusMeters?.call() ?? this.radiusMeters,
//       triggers: triggers?.call() ?? this.triggers,
//       iosSettings: iosSettings?.call() ?? this.iosSettings,
//       androidSettings: androidSettings?.call() ?? this.androidSettings,
//     );
//   }
// }

// extension ModifyLocation on Location {
//   Location copyWith({double? latitude, double? longitude}) {
//     return Location(
//       latitude: latitude ?? this.latitude,
//       longitude: longitude ?? this.longitude,
//     );
//   }
// }

// extension ModifyAndroidGeofenceSettings on AndroidGeofenceSettings {
//   AndroidGeofenceSettings copyWith({
//     Set<GeofenceEvent> Function()? initialTrigger,
//     Duration Function()? expiration,
//     Duration Function()? loiteringDelay,
//     Duration Function()? notificationResponsiveness,
//   }) {
//     return AndroidGeofenceSettings(
//       initialTriggers: initialTrigger?.call() ?? this.initialTriggers,
//       expiration: expiration?.call() ?? this.expiration,
//       loiteringDelay: loiteringDelay?.call() ?? this.loiteringDelay,
//       notificationResponsiveness:
//           notificationResponsiveness?.call() ?? this.notificationResponsiveness,
//     );
//   }
// }
