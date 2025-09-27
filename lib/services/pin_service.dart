import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for securely storing and validating an optional 6-digit PIN.
/// - Uses SharedPreferences to store flags (enabled, prompt answered)
/// - Uses FlutterSecureStorage to store the salted hash of the PIN and the salt
class PinService {
  static const _prefsKeyEnabled = 'pin_enabled';
  static const _prefsKeyPromptAnswered = 'pin_prompt_answered';
  static const _secureKeyPinHash = 'pin_hash';
  static const _secureKeyPinSalt = 'pin_salt';

  static final PinService _instance = PinService._internal();
  factory PinService() => _instance;
  PinService._internal();

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  Future<bool> isPinEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyEnabled) ?? false;
    }

  Future<void> setPromptAnswered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyPromptAnswered, true);
  }

  Future<bool> isPromptAnswered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyPromptAnswered) ?? false;
  }

  Future<void> disablePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, false);
    // Do not erase hash by default to allow re-enable with same PIN if desired.
  }

  /// Sets a new 6-digit PIN. Overwrites any existing one.
  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('PIN must be exactly 6 digits');
    }
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);
    await _secure.write(key: _secureKeyPinHash, value: hash);
    await _secure.write(key: _secureKeyPinSalt, value: salt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, true);
  }

  Future<bool> verifyPin(String pin) async {
    try {
      final salt = await _secure.read(key: _secureKeyPinSalt);
      final storedHash = await _secure.read(key: _secureKeyPinHash);
      if (salt == null || storedHash == null) return false;
      final incoming = _hashPin(pin, salt);
      return _constantTimeEquals(storedHash, incoming);
    } catch (e) {
      if (kDebugMode) {
        print('[PinService] verifyPin error: $e');
      }
      return false;
    }
  }

  String _generateSalt({int length = 16}) {
    // Simple salt using current time bytes; for app-local PIN this is sufficient.
    final millis = DateTime.now().millisecondsSinceEpoch;
    final bytes = utf8.encode('$millis:${UniqueKey()}');
    return base64Url.encode(sha256.convert(bytes).bytes).substring(0, length);
  }

  String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
