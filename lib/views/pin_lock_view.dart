import 'package:flutter/material.dart';
import 'package:intelliboro/services/pin_service.dart';
import 'dart:async';

/// Simple lock screen that asks for a 6-digit PIN before allowing access.
class PinLockView extends StatefulWidget {
  final VoidCallback onUnlocked;
  const PinLockView({super.key, required this.onUnlocked});

  @override
  State<PinLockView> createState() => _PinLockViewState();
}

class _PinLockViewState extends State<PinLockView> {
  final _pinCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
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
        _error = _formatLockoutMsg(remain);
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
          _error = _formatLockoutMsg(remain);
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
    if (!_formKey.currentState!.validate()) return;
    if (_verifying) return;
    setState(() => _verifying = true);
    try {
      final ok = await PinService().verifyPin(_pinCtrl.text);
      if (!mounted) return;
      if (ok) {
        widget.onUnlocked();
      } else {
        await _checkLockout();
        if (!_lockedOut) {
          setState(() {
            _error = 'Incorrect PIN. Please try again.';
          });
        }
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
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
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Unlock with your 6-digit PIN',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      counterText: '',
                    ),
                    validator: (v) {
                      if (_lockedOut) {
                        return _error ?? 'Locked out temporarily. Please wait.';
                      }
                      if (v == null || v.isEmpty) return 'Enter your PIN';
                      if (!RegExp(r'^\d{6}$').hasMatch(v)) {
                        return 'PIN must be exactly 6 digits';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _verify(),
                  ),
                  const SizedBox(height: 8),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: (_verifying || _lockedOut) ? null : _verify,
                    icon: const Icon(Icons.arrow_forward),
                    label: _verifying
                        ? const Text('Verifying...')
                        : (_lockedOut ? const Text('Locked') : const Text('Unlock')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}