import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/services/text_to_speech_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enumeration of context types that can trigger TTS notifications
enum ContextType {
  location,
  time,
  battery,
  connectivity,
  calendar,
  manual
}

/// Context data structure
class ContextData {
  final ContextType type;
  final String description;
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  ContextData({
    required this.type,
    required this.description,
    this.metadata = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    return 'ContextData{type: $type, description: $description, metadata: $metadata, timestamp: $timestamp}';
  }
}

/// Service for detecting contexts and triggering appropriate TTS notifications
class ContextDetectionService {
  static final ContextDetectionService _instance = ContextDetectionService._internal();
  factory ContextDetectionService() => _instance;
  ContextDetectionService._internal();

  final TextToSpeechService _ttsService = TextToSpeechService();
  
  // Context detection settings
  bool _isEnabled = true;
  bool _locationContextEnabled = true;
  bool _timeContextEnabled = true;
  bool _batteryContextEnabled = false;
  bool _connectivityContextEnabled = false;
  
  // Context-specific settings
  int _batteryThreshold = 20; // Battery percentage threshold
  Duration _timeContextWindow = const Duration(minutes: 5); // Time window for task reminders
  
  // Stream controllers for context events
  final StreamController<ContextData> _contextStreamController = 
      StreamController<ContextData>.broadcast();
  
  // Timer for periodic context checks
  Timer? _contextTimer;
  
  // Keys for SharedPreferences
  static const String _enabledKey = 'context_detection_enabled';
  static const String _locationContextKey = 'location_context_enabled';
  static const String _timeContextKey = 'time_context_enabled';
  static const String _batteryContextKey = 'battery_context_enabled';
  static const String _connectivityContextKey = 'connectivity_context_enabled';
  static const String _batteryThresholdKey = 'battery_threshold';
  static const String _timeWindowKey = 'time_context_window_minutes';

  /// Initialize the context detection service
  Future<void> init() async {
    try {
      // Load settings
      await _loadSettings();
      
      // Initialize TTS service
      await _ttsService.init();
      
      // Start context monitoring if enabled
      if (_isEnabled) {
        _startContextMonitoring();
      }
      
      developer.log('[ContextDetectionService] Successfully initialized');
    } catch (e, stackTrace) {
      developer.log(
        '[ContextDetectionService] Error during initialization: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      _isEnabled = prefs.getBool(_enabledKey) ?? true;
      _locationContextEnabled = prefs.getBool(_locationContextKey) ?? true;
      _timeContextEnabled = prefs.getBool(_timeContextKey) ?? true;
      _batteryContextEnabled = prefs.getBool(_batteryContextKey) ?? false;
      _connectivityContextEnabled = prefs.getBool(_connectivityContextKey) ?? false;
      _batteryThreshold = prefs.getInt(_batteryThresholdKey) ?? 20;
      
      final timeWindowMinutes = prefs.getInt(_timeWindowKey) ?? 5;
      _timeContextWindow = Duration(minutes: timeWindowMinutes);

      developer.log('[ContextDetectionService] Settings loaded');
    } catch (e) {
      developer.log('[ContextDetectionService] Error loading settings: $e');
    }
  }

  /// Save settings to SharedPreferences
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      await prefs.setBool(_enabledKey, _isEnabled);
      await prefs.setBool(_locationContextKey, _locationContextEnabled);
      await prefs.setBool(_timeContextKey, _timeContextEnabled);
      await prefs.setBool(_batteryContextKey, _batteryContextEnabled);
      await prefs.setBool(_connectivityContextKey, _connectivityContextEnabled);
      await prefs.setInt(_batteryThresholdKey, _batteryThreshold);
      await prefs.setInt(_timeWindowKey, _timeContextWindow.inMinutes);

      developer.log('[ContextDetectionService] Settings saved');
    } catch (e) {
      developer.log('[ContextDetectionService] Error saving settings: $e');
    }
  }

