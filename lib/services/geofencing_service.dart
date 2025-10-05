import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate' show ReceivePort;
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:native_geofence/native_geofence.dart' as native_geofence;
import 'package:intelliboro/viewmodel/Geofencing/map_viewmodel.dart';
import 'package:intelliboro/viewmodel/notifications/callback.dart'
    show geofenceTriggered;
import 'dart:convert';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intelliboro/services/notification_service.dart'
    show notificationPlugin;
import 'package:intelliboro/services/text_to_speech_service.dart';

class GeofencingService {
  // --- Singleton implementation ---
  static final GeofencingService _instance = GeofencingService._internal();

  factory GeofencingService() => _instance;

  // --- End Singleton implementation ---

  // A reference to the MapViewModel is problematic for a singleton service.
  // We will manage map interactions via methods instead.
  MapboxMapViewModel? _mapViewModel;

  // Track created geofence IDs for management
  final Set<String> _createdGeofenceIds = {};
  bool _isInitialized = false;
  final ReceivePort _port =
      ReceivePort(); // For native_geofence plugin if it used ports

  // Port for our app's background->UI notification events
  final ReceivePort _newNotificationReceivePort = ReceivePort();
  final StreamController<void> _newNotificationStreamController =
      StreamController<void>.broadcast();

  // Private internal constructor
  GeofencingService._internal();

  // Stream for UI to listen for new notification events from background
  Stream<void> get newNotificationEvents =>
      _newNotificationStreamController.stream;

  // Allow a view model to register itself for map updates
  void registerMapViewModel(MapboxMapViewModel viewModel) {
    _mapViewModel = viewModel;
    developer.log('[GeofencingService] MapViewModel registered.');
  }

  // Allow a view model to unregister itself
  void unregisterMapViewModel() {
    _mapViewModel = null;
    developer.log('[GeofencingService] MapViewModel unregistered.');
  }

  CircleAnnotationManager? get geofenceZoneSymbol =>
      _mapViewModel?.getGeofenceZoneSymbol();
  CircleAnnotationManager? get geofenceZoneHelper =>
      _mapViewModel?.getGeofenceZonePicker();

  Future<void> init() async {
    // init() now guards against multiple executions
    if (_isInitialized) {
      developer.log('[GeofencingService] Already initialized, skipping.');
      return;
    }
    await _initialize();
  }

