import 'package:flutter/material.dart';
import 'package:intelliboro/services/pin_service.dart';
import 'package:intelliboro/widgets/numeric_keypad.dart';
import 'package:intelliboro/widgets/pin_display.dart';

/// First-launch optional PIN setup. Prompts the user if they want to enable a 6-digit PIN.
/// If yes, asks to enter and confirm the PIN and saves it securely.
class PinSetupView extends StatefulWidget {
  final VoidCallback onCompleted;
  const PinSetupView({super.key, required this.onCompleted});

  @override
  State<PinSetupView> createState() => _PinSetupViewState();
}

class _PinSetupViewState extends State<PinSetupView> {
  String _enteredPin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  final _maxPinLength = 6;
  bool _asked = false;
  bool _enabling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Ask the enable dialog once the first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) => _askEnable());
  }

  Future<void> _askEnable() async {
    if (_asked) return;
    _asked = true;
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Enable PIN protection?'),
            content: const Text(
              'Would you like to set up a 6-digit PIN to protect the app? You can change this later in settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Enable'),
              ),
            ],
          ),
    );
    if (!mounted) return;
    if (res == true) {
      setState(() => _enabling = true);
    } else {
      await PinService().setPromptAnswered();
      if (!mounted) return;
      widget.onCompleted();
    }
  }

  Future<void> _savePin() async {
    setState(() => _error = null);

    // Validate PIN
    if (_enteredPin.length != _maxPinLength) {
      setState(() => _error = 'PIN must be exactly 6 digits');
      return;
    }

    if (_confirmPin.length != _maxPinLength) {
      setState(() => _error = 'Please confirm your PIN');
      return;
    }

    if (_enteredPin != _confirmPin) {
      setState(() => _error = 'PINs do not match');
      return;
    }

    try {
      await PinService().setPin(_enteredPin);
      await PinService().setPromptAnswered();
      if (!mounted) return;
      widget.onCompleted();
    } catch (e) {
      setState(() => _error = 'Failed to save PIN: $e');
    }
  }

  void _onNumberTap(String number) {
    if (!_isConfirming) {
      // Setting initial PIN
      if (_enteredPin.length < _maxPinLength) {
        setState(() {
          _enteredPin += number;
          _error = null;
        });

        // Move to confirmation when PIN is complete
        if (_enteredPin.length == _maxPinLength) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              setState(() => _isConfirming = true);
            }
          });
        }
      }
    } else {
      // Confirming PIN
      if (_confirmPin.length < _maxPinLength) {
        setState(() {
          _confirmPin += number;
          _error = null;
        });

        // Auto-save when confirmation is complete
        if (_confirmPin.length == _maxPinLength) {
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) _savePin();
          });
        }
      }
    }
  }

  void _onBackspace() {
    if (!_isConfirming) {
      // Editing initial PIN
      if (_enteredPin.isNotEmpty) {
        setState(() {
          _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
          _error = null;
        });
      }
    } else {
      // Editing confirmation PIN
      if (_confirmPin.isNotEmpty) {
        setState(() {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
          _error = null;
        });
      } else {
        // If confirmation is empty, go back to editing initial PIN
        setState(() => _isConfirming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Set up PIN')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                _enabling
                    ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _isConfirming
                              ? 'Confirm your PIN'
                              : 'Create a 6-digit PIN',
                          style: theme.textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // PIN Display with dots
                        PinDisplay(
                          pin: _isConfirming ? _confirmPin : _enteredPin,
                          maxLength: _maxPinLength,
                        ),

                        const SizedBox(height: 24),

                        // Step indicator
                        Text(
                          _isConfirming ? 'Step 2 of 2' : 'Step 1 of 2',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 16),

                        // Error message
                        if (_error != null)
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

                        const SizedBox(height: 32),

                        // Custom Numeric Keypad
                        NumericKeypad(
                          onNumberTap: _onNumberTap,
                          onBackspace: _onBackspace,
                          showBackspace: true,
                        ),

                        const SizedBox(height: 24),

                        // Manual save button (optional, for user control)
                        if (_isConfirming &&
                            _confirmPin.length == _maxPinLength)
                          FilledButton.icon(
                            onPressed: _savePin,
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Save PIN'),
                          ),
                      ],
                    )
                    : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Preparing PIN setup...'),
                      ],
                    ),
          ),
        ),
      ),
    );
  }
}