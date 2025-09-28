import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for handling text-to-speech notifications for context-aware tasks
class TextToSpeechService {
  static final TextToSpeechService _instance = TextToSpeechService._internal();
  factory TextToSpeechService() => _instance;
  TextToSpeechService._internal();

  FlutterTts? _flutterTts;
  bool _isInitialized = false;
  bool _isSpeaking = false;

  // Default settings
  double _speechRate = 0.5;
  double _volume = 0.8;
  double _pitch = 1.0;
  String _language = 'en-US';
  bool _isEnabled = true;

  // Keys for SharedPreferences
  static const String _enabledKey = 'tts_enabled';
  static const String _speechRateKey = 'tts_speech_rate';
  static const String _volumeKey = 'tts_volume';
  static const String _pitchKey = 'tts_pitch';
  static const String _languageKey = 'tts_language';

  /// Initialize the TTS service
  Future<void> init() async {
    if (_isInitialized) {
      developer.log('[TextToSpeechService] Already initialized - skipping');
      return;
    }

    try {
      developer.log('[TextToSpeechService] Starting initialization...');
      _flutterTts = FlutterTts();

      // Load settings from SharedPreferences
      await _loadSettings();

      // Configure TTS
      await _configureTts();

      _isInitialized = true;
      developer.log('[TextToSpeechService] Successfully initialized');
    } catch (e, stackTrace) {
      developer.log(
        '[TextToSpeechService] Error during initialization: $e',
        error: e,
        stackTrace: stackTrace,
      );
      // Reset state on failure
      _isInitialized = false;
      _flutterTts = null;
      rethrow;
    }
  }

  /// Configure the TTS engine with current settings
  Future<void> _configureTts() async {
    if (_flutterTts == null) return;

    try {
      await _flutterTts!.setLanguage(_language);
      await _flutterTts!.setSpeechRate(_speechRate);
      await _flutterTts!.setVolume(_volume);
      await _flutterTts!.setPitch(_pitch);

      // Set up completion handler
      _flutterTts!.setCompletionHandler(() {
        _isSpeaking = false;
        developer.log('[TextToSpeechService] Speech completed');
      });

      // Set up error handler
      _flutterTts!.setErrorHandler((msg) {
        _isSpeaking = false;
        developer.log('[TextToSpeechService] TTS Error: $msg');
      });

      developer.log('[TextToSpeechService] TTS configured successfully');
    } catch (e) {
      developer.log('[TextToSpeechService] Error configuring TTS: $e');
    }
  }

  /// Load settings from SharedPreferences
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _isEnabled = prefs.getBool(_enabledKey) ?? true;
      _speechRate = prefs.getDouble(_speechRateKey) ?? 0.5;
      _volume = prefs.getDouble(_volumeKey) ?? 0.8;
      _pitch = prefs.getDouble(_pitchKey) ?? 1.0;
      _language = prefs.getString(_languageKey) ?? 'en-US';