  Future<void> _initialize() async {
    if (_isInitialized) {
      developer.log('[GeofencingService] Already initialized, skipping.');
      return;
    }

    try {
      // First, ensure any existing port mapping is removed
      IsolateNameServer.removePortNameMapping('native_geofence_send_port');

      // Register the port for geofence events
      final bool registered = IsolateNameServer.registerPortWithName(
        _port.sendPort,
        'native_geofence_send_port',
      );

      if (!registered) {
        developer.log(
          '[GeofencingService] WARNING: Failed to register port with name "native_geofence_send_port"',
        );
        // Try to remove and register again
        IsolateNameServer.removePortNameMapping('native_geofence_send_port');
        final bool retryRegistered = IsolateNameServer.registerPortWithName(
          _port.sendPort,
          'native_geofence_send_port',
        );
        if (!retryRegistered) {
          throw Exception('Failed to register port after retry');
        }
      }

      // Listen for geofence events on the port. Messages originate from the
      // background geofence callback isolate and include a 'notificationId',
      // 'geofenceIds' and optionally 'taskIds'. We process the message on the
      // UI isolate to decide whether to immediately show the notification or
      // to snooze the incoming tasks if a higher-priority task is active.
      _port.listen((dynamic data) {
        developer.log(
          '[GeofencingService] Received on native_geofence_send_port: $data',
        );

        Future.microtask(() async {
          try {
            if (data is Map) {
              final dynamic nid = data['notificationId'];
              final int? notificationId =
                  nid is int ? nid : (nid is String ? int.tryParse(nid) : null);
              final List<dynamic> geofenceIds =
                  (data['geofenceIds'] as List<dynamic>?) ?? [];
              final List<dynamic> payloadTaskIds =
                  (data['taskIds'] as List<dynamic>?) ?? [];

              // Resolve candidate tasks. Prefer explicit taskIds when provided.
              final List<TaskModel> candidates = [];
              final taskRepo = TaskRepository();
              if (payloadTaskIds.isNotEmpty) {
                for (final tid in payloadTaskIds) {
                  final int? parsed =
                      tid is int
                          ? tid
                          : (tid is String ? int.tryParse(tid) : null);
                  if (parsed != null) {
                    final t = await taskRepo.getTaskById(parsed);
                    if (t != null && !t.isCompleted) candidates.add(t);
                  }
                }
              }
              if (candidates.isEmpty && geofenceIds.isNotEmpty) {
                final all = await taskRepo.getTasks();
                candidates.addAll(
                  all.where(
                    (t) =>
                        t.geofenceId != null &&
                        geofenceIds.contains(t.geofenceId) &&
                        !t.isCompleted,
                  ),
                );
              }

              if (candidates.isEmpty) return;

              // If there's an active task with higher effective priority, snooze incoming
              final timerService = TaskTimerService();
              final bool hasActive = timerService.hasActiveTask;
              double activePriority = -1;
              if (hasActive) {
                activePriority =
                    timerService.activeTask!.getEffectivePriority();
              }

              // Log candidate details for debugging
              try {
                final candidateSummary = candidates
                    .map(
                      (c) =>
                          'id=${c.id},name=${c.taskName},prio=${c.getEffectivePriority()}',
                    )
                    .join(' | ');
                developer.log(
                  '[GeofencingService] Candidate tasks: $candidateSummary',
                );
              } catch (_) {}

              // Find highest incoming priority
              final incomingHighest = candidates
                  .map((c) => c.getEffectivePriority())
                  .fold<double>(0, (p, e) => e > p ? e : p);

              developer.log(
                '[GeofencingService] Active priority: ${hasActive ? activePriority : 'none'}, Incoming highest: $incomingHighest',
              );

              if (hasActive && incomingHighest <= activePriority) {
                developer.log(
                  '[GeofencingService] Active task has higher/equal priority; snoozing incoming ${candidates.length} tasks',
                );

                // Add each incoming task to pending and attempt to pause geofence monitoring
                for (final c in candidates) {
                  try {
                    await timerService.addToPending(
                      c,
                      timerService.defaultSnoozeDuration,
                    );
                    // Ensure UI is notified of task list changes
                    try {
                      timerService.tasksChanged.value = true;
                    } catch (_) {}
                  } catch (e) {
                    developer.log(
                      '[GeofencingService] Failed to add task ${c.id} to pending: $e',
                    );
                  }
                }

                // Cancel the notification so the user doesn't see the normal alert
                if (notificationId != null) {
                  try {
                    await notificationPlugin.cancel(notificationId);
                    developer.log(
                      '[GeofencingService] Cancelled notification $notificationId due to active task',
                    );
                    // If the background callback registered an ack port name, notify it
                    try {
                      final String? ackPortName =
                          data['ackPortName'] as String?;
                      if (ackPortName != null) {
                        final sp = IsolateNameServer.lookupPortByName(
                          ackPortName,
                        );
                        if (sp != null) {
                          sp.send('suppressed');
                          developer.log(
                            '[GeofencingService] Sent suppression ack to $ackPortName',
                          );
                        }
                        // Remove ack port mapping if present to avoid leaks
                        IsolateNameServer.removePortNameMapping(ackPortName);
                      }
                    } catch (e) {
                      developer.log(
                        '[GeofencingService] Failed to send ack to background isolate: $e',
                      );
                    }
                  } catch (e) {
                    developer.log(
                      '[GeofencingService] Failed to cancel notification $notificationId: $e',
                    );
                  }
                }

                // Optionally pause native geofence monitoring for those ids to avoid repeated triggers
                for (final gid in geofenceIds) {
                  try {
                    final idStr = gid is String ? gid : gid.toString();
                    await native_geofence.NativeGeofenceManager.instance
                        .removeGeofenceById(idStr);
                    developer.log(
                      '[GeofencingService] Temporarily removed native geofence $idStr due to snooze',
                    );
                  } catch (e) {
                    developer.log(
                      '[GeofencingService] Failed to remove native geofence for snooze: $e',
                    );
                  }
                }

                // Inform the user that tasks were added to do later and provide quick snooze actions
                try {
                  final plugin = notificationPlugin;
                  final List<int> ids =
                      candidates.map((c) => c.id).whereType<int>().toList();
                  final title = 'Added to Do Later';
                  final names = candidates.map((c) => c.taskName).join(', ');
                  final body =
                      ids.length == 1
                          ? '${names} added to do later. Snooze 5 minutes or choose later.'
                          : 'Added to do later: ${names}. Snooze 5 minutes or choose later.';

                  final payload = jsonEncode({'taskIds': ids});

                  final int newNotifId = DateTime.now().millisecondsSinceEpoch
                      .remainder(2147483647);
                  final AndroidNotificationDetails androidDetails =
                      AndroidNotificationDetails(
                        'geofence_alerts',
                        'Geofence Alerts',
                        channelDescription:
                            'Pending tasks and quick snooze actions',
                        importance: Importance.defaultImportance,
                        priority: Priority.defaultPriority,
                        actions: <AndroidNotificationAction>[
                          AndroidNotificationAction(
                            'com.intelliboro.SNOOZE_5',
                            'Snooze 5m',
                            showsUserInterface: false,
                            cancelNotification: true,
                          ),
                          AndroidNotificationAction(
                            'com.intelliboro.SNOOZE_LATER',
                            'Snooze later',
                            showsUserInterface: true,
                            cancelNotification: true,
                          ),
                        ],
                      );

                  await plugin.show(
                    newNotifId,
                    title,
                    body,
                    NotificationDetails(android: androidDetails),
                    payload: payload,
                  );
                  developer.log(
                    '[GeofencingService] Posted pending notification $newNotifId for tasks: $ids',
                  );
                  // Also try to trigger a brief TTS that indicates tasks were snoozed
                  try {
                    final tts = TextToSpeechService();
                    await tts.init();
                    if (await tts.isAvailable() && tts.isEnabled) {
                      await tts.speakTaskNotification(
                        ids.length == 1
                            ? 'Task ${names} has been snoozed and added to your pending list.'
                            : '${ids.length} tasks were snoozed and added to your pending list.',
                        'snooze',
                      );
                    }
                  } catch (ttsErr) {
                    developer.log(
                      '[GeofencingService] TTS for snooze failed: $ttsErr',
                    );
                  }
                } catch (e) {
                  developer.log(
                    '[GeofencingService] Failed to post pending notification: $e',
                  );
                }
              } else {
                // No active task OR incomingHigher > activePriority: show the immediate geofence alert notification now
                try {
                  final plugin = notificationPlugin;
                  final List<int> ids =
                      candidates.map((c) => c.id).whereType<int>().toList();
                  final names = candidates.map((c) => c.taskName).join(', ');
                  final title =
                      ids.length == 1 ? 'Task reminder' : 'Nearby tasks';
                  final body =
                      ids.length == 1
                          ? 'You entered the area for "$names".'
                          : 'You entered areas for: ${names}';

                  // Ensure we cancel the early background notification (to avoid duplicates)
                  if (notificationId != null) {
                    try {
                      await plugin.cancel(notificationId);
                    } catch (_) {}
                  }

                  // Send ack to background isolate to suppress its own audible/TTS path
                  try {
                    final String? ackPortName = data['ackPortName'] as String?;
                    if (ackPortName != null) {
                      final sp = IsolateNameServer.lookupPortByName(
                        ackPortName,
                      );
                      sp?.send('suppressed');
                      IsolateNameServer.removePortNameMapping(ackPortName);
                    }
                  } catch (_) {}

                  const AndroidNotificationDetails androidDetails =
                      AndroidNotificationDetails(
                        'geofence_alerts',
                        'Geofence Alerts',
                        channelDescription:
                            'Alerts when entering/exiting geofences',
                        importance: Importance.max,
                        priority: Priority.max,
                        playSound: true,
                        visibility: NotificationVisibility.public,
                        category: AndroidNotificationCategory.alarm,
                        fullScreenIntent: true,
                        styleInformation: BigTextStyleInformation(''),
                        actions: <AndroidNotificationAction>[
                          AndroidNotificationAction(
                            'com.intelliboro.DO_NOW',
                            'Do Now',
                            showsUserInterface: true,
                            cancelNotification: true,
                          ),
                          AndroidNotificationAction(
                            'com.intelliboro.DO_LATER',
                            'Do Later',
                            showsUserInterface: false,
                            cancelNotification: false,
                          ),
                        ],
                      );

                  // Use a fresh id for the UI alert
                  final int uiNotifId = DateTime.now().millisecondsSinceEpoch
                      .remainder(2147483647);

                  final payload = jsonEncode({
                    'notificationId': uiNotifId,
                    'geofenceIds': geofenceIds,
                    'taskIds': ids,
                  });

                  // Prefer using TaskTimerService.requestSwitch when there's an active task
                  try {
                    final timerService = TaskTimerService();
                    if (hasActive) {
                      // If incoming is higher priority, request switch which will
                      // interrupt current task and post the switch notification.
                      // Pick only the single highest-priority candidate to avoid
                      // multiple overlapping switch requests.
                      TaskModel? best;
                      double bestPrio = -double.infinity;
                      for (final c in candidates) {
                        final p = c.getEffectivePriority();
                        if (best == null || p > bestPrio) {
                          best = c;
                          bestPrio = p;
                        }
                      }
                      if (best != null) {
                        developer.log(
                          '[GeofencingService] Requesting switch to highest-priority task id=${best.id}, name=${best.taskName}, prio=$bestPrio',
                        );
                        await timerService.requestSwitch(best);
                      }
                    } else {
                      await plugin.show(
                        uiNotifId,
                        title,
                        body,
                        NotificationDetails(android: androidDetails),
                        payload: payload,
                      );
                      developer.log(
                        '[GeofencingService] Posted geofence alert notification $uiNotifId for tasks: $ids',
                      );

                      // Optional: brief TTS in UI isolate
                      try {
                        final tts = TextToSpeechService();
                        await tts.init();
                        if (await tts.isAvailable() && tts.isEnabled) {
                          await tts.speakTaskNotification(
                            ids.length == 1
                                ? 'Reminder: $names'
                                : 'You have ${ids.length} nearby tasks.',
                            'location',
                          );
                        }
                      } catch (ttsErr) {
                        developer.log(
                          '[GeofencingService] TTS failed: $ttsErr',
                        );
                      }
                    }
                  } catch (e) {
                    developer.log(
                      '[GeofencingService] Error requesting switch or posting notification: $e',
                    );
                  }
                } catch (e) {
                  developer.log(
                    '[GeofencingService] Failed to show geofence alert: $e',
                  );
                }
              }
            }
          } catch (e, st) {
            developer.log(
              '[GeofencingService] Error processing port message: $e',
              error: e,
              stackTrace: st,
            );
          }
        });
      });

      // Register and listen to our app-specific notification port
      final String newNotificationPortName =
          'intelliboro_new_notification_port';
      IsolateNameServer.removePortNameMapping(
        newNotificationPortName,
      ); // Ensure clean slate
      if (!IsolateNameServer.registerPortWithName(
        _newNotificationReceivePort.sendPort,
        newNotificationPortName,
      )) {
        developer.log(
          '[GeofencingService] CRITICAL: Failed to register $newNotificationPortName',
        );
        // Potentially throw an error or handle more gracefully
      } else {
        developer.log(
          '[GeofencingService] Successfully registered $newNotificationPortName',
        );
      }

      _newNotificationReceivePort.listen((dynamic message) {
        developer.log(
          '[GeofencingService] Received on $newNotificationPortName: $message - forwarding to stream.',
        );
        _newNotificationStreamController.add(null); // Send a void event
      });

      // Initialize the geofence plugin
      await native_geofence.NativeGeofenceManager.instance.initialize();

      // Verify initialization by checking monitored regions
      final regions =
          await native_geofence.NativeGeofenceManager.instance
              .getRegisteredGeofences();
      developer.log(
        '[GeofencingService] Currently monitoring regions: $regions',
      );

      _isInitialized = true;
      developer.log('[GeofencingService] Successfully initialized');
    } catch (e, stackTrace) {
      developer.log(
        '[GeofencingService] Error during initialization: $e\n$stackTrace',
      );
      rethrow;
    }
  }

