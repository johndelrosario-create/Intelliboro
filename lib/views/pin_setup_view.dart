import 'package:flutter/material.dart';
import 'package:intelliboro/services/pin_service.dart';

/// First-launch optional PIN setup. Prompts the user if they want to enable a 6-digit PIN.
/// If yes, asks to enter and confirm the PIN and saves it securely.
class PinSetupView extends StatefulWidget {
  final VoidCallback onCompleted;
  const PinSetupView({super.key, required this.onCompleted});

  @override
  State<PinSetupView> createState() => _PinSetupViewState();
}

class _PinSetupViewState extends State<PinSetupView> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
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
      builder: (ctx) => AlertDialog(
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
    if (!_formKey.currentState!.validate()) return;
    try {
      await PinService().setPin(_pinCtrl.text);
      await PinService().setPromptAnswered();
      if (!mounted) return;
      widget.onCompleted();
    } catch (e) {
      setState(() => _error = 'Failed to save PIN: $e');
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
            child: _enabling
                ? Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Create a 6-digit PIN',
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
                            labelText: 'Enter PIN',
                            counterText: '',
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Enter a PIN';
                            if (!RegExp(r'^\d{6}$').hasMatch(v)) {
                              return 'PIN must be exactly 6 digits';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _confirmCtrl,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'Confirm PIN',
                            counterText: '',
                          ),
                          validator: (v) {
                            if (v != _pinCtrl.text) return 'PINs do not match';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(_error!, style: const TextStyle(color: Colors.red)),
                          ),
                        FilledButton.icon(
                          onPressed: _savePin,
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('Save PIN'),
                        ),
                      ],
                    ),
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