  /// Start monitoring contexts
  void _startContextMonitoring() {
    // Start a timer for periodic context checks
    _contextTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkTimeContext();
      _checkBatteryContext();
      _checkConnectivityContext();
    });
    
    developer.log('[ContextDetectionService] Context monitoring started');
  }

  /// Stop monitoring contexts
  void _stopContextMonitoring() {
    _contextTimer?.cancel();
    _contextTimer = null;
    developer.log('[ContextDetectionService] Context monitoring stopped');
  }

  /// Check time-based context for tasks
  void _checkTimeContext() {
    if (!_timeContextEnabled) return;
    
    // This would be integrated with your task repository to check for upcoming tasks
    // For now, this is a placeholder for the time context detection logic
    developer.log('[ContextDetectionService] Checking time context');
  }

  /// Check battery context
  void _checkBatteryContext() {
    if (!_batteryContextEnabled) return;
    
    // Battery level checking would be implemented here
    // This is a placeholder for battery context detection
    developer.log('[ContextDetectionService] Checking battery context');
  }

  /// Check connectivity context
  void _checkConnectivityContext() {
    if (!_connectivityContextEnabled) return;
    
    // Network connectivity checking would be implemented here
    // This is a placeholder for connectivity context detection
    developer.log('[ContextDetectionService] Checking connectivity context');
  }

  /// Manually trigger a context detection for a specific task
  Future<void> triggerContextForTask(TaskModel task, ContextType contextType, {Map<String, dynamic>? metadata}) async {
    if (!_isEnabled) {
      developer.log('[ContextDetectionService] Context detection is disabled');
      return;
    }

    try {
      final contextData = ContextData(
        type: contextType,
        description: _getContextDescription(contextType),
        metadata: metadata ?? {},
      );

      // Add context to stream
      _contextStreamController.add(contextData);

      // Trigger TTS notification
      await _triggerTtsNotification(task, contextData);

      developer.log('[ContextDetectionService] Context triggered for task: ${task.taskName}');
    } catch (e, stackTrace) {
      developer.log(
        '[ContextDetectionService] Error triggering context for task: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Trigger TTS notification for a task based on context
  Future<void> _triggerTtsNotification(TaskModel task, ContextData context) async {
    try {
      String contextString = _getContextString(context.type);
      await _ttsService.speakTaskNotification(task.taskName, contextString);
      
      developer.log('[ContextDetectionService] TTS notification triggered for task: ${task.taskName} with context: ${context.type}');
    } catch (e) {
      developer.log('[ContextDetectionService] Error triggering TTS notification: $e');
    }
  }

  /// Get context description
  String _getContextDescription(ContextType type) {
    switch (type) {
      case ContextType.location:
        return 'Location-based context detected';
      case ContextType.time:
        return 'Time-based context detected';
      case ContextType.battery:
        return 'Battery level context detected';
      case ContextType.connectivity:
        return 'Connectivity context detected';
      case ContextType.calendar:
        return 'Calendar context detected';
      case ContextType.manual:
        return 'Manual context trigger';
    }
  }

  /// Get context string for TTS
  String _getContextString(ContextType type) {
    switch (type) {
      case ContextType.location:
        return 'location';
      case ContextType.time:
        return 'time';
      case ContextType.battery:
        return 'urgent';
      case ContextType.connectivity:
        return 'connectivity';
      case ContextType.calendar:
        return 'calendar';
      case ContextType.manual:
        return 'manual';
    }
  }

  /// Handle geofence-triggered context (integration with existing geofence system)
  Future<void> handleGeofenceContext(String taskName, String geofenceId, {Map<String, dynamic>? metadata}) async {
    if (!_locationContextEnabled) return;

    try {
      final contextData = ContextData(
        type: ContextType.location,
        description: 'Geofence context triggered',
        metadata: {
          'geofence_id': geofenceId,
          ...?metadata,
        },
      );

      _contextStreamController.add(contextData);
      
      // Create a temporary task model for TTS
      final tempTask = TaskModel(
        taskName: taskName,
        taskPriority: 1,
        taskTime: const TimeOfDay(hour: 0, minute: 0),
        taskDate: DateTime.now(),
        isRecurring: false,
        isCompleted: false,
      );

      await _triggerTtsNotification(tempTask, contextData);
      
      developer.log('[ContextDetectionService] Geofence context handled for task: $taskName');
    } catch (e) {
      developer.log('[ContextDetectionService] Error handling geofence context: $e');
    }
  }

  // Getters and setters for configuration
  bool get isEnabled => _isEnabled;
  bool get locationContextEnabled => _locationContextEnabled;
  bool get timeContextEnabled => _timeContextEnabled;
  bool get batteryContextEnabled => _batteryContextEnabled;
  bool get connectivityContextEnabled => _connectivityContextEnabled;
  int get batteryThreshold => _batteryThreshold;
  Duration get timeContextWindow => _timeContextWindow;

  /// Stream of context events
  Stream<ContextData> get contextStream => _contextStreamController.stream;

  /// Enable or disable context detection
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    if (_isEnabled) {
      _startContextMonitoring();
    } else {
      _stopContextMonitoring();
    }
    await _saveSettings();
    developer.log('[ContextDetectionService] Context detection enabled: $_isEnabled');
  }

  /// Enable or disable location context
  Future<void> setLocationContextEnabled(bool enabled) async {
    _locationContextEnabled = enabled;
    await _saveSettings();
    developer.log('[ContextDetectionService] Location context enabled: $_locationContextEnabled');
  }

  /// Enable or disable time context
  Future<void> setTimeContextEnabled(bool enabled) async {
    _timeContextEnabled = enabled;
    await _saveSettings();
    developer.log('[ContextDetectionService] Time context enabled: $_timeContextEnabled');
  }

  /// Enable or disable battery context
  Future<void> setBatteryContextEnabled(bool enabled) async {
    _batteryContextEnabled = enabled;
    await _saveSettings();
    developer.log('[ContextDetectionService] Battery context enabled: $_batteryContextEnabled');
  }

  /// Enable or disable connectivity context
  Future<void> setConnectivityContextEnabled(bool enabled) async {
    _connectivityContextEnabled = enabled;
    await _saveSettings();
    developer.log('[ContextDetectionService] Connectivity context enabled: $_connectivityContextEnabled');
  }

  /// Set battery threshold
  Future<void> setBatteryThreshold(int threshold) async {
    if (threshold < 0 || threshold > 100) return;
    
    _batteryThreshold = threshold;
    await _saveSettings();
    developer.log('[ContextDetectionService] Battery threshold set to: $_batteryThreshold%');
  }

  /// Set time context window
  Future<void> setTimeContextWindow(Duration window) async {
    _timeContextWindow = window;
    await _saveSettings();
    developer.log('[ContextDetectionService] Time context window set to: ${_timeContextWindow.inMinutes} minutes');
  }

  /// Dispose of resources
  void dispose() {
    _stopContextMonitoring();
    _contextStreamController.close();
    _ttsService.dispose();
    developer.log('[ContextDetectionService] Service disposed');
  }
}