  // Reference to the top-level callback function for geofence events
  // static final geofenceCallback = geofenceTriggered;

  Future<void> createGeofence({
    required Point geometry,
    required double radiusMeters,
    String? customId,
    Color fillColor = Colors.amberAccent,
    Color strokeColor = Colors.white,
    double strokeWidth = 2.0,
    double fillOpacity = 0.5,
  }) async {
    if (!_isInitialized) {
      await _initialize();
    }

    try {
      developer.log('Creating geofence at ${geometry.coordinates}');

      // Generate a unique ID if not provided
      final geofenceId =
          customId ?? 'geofence_${DateTime.now().millisecondsSinceEpoch}';

      // If the geofence already exists in our tracking set, remove it first
      if (_createdGeofenceIds.contains(geofenceId)) {
        developer.log('Geofence $geofenceId already exists, removing it first');
        await removeGeofence(geofenceId);
      }

      // Create the visual representation on the map
      await _createGeofenceVisual(
        id: geofenceId,
        geometry: geometry,
        radiusMeters: radiusMeters,
        fillColor: fillColor,
        fillOpacity: fillOpacity,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
      );

      // Create the native geofence
      await native_geofence.NativeGeofenceManager.instance.createGeofence(
        native_geofence.Geofence(
          id: geofenceId,
          location: native_geofence.Location(
            latitude: geometry.coordinates.lat.toDouble(),
            longitude: geometry.coordinates.lng.toDouble(),
          ),
          radiusMeters: radiusMeters,
          triggers: {
            native_geofence.GeofenceEvent.enter,
            native_geofence.GeofenceEvent.exit,
          },
          iosSettings: native_geofence.IosGeofenceSettings(
            initialTrigger: false,
          ),
          androidSettings: native_geofence.AndroidGeofenceSettings(
            initialTriggers: {
              native_geofence.GeofenceEvent.enter,
              native_geofence.GeofenceEvent.exit,
            },
            notificationResponsiveness: const Duration(seconds: 0),
            loiteringDelay: const Duration(seconds: 0),
          ),
        ),
        geofenceTriggered,
      );

      _createdGeofenceIds.add(geofenceId);
      developer.log('Geofence created successfully: $geofenceId');

      return Future.value();
    } catch (e, stackTrace) {
      developer.log(
        'Error in createGeofence',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _createGeofenceVisual({
    required String id,
    required Point geometry,
    required double radiusMeters,
    required Color fillColor,
    required double fillOpacity,
    required Color strokeColor,
    required double strokeWidth,
  }) async {
    try {
      // Check if a map view model is available before doing visual tasks
      if (_mapViewModel == null) {
        developer.log(
          '[GeofencingService] No MapViewModel registered, skipping visual creation.',
        );
        return; // Can't create visual without a map
      }

      final zoomLevel = await _mapViewModel!.currentZoomLevel();

      // Get the conversion factor using the specific geofence latitude for consistency
      // This ensures existing and new geofences use the same calculation method
      final metersPerPixelConversionFactor = await _mapViewModel!
          .mapboxMap!
          .projection
          .getMetersPerPixelAtLatitude(
            geometry.coordinates.lat.toDouble(),
            zoomLevel,
          );

      if (metersPerPixelConversionFactor == 0.0) {
        developer.log(
          'Error in _createGeofenceVisual: metersPerPixelConversionFactor is 0.0. Cannot calculate radius in pixels.',
        );
        // Potentially throw an error or return, as radiusInPixels will be invalid (Infinity or NaN)
        throw Exception(
          "Failed to calculate meters per pixel for geofence visual.",
        );
      }

      // Calculate radius in pixels
      final radiusInPixels = radiusMeters / metersPerPixelConversionFactor;

      developer.log('''
        Creating geofence visual:
        - ID: $id
        - Position: ${geometry.coordinates.lat}, ${geometry.coordinates.lng}
        - Radius: ${radiusMeters}m (${radiusInPixels.toStringAsFixed(2)}px)
        - Zoom: $zoomLevel
      ''');

      if (geofenceZoneHelper == null) {
        throw StateError('Geofence zone symbol helper is null');
      }

      final annotation = await geofenceZoneSymbol!.create(
        CircleAnnotationOptions(
          geometry: geometry,
          circleRadius: radiusInPixels,
          circleColor: fillColor.value,
          circleOpacity: fillOpacity,
          circleStrokeColor: strokeColor.value,
          circleStrokeWidth: strokeWidth,
        ),
      );

      _mapViewModel!.geofenceZoneSymbolIds.add(annotation);
      developer.log('Geofence visual created: $id');
    } catch (e, stackTrace) {
      developer.log(
        'Error creating geofence visual',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // Note: The implementation that interacts with the native geofence plugin
  // is performed inline in `createGeofence(...)`. The old helper `_createNativeGeofence`
  // was removed as it was unused and caused an analyzer warning.

  // Store created geofences to be able to remove them later
  final Map<String, native_geofence.Geofence> _geofenceCache = {};

  Future<void> removeGeofence(String id) async {
    try {
      developer.log('Attempting to remove geofence: $id');

      // Even if we didn't previously track this geofence in _createdGeofenceIds,
      // attempt native removal. This handles cases where the app or DB state
      // got out of sync with the native plugin (or after app restarts).
      try {
        await native_geofence.NativeGeofenceManager.instance.removeGeofenceById(
          id,
        );
        developer.log('Successfully removed native geofence: $id');
      } catch (e) {
        developer.log(
          'Error removing native geofence $id (this might be normal if it was already removed or plugin state is different): $e',
        );
        // Continue - we still want to attempt DB/cache cleanup below
      }

      // Remove local bookkeeping entries if present
      if (_createdGeofenceIds.contains(id)) {
        _createdGeofenceIds.remove(id);
      } else {
        developer.log('Geofence $id was not present in _createdGeofenceIds');
      }

      if (_geofenceCache.containsKey(id)) {
        _geofenceCache.remove(id);
      }

      developer.log('Completed removal of geofence: $id');
    } catch (e, stackTrace) {
      developer.log(
        'Error in removeGeofence for $id',
        error: e,
        stackTrace: stackTrace,
      );
      // Still don't rethrow - we want the calling code to continue even if removal fails
    }
  }

  Future<void> removeAllGeofences() async {
    try {
      await native_geofence.NativeGeofenceManager.instance.removeAllGeofences();
      developer.log('All geofences removed');
    } catch (e, stackTrace) {
      developer.log(
        'Error removing all geofences',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // Clean up resources
  void dispose() {
    try {
      developer.log(
        '[GeofencingService] Global dispose called. This should be rare.',
      );

      // Do NOT close the port or remove the port mapping here
      // as it needs to stay alive for geofence callbacks
      // _port.close();
      // IsolateNameServer.removePortNameMapping('native_geofence_send_port');

      _createdGeofenceIds.clear();
      _isInitialized = false;

      // Clean up our app-specific notification port and stream controller
      IsolateNameServer.removePortNameMapping(
        'intelliboro_new_notification_port',
      );
      _newNotificationReceivePort.close();
      _newNotificationStreamController.close();
      developer.log(
        '[GeofencingService] Cleaned up app-specific notification resources.',
      );
    } catch (e, stackTrace) {
      developer.log(
        'Error disposing GeofencingService',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
