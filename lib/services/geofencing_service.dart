import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate' show ReceivePort;
import 'dart:typed_data';
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

  // Track active geofence notifications and their watchdog timers
  final Map<int, Timer> _notificationWatchdogs = {};
  final Map<int, Map<String, dynamic>> _activeNotifications = {};
  final Map<int, DateTime> _suppressedNotificationIds = {};
  final Map<int, DateTime> _suppressedTaskIds = {};
  static const Duration _defaultTtsSuppressionWindow = Duration(seconds: 12);

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
      _mapViewModel?.geofenceZoneSymbol;
  CircleAnnotationManager? get geofenceZoneHelper =>
      _mapViewModel?.geofenceZoneHelper;

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
      try {
        IsolateNameServer.removePortNameMapping('native_geofence_send_port');
        developer.log('[GeofencingService] Removed existing port mapping');
      } catch (e) {
        developer.log(
          '[GeofencingService] No existing port mapping to remove: $e',
        );
      }

      // Register the port for geofence events
      final bool registered = IsolateNameServer.registerPortWithName(
        _port.sendPort,
        'native_geofence_send_port',
      );

      if (!registered) {
        developer.log(
          '[GeofencingService] CRITICAL: Failed to register port with name "native_geofence_send_port"',
        );
        // Try to remove and register again
        try {
          IsolateNameServer.removePortNameMapping('native_geofence_send_port');
          await Future.delayed(const Duration(milliseconds: 100));
          final bool retryRegistered = IsolateNameServer.registerPortWithName(
            _port.sendPort,
            'native_geofence_send_port',
          );
          if (!retryRegistered) {
            throw Exception(
              'CRITICAL: Failed to register native_geofence_send_port after retry. '
              'Geofence notifications will NOT work. User should restart the app.',
            );
          }
          developer.log(
            '[GeofencingService] Port registered successfully on retry',
          );
        } catch (retryError) {
          developer.log(
            '[GeofencingService] CRITICAL: Port registration failed completely: $retryError',
          );
          rethrow;
        }
      } else {
        developer.log(
          '[GeofencingService] Port registered successfully on first attempt',
        );
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
              // Handle TTS requests from background isolate
              if (data['type'] == 'tts_request') {
                developer.log(
                  '[GeofencingService] Received TTS request from background isolate',
                );
                final String text = data['text'] as String? ?? '';
                final String context = data['context'] as String? ?? 'location';
                final bool allowTts = data['allowTts'] as bool? ?? true;
                final int? requestNotificationId = _coerceInt(
                  data['notificationId'],
                );
                final int? requestTaskId = _coerceInt(data['taskId']);

                if (!allowTts) {
                  developer.log(
                    '[GeofencingService] Skipping TTS request because task disabled TTS',
                  );
                  return;
                }

                if (_isTtsSuppressed(
                  notificationId: requestNotificationId,
                  taskId: requestTaskId,
                )) {
                  developer.log(
                    '[GeofencingService] Skipping TTS request because notification/task is suppressed',
                  );
                  return;
                }

                // Schedule TTS on next frame to ensure UI is ready
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  try {
                    developer.log(
                      '[GeofencingService] Initializing TTS service...',
                    );
                    final ttsService = TextToSpeechService();
                    await ttsService.init();
                    developer.log(
                      '[GeofencingService] Speaking: "$text" (context: $context)',
                    );
                    await ttsService.speakTaskNotification(text, context);
                    developer.log(
                      '[GeofencingService] TTS completed successfully',
                    );
                  } catch (e) {
                    developer.log('[GeofencingService] TTS failed: $e');
                  }
                });
                return; // Don't process as regular geofence event
              }

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

              // Check if any candidate is the active task
              bool isSameTask = false;
              if (hasActive && timerService.activeTask != null) {
                isSameTask = candidates.any(
                  (c) => c.id == timerService.activeTask!.id,
                );
              }

              if (hasActive &&
                  incomingHighest <= activePriority &&
                  !isSameTask) {
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
                          sp.send({'status': 'suppressed'});
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
                            '⏱️ Snooze 5m',
                            showsUserInterface: false,
                            cancelNotification: true,
                          ),
                          AndroidNotificationAction(
                            'com.intelliboro.SNOOZE_LATER',
                            '🔔 Snooze later',
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
                  final ttsEligible =
                      candidates.where((task) => task.ttsEnabled).toList();
                  if (ttsEligible.isNotEmpty) {
                    try {
                      final tts = TextToSpeechService();
                      await tts.init();
                      if (await tts.isAvailable() && tts.isEnabled) {
                        final message =
                            ttsEligible.length == 1
                                ? 'Task ${ttsEligible.first.taskName} has been snoozed and added to your pending list.'
                                : '${ttsEligible.length} tasks were snoozed and added to your pending list.';
                        await tts.speakTaskNotification(message, 'snooze');
                      }
                    } catch (ttsErr) {
                      developer.log(
                        '[GeofencingService] TTS for snooze failed: $ttsErr',
                      );
                    }
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

                  // Pick the single highest-priority candidate to show/speak
                  TaskModel? best;
                  double bestPrio = -double.infinity;
                  for (final c in candidates) {
                    final p = c.getEffectivePriority();
                    if (best == null ||
                        p > bestPrio ||
                        (p == bestPrio && (c.id ?? 0) < (best.id ?? 0))) {
                      best = c;
                      bestPrio = p;
                    }
                  }

                  if (best == null) {
                    developer.log(
                      '[GeofencingService] No best candidate found',
                    );
                    return;
                  }

                  final remainingCount = candidates.length - 1;
                  final title = 'Task reminder';
                  final body =
                      remainingCount > 0
                          ? 'You have task: ${best.taskName} (and $remainingCount more)'
                          : 'You have task: ${best.taskName}';

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
                      sp?.send({'status': 'suppressed'});
                      IsolateNameServer.removePortNameMapping(ackPortName);
                    }
                  } catch (_) {}

                  final AndroidNotificationDetails
                  androidDetails = AndroidNotificationDetails(
                    'geofence_alerts_v2', // Changed channel ID to force update
                    'Geofence Alerts',
                    channelDescription:
                        'Alerts when entering/exiting geofences',
                    importance: Importance.max,
                    priority: Priority.max,
                    playSound: true,
                    enableVibration: true,
                    vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
                    visibility: NotificationVisibility.public,
                    category: AndroidNotificationCategory.alarm,
                    fullScreenIntent: true,
                    styleInformation: const BigTextStyleInformation(''),
                    ongoing: true, // Cannot be dismissed by swiping
                    autoCancel: false, // Cannot be dismissed by swiping
                    onlyAlertOnce: true, // Only play sound/vibrate once
                    colorized: true,
                    color: const Color(
                      0xFFFF9800,
                    ), // Orange color for geofence alerts
                    actions: const <AndroidNotificationAction>[
                      AndroidNotificationAction(
                        'com.intelliboro.DO_NOW',
                        '▶️ Do task now',
                        showsUserInterface: true,
                        cancelNotification:
                            false, // Don't auto-dismiss, handled by action handler
                      ),
                      AndroidNotificationAction(
                        'com.intelliboro.DO_LATER',
                        '⏰ Do Later',
                        showsUserInterface: true,
                        cancelNotification:
                            false, // Don't auto-dismiss, handled by action handler
                      ),
                    ],
                  );

                  // Prefer to reuse the early/background notification id when
                  // available so the UI replaces the background notification
                  // instead of creating a duplicate.
                  final int uiNotifId =
                      notificationId ??
                      DateTime.now().millisecondsSinceEpoch.remainder(
                        2147483647,
                      );

                  final payloadData = {
                    'notificationId': uiNotifId,
                    'geofenceIds': geofenceIds,
                    'taskIds': [best.id],
                  };
                  final payload = jsonEncode(payloadData);

                  // Prefer using TaskTimerService.requestSwitch when there's an active task
                  try {
                    final timerService = TaskTimerService();
                    if (hasActive && !isSameTask) {
                      // If incoming is higher priority (and not same task), request switch
                      developer.log(
                        '[GeofencingService] Requesting switch to highest-priority task id=${best.id}, name=${best.taskName}, prio=$bestPrio',
                      );
                      await timerService.requestSwitch(best);
                    } else {
                      await plugin.show(
                        uiNotifId,
                        title,
                        body,
                        NotificationDetails(android: androidDetails),
                        payload: payload,
                      );
                      developer.log(
                        '[GeofencingService] Posted geofence alert notification $uiNotifId for task: ${best.id}',
                      );

                      // Start watchdog timer to prevent dismissal
                      _startNotificationWatchdog(
                        uiNotifId,
                        title,
                        body,
                        payloadData,
                      );

                      final bool suppressImmediateTts = _isTtsSuppressed(
                        notificationId: uiNotifId,
                        taskId: best.id,
                      );

                      // TTS in UI isolate only when explicitly allowed and not suppressed
                      if (!suppressImmediateTts && best.ttsEnabled) {
                        try {
                          final tts = TextToSpeechService();
                          await tts.init();
                          if (await tts.isAvailable() && tts.isEnabled) {
                            await tts.speakTaskNotification(
                              best.taskName,
                              'location',
                            );
                          }
                        } catch (ttsErr) {
                          developer.log(
                            '[GeofencingService] TTS failed: $ttsErr',
                          );
                        }
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
      try {
        IsolateNameServer.removePortNameMapping(newNotificationPortName);
        developer.log(
          '[GeofencingService] Removed existing $newNotificationPortName mapping',
        );
      } catch (e) {
        developer.log(
          '[GeofencingService] No existing $newNotificationPortName mapping: $e',
        );
      }

      final bool notifPortRegistered = IsolateNameServer.registerPortWithName(
        _newNotificationReceivePort.sendPort,
        newNotificationPortName,
      );

      if (!notifPortRegistered) {
        developer.log(
          '[GeofencingService] CRITICAL: Failed to register $newNotificationPortName',
        );
        // Retry once with delay
        try {
          await Future.delayed(const Duration(milliseconds: 100));
          IsolateNameServer.removePortNameMapping(newNotificationPortName);
          await Future.delayed(const Duration(milliseconds: 50));
          final bool retryRegistered = IsolateNameServer.registerPortWithName(
            _newNotificationReceivePort.sendPort,
            newNotificationPortName,
          );
          if (!retryRegistered) {
            throw Exception(
              'CRITICAL: Failed to register $newNotificationPortName after retry. '
              'Notification history updates will not work in real-time.',
            );
          }
          developer.log(
            '[GeofencingService] $newNotificationPortName registered on retry',
          );
        } catch (retryError) {
          developer.log(
            '[GeofencingService] CRITICAL: $newNotificationPortName registration failed: $retryError',
          );
          // Don't rethrow - allow service to continue even if this port fails
        }
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
      developer.log(
        '[GeofencingService] Creating native geofence with radius: ${radiusMeters}m at ${geometry.coordinates.lat}, ${geometry.coordinates.lng}',
      );
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
            }, // Don't fire on creation - only on actual boundary crossing
            notificationResponsiveness: const Duration(seconds: 5),
            loiteringDelay: const Duration(seconds: 0),
          ),
        ),
        geofenceTriggered,
      );

      _createdGeofenceIds.add(geofenceId);
      developer.log(
        'Geofence created successfully: $geofenceId with radius ${radiusMeters}m',
      );

      // Verify the geofence was registered with the native plugin
      try {
        final registeredGeofences =
            await native_geofence.NativeGeofenceManager.instance
                .getRegisteredGeofences();
        developer.log(
          '[GeofencingService] Currently registered geofences: $registeredGeofences',
        );
      } catch (e) {
        developer.log(
          '[GeofencingService] Failed to verify registered geofences: $e',
        );
      }

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

  /// Start a watchdog timer for a specific notification to prevent dismissal
  void _startNotificationWatchdog(
    int notificationId,
    String title,
    String body,
    Map<String, dynamic> payload,
  ) {
    // Cancel existing watchdog if any
    _stopNotificationWatchdog(notificationId);

    // Store notification details
    _activeNotifications[notificationId] = {
      'title': title,
      'body': body,
      'payload': payload,
    };

    // Re-show notification every 3 seconds to prevent permanent dismissal
    _notificationWatchdogs[notificationId] = Timer.periodic(
      const Duration(seconds: 3),
      (_) async {
        try {
          final notifData = _activeNotifications[notificationId];
          if (notifData == null) {
            _stopNotificationWatchdog(notificationId);
            return;
          }

          // Re-show the notification with the same ID
          final androidDetails = AndroidNotificationDetails(
            'geofence_alerts_v2', // Changed channel ID to match main alert
            'Geofence Alerts',
            channelDescription: 'Alerts when entering/exiting geofences',
            importance: Importance.max,
            priority: Priority.max,
            playSound: false, // Don't play sound on re-show
            enableVibration: false, // Don't vibrate on re-show
            visibility: NotificationVisibility.public,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            styleInformation: const BigTextStyleInformation(''),
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true, // Ensure silent update
            colorized: true,
            color: const Color(0xFFFF9800),
            actions: const <AndroidNotificationAction>[
              AndroidNotificationAction(
                'com.intelliboro.DO_NOW',
                '▶️ Do task now',
                showsUserInterface: true,
                cancelNotification: false,
              ),
              AndroidNotificationAction(
                'com.intelliboro.DO_LATER',
                '⏰ Do Later',
                showsUserInterface: true,
                cancelNotification: false,
              ),
            ],
          );

          await notificationPlugin.show(
            notificationId,
            notifData['title'] as String,
            notifData['body'] as String,
            NotificationDetails(android: androidDetails),
            payload: jsonEncode(notifData['payload']),
          );
        } catch (e) {
          developer.log(
            '[GeofencingService] Watchdog error for notification $notificationId: $e',
          );
        }
      },
    );

    developer.log(
      '[GeofencingService] Started watchdog for notification $notificationId',
    );
  }

  /// Stop the watchdog timer for a specific notification
  void _stopNotificationWatchdog(int notificationId) {
    developer.log(
      '[GeofencingService] Attempting to stop watchdog for notification $notificationId',
    );
    developer.log(
      '[GeofencingService] Active watchdogs: ${_notificationWatchdogs.keys.toList()}',
    );

    final timer = _notificationWatchdogs[notificationId];
    if (timer != null) {
      timer.cancel();
      _notificationWatchdogs.remove(notificationId);
      _activeNotifications.remove(notificationId);
      developer.log(
        '[GeofencingService] ✅ Successfully stopped watchdog for notification $notificationId',
      );
    } else {
      developer.log(
        '[GeofencingService] ⚠️ No watchdog found for notification $notificationId (may have been shown from background isolate)',
      );
    }
  }

  void suppressTtsForNotification(
    int? notificationId, {
    int? taskId,
    Duration duration = _defaultTtsSuppressionWindow,
  }) {
    if (notificationId == null && taskId == null) return;
    final expiry = DateTime.now().add(duration);
    _purgeExpiredTtsSuppressions();
    if (notificationId != null) {
      _suppressedNotificationIds[notificationId] = expiry;
    }
    if (taskId != null) {
      _suppressedTaskIds[taskId] = expiry;
    }
    developer.log(
      '[GeofencingService] Suppressed TTS for notification=$notificationId taskId=$taskId until $expiry',
    );
  }

  bool _isTtsSuppressed({int? notificationId, int? taskId}) {
    _purgeExpiredTtsSuppressions();
    final now = DateTime.now();
    if (notificationId != null) {
      final expiry = _suppressedNotificationIds[notificationId];
      if (expiry != null) {
        if (now.isBefore(expiry)) return true;
        _suppressedNotificationIds.remove(notificationId);
      }
    }
    if (taskId != null) {
      final expiry = _suppressedTaskIds[taskId];
      if (expiry != null) {
        if (now.isBefore(expiry)) return true;
        _suppressedTaskIds.remove(taskId);
      }
    }
    return false;
  }

  void _purgeExpiredTtsSuppressions() {
    final now = DateTime.now();
    _suppressedNotificationIds.removeWhere((_, expiry) => expiry.isBefore(now));
    _suppressedTaskIds.removeWhere((_, expiry) => expiry.isBefore(now));
  }

  int? _coerceInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Public method to stop watchdog for a notification (called when notification is dismissed)
  void stopNotificationWatchdog(int notificationId) {
    _stopNotificationWatchdog(notificationId);
  }

  /// Stop all active notification watchdogs
  void _stopAllNotificationWatchdogs() {
    for (final timer in _notificationWatchdogs.values) {
      timer.cancel();
    }
    _notificationWatchdogs.clear();
    _activeNotifications.clear();
    developer.log('[GeofencingService] Stopped all notification watchdogs');
  }

  // Clean up resources
  void dispose() {
    try {
      developer.log(
        '[GeofencingService] Global dispose called. This should be rare.',
      );

      // Stop all watchdog timers
      _stopAllNotificationWatchdogs();

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
