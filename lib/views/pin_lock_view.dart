import 'package:flutter/material.dart';
import 'package:intelliboro/services/pin_service.dart';

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
  int _attempts = 0;
  static const int _maxAttempts = 8;
  bool _verifying = false;

  Future<void> _verify() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_verifying) return;
    setState(() => _verifying = true);
    try {
      final ok = await PinService().verifyPin(_pinCtrl.text);
      if (!mounted) return;
      if (ok) {
        widget.onUnlocked();
      } else {
        setState(() {
          _attempts += 1;
          _error = 'Incorrect PIN. Attempts: $_attempts/$_maxAttempts';
        });
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
                      if (v == null || v.isEmpty) return 'Enter your PIN';
                      if (!RegExp(r'^\d{6}$').hasMatch(v)) {
                        return 'PIN must be exactly 6 digits';
                      }
                      if (_attempts >= _maxAttempts) {
                        return 'Too many attempts. Please wait a bit and try again.';
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
                    onPressed: _verifying ? null : _verify,
                    icon: const Icon(Icons.arrow_forward),
                    label: _verifying ? const Text('Verifying...') : const Text('Unlock'),
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