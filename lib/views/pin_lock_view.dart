import 'package:flutter/material.dart';
import 'package:intelliboro/services/pin_service.dart';
import 'package:intelliboro/widgets/numeric_keypad.dart';
import 'package:intelliboro/widgets/pin_display.dart';
import 'dart:async';

/// Simple lock screen that asks for a 6-digit PIN before allowing access.
class PinLockView extends StatefulWidget {
  final VoidCallback onUnlocked;
  const PinLockView({super.key, required this.onUnlocked});

  @override
  State<PinLockView> createState() => _PinLockViewState();
}

class _PinLockViewState extends State<PinLockView> {
  String _enteredPin = '';
  final _maxPinLength = 6;
  String? _error;
  bool _verifying = false;
  bool _lockedOut = false;
  Duration _remaining = Duration.zero;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _checkLockout();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _checkLockout() async {
    final svc = PinService();
    final locked = await svc.isLockedOut();
    if (!mounted) return;
    if (locked) {
      final remain = await svc.lockoutRemaining();
      setState(() {
        _lockedOut = true;
        _remaining = remain;
        _error =
            null; // Clear error when locked out, use dedicated lockout display
      });
      _startTicker();
    } else {
      setState(() {
        _lockedOut = false;
        _remaining = Duration.zero;
      });
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final remain = await PinService().lockoutRemaining();
      if (!mounted) return;
      if (remain <= Duration.zero) {
        _ticker?.cancel();
        setState(() {
          _lockedOut = false;
          _remaining = Duration.zero;
          _error = null;
        });
      } else {
        setState(() {
          _remaining = remain;
          // Don't set _error here, use dedicated lockout display
        });
      }
    });
  }

  String _formatLockoutMsg(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return 'Too many incorrect attempts. Try again in $mm:$ss';
  }

  Future<void> _verify() async {
    setState(() => _error = null);
    await _checkLockout();
    if (_lockedOut) return;

    // Validate PIN length
    if (_enteredPin.length != _maxPinLength) {
      setState(() => _error = 'PIN must be exactly 6 digits');
      return;
    }

    if (_verifying) return;
    setState(() => _verifying = true);
    try {
      final ok = await PinService().verifyPin(_enteredPin);
      if (!mounted) return;
      if (ok) {
        widget.onUnlocked();
      } else {
        await _checkLockout();
        if (!_lockedOut) {
          setState(() {
            _error = 'Incorrect PIN. Please try again.';
            _enteredPin = ''; // Clear the entered PIN on error
          });
        }
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _onNumberTap(String number) {
    if (_lockedOut || _verifying) return;

    if (_enteredPin.length < _maxPinLength) {
      setState(() {
        _enteredPin += number;
        _error = null; // Clear any previous error
      });

      // Auto-verify when PIN is complete
      if (_enteredPin.length == _maxPinLength) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _verify();
        });
      }
    }
  }

  void _onBackspace() {
    if (_lockedOut || _verifying) return;

    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _error = null; // Clear any previous error
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Enter PIN')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Unlock with your 6-digit PIN',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // PIN Display with dots
                PinDisplay(pin: _enteredPin, maxLength: _maxPinLength),

                const SizedBox(height: 24),

                // Error message
                if (_error != null && !_lockedOut)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Lockout message
                if (_lockedOut)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      _formatLockoutMsg(_remaining),
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 32),

                // Custom Numeric Keypad
                NumericKeypad(
                  onNumberTap: _onNumberTap,
                  onBackspace: _onBackspace,
                  showBackspace: true,
                ),

                const SizedBox(height: 24),

                // Status indicator
                if (_verifying)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}