      developer.log(
        '[TextToSpeechService] Settings loaded: enabled=$_isEnabled, rate=$_speechRate, volume=$_volume, pitch=$_pitch, language=$_language',
      );
    } catch (e) {
      developer.log('[TextToSpeechService] Error loading settings: $e');
    }
  }

  /// Save settings to SharedPreferences
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(_enabledKey, _isEnabled);
      await prefs.setDouble(_speechRateKey, _speechRate);
      await prefs.setDouble(_volumeKey, _volume);
      await prefs.setDouble(_pitchKey, _pitch);
      await prefs.setString(_languageKey, _language);

      developer.log('[TextToSpeechService] Settings saved');
    } catch (e) {
      developer.log('[TextToSpeechService] Error saving settings: $e');
    }
  }

  /// Speak the given text for a task notification
  Future<void> speakTaskNotification(String taskName, String context) async {
    if (!_isEnabled || !_isInitialized || _flutterTts == null) {
      developer.log('[TextToSpeechService] TTS not available or disabled');
      return;
    }

    try {
      // Stop any current speech
      if (_isSpeaking) {
        await stop();
      }

      // Create the notification text
      String notificationText = _createNotificationText(taskName, context);

      developer.log('[TextToSpeechService] Speaking: $notificationText');

      _isSpeaking = true;
      await _flutterTts!.speak(notificationText);
    } catch (e, stackTrace) {
      developer.log(
        '[TextToSpeechService] Error speaking notification: $e',
        error: e,
        stackTrace: stackTrace,
      );
      _isSpeaking = false;
    }
  }

  // Getters and setters for configuration
  bool get isEnabled => _isEnabled;
  bool get isSpeaking => _isSpeaking;
  double get speechRate => _speechRate;
  double get volume => _volume;
  double get pitch => _pitch;
  String get language => _language;

  /// Create a natural-sounding notification text
  String _createNotificationText(String taskName, String context) {
    // Clean up the task name
    String cleanTaskName = taskName.trim();

    // Create contextual messages based on the type of context
    switch (context.toLowerCase()) {
      case 'location':
      case 'geofence':
        return "You have task: $cleanTaskName";
      case 'time':
        return "Time reminder: $cleanTaskName";
      case 'urgent':
        return "Urgent task: $cleanTaskName";
      default:
        return "You have task: $cleanTaskName";
    }
  }

  /// Stop current speech
  Future<void> stop() async {
    if (_flutterTts != null && _isSpeaking) {
      try {
        await _flutterTts!.stop();
        _isSpeaking = false;
        developer.log('[TextToSpeechService] Speech stopped');
      } catch (e) {
        developer.log('[TextToSpeechService] Error stopping speech: $e');
      }
    }
  }

  /// Pause current speech
  Future<void> pause() async {
    if (_flutterTts != null && _isSpeaking) {
      try {
        await _flutterTts!.pause();
        developer.log('[TextToSpeechService] Speech paused');
      } catch (e) {
        developer.log('[TextToSpeechService] Error pausing speech: $e');
      }
    }
  }

  /// Get available languages
  Future<List<String>> getLanguages() async {
    if (_flutterTts == null) return [];

    try {
      final languages = await _flutterTts!.getLanguages;
      return List<String>.from(languages);
    } catch (e) {
      developer.log('[TextToSpeechService] Error getting languages: $e');
      return [];
    }
  }

  /// Check if TTS is available on the device
  Future<bool> isAvailable() async {
    if (_flutterTts == null) return false;

    try {
      final languages = await _flutterTts!.getLanguages;
      return languages.isNotEmpty;
    } catch (e) {
      developer.log('[TextToSpeechService] TTS not available: $e');
      return false;
    }
  }

  /// Enable or disable TTS
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    await _saveSettings();
    developer.log('[TextToSpeechService] TTS enabled: $_isEnabled');
  }

  /// Set speech rate (0.0 - 1.0)
  Future<void> setSpeechRate(double rate) async {
    if (rate < 0.0 || rate > 1.0) return;

    _speechRate = rate;
    if (_flutterTts != null) {
      await _flutterTts!.setSpeechRate(_speechRate);
    }
    await _saveSettings();
    developer.log('[TextToSpeechService] Speech rate set to: $_speechRate');
  }

  /// Set volume (0.0 - 1.0)
  Future<void> setVolume(double volume) async {
    if (volume < 0.0 || volume > 1.0) return;

    _volume = volume;
    if (_flutterTts != null) {
      await _flutterTts!.setVolume(_volume);
    }
    await _saveSettings();
    developer.log('[TextToSpeechService] Volume set to: $_volume');
  }

  /// Set pitch (0.5 - 2.0)
  Future<void> setPitch(double pitch) async {
    if (pitch < 0.5 || pitch > 2.0) return;

    _pitch = pitch;
    if (_flutterTts != null) {
      await _flutterTts!.setPitch(_pitch);
    }
    await _saveSettings();
    developer.log('[TextToSpeechService] Pitch set to: $_pitch');
  }

  /// Set language
  Future<void> setLanguage(String language) async {
    _language = language;
    if (_flutterTts != null) {
      await _flutterTts!.setLanguage(_language);
    }
    await _saveSettings();
    developer.log('[TextToSpeechService] Language set to: $_language');
  }

  /// Test TTS with a sample message
  Future<void> testSpeech() async {
    await speakTaskNotification("Write email", "location");
  }

  /// Dispose of resources
  void dispose() {
    _flutterTts?.stop();
    _flutterTts = null;
    _isInitialized = false;
    _isSpeaking = false;
    developer.log('[TextToSpeechService] Service disposed');
  }
}