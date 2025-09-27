import 'package:shared_preferences/shared_preferences.dart';

/// Manages app-wide default notification sound preferences for Android.
class NotificationPreferencesService {
  static const _keyDefaultSound = 'default_notification_sound';

  // Built-in system notification sounds
  static const String soundDefault = 'default';
  static const String soundSilent = 'silent';
  static const String soundAlarm = 'alarm';
  static const String soundRingtone = 'ringtone';
  static const String soundNotification = 'notification';
  static const String soundAlert = 'alert';
  static const String soundChime = 'chime';
  static const String soundBell = 'bell';
  static const String soundTone = 'tone';
  static const String soundBeep = 'beep';

  /// Get all available notification sound options with user-friendly names
  static List<Map<String, String>> getAvailableSounds() {
    return [
      {'key': soundDefault, 'name': 'System Default'},
      {'key': soundChime, 'name': 'Chime'},
      {'key': soundBell, 'name': 'Bell'},
      {'key': soundTone, 'name': 'Tone'},
      {'key': soundBeep, 'name': 'Beep'},
    ];
  }

  /// Get user-friendly name for a sound key
  static String getSoundName(String soundKey) {
    final sounds = getAvailableSounds();
    final sound = sounds.firstWhere(
      (s) => s['key'] == soundKey,
      orElse: () => {'key': soundDefault, 'name': 'System Default'},
    );
    return sound['name']!;
  }

  static final NotificationPreferencesService _instance =
      NotificationPreferencesService._internal();
  factory NotificationPreferencesService() => _instance;
  NotificationPreferencesService._internal();

  Future<String> getDefaultSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDefaultSound) ?? soundDefault;
  }

  Future<void> setDefaultSound(String soundKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultSound, soundKey);
  }
}