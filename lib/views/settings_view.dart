import 'package:flutter/material.dart';
import 'package:intelliboro/services/pin_service.dart';
import 'package:intelliboro/services/offline_map_service.dart';
import 'package:intelliboro/services/geofence_storage.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _loading = true;
  bool _pinEnabled = false;
  String? _status;
  bool _offlineBusy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await PinService().isPinEnabled();
    if (!mounted) return;
    setState(() {
      _pinEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _enablePin() async {
    final res = await showDialog<_PinPairResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _NewPinDialog(),
    );
    if (res == null) return;
    try {
      await PinService().setPin(res.newPin);
      await PinService().setPromptAnswered();
      setState(() {
        _pinEnabled = true;
        _status = 'PIN enabled';
      });
    } catch (e) {
      setState(() => _status = 'Failed to enable PIN: $e');
    }
  }

  Future<void> _disablePin() async {
    final current = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _CurrentPinDialog(title: 'Disable PIN'),
    );
    if (current == null) return;
    final ok = await PinService().verifyPin(current);
    if (!ok) {
      setState(() => _status = 'Incorrect current PIN');
      return;
    }
    await PinService().disablePin();
    setState(() {
      _pinEnabled = false;
      _status = 'PIN disabled';
    });
  }

  Future<void> _changePin() async {
    final res = await showDialog<_PinChangeResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ChangePinDialog(),
    );
    if (res == null) return;
    final ok = await PinService().verifyPin(res.currentPin);
    if (!ok) {
      setState(() => _status = 'Incorrect current PIN');
      return;
    }
    try {
      await PinService().setPin(res.newPin);
      setState(() => _status = 'PIN changed');
    } catch (e) {
      setState(() => _status = 'Failed to change PIN: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            value: _pinEnabled,
            title: const Text('PIN Protection'),
            subtitle: Text(_pinEnabled ? 'Enabled' : 'Disabled'),
            onChanged: (v) async {
              if (v) {
                await _enablePin();
              } else {
                await _disablePin();
              }
            },
          ),
          ListTile(
            enabled: _pinEnabled,
            leading: const Icon(Icons.lock_reset),
            title: const Text('Change PIN'),
            subtitle: const Text('Requires current PIN'),
            onTap: _pinEnabled ? _changePin : null,
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Offline Maps'),
            subtitle: const Text('Download tiles for offline use (Mapbox)'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _offlineBusy
                      ? null
                      : () async {
                          setState(() {
                            _offlineBusy = true;
                            _status = 'Initializing offline service...';
                          });
                          try {
                            await OfflineMapService().init(styleUri: 'mapbox://styles/mapbox/streets-v12');
                            await OfflineMapService().ensureHomeRegion();
                            setState(() => _status = 'Home region (25km, z8-16) queued.');
                          } catch (e) {
                            setState(() => _status = 'Offline init/download failed: $e');
                          } finally {
                            setState(() => _offlineBusy = false);
                          }
                        },
                  icon: const Icon(Icons.home_work_outlined),
                  label: const Text('Download Home Region (25 km)'),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _offlineBusy
                      ? null
                      : () async {
                          setState(() {
                            _offlineBusy = true;
                            _status = 'Queuing geofence regions...';
                          });
                          try {
                            await OfflineMapService().init(styleUri: 'mapbox://styles/mapbox/streets-v12');
                            final gfs = await GeofenceStorage().loadGeofences();
                            for (final g in gfs) {
                              await OfflineMapService().ensureRegionForGeofence(g);
                            }
                            setState(() => _status = 'Queued ${gfs.length} geofence regions (3km, z10-17).');
                          } catch (e) {
                            setState(() => _status = 'Failed to queue geofence regions: $e');
                          } finally {
                            setState(() => _offlineBusy = false);
                          }
                        },
                  icon: const Icon(Icons.where_to_vote_outlined),
                  label: const Text('Download Regions for All Geofences'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _offlineBusy
                      ? null
                      : () async {
                          setState(() {
                            _offlineBusy = true;
                            _status = 'Clearing offline data...';
                          });
                          try {
                            await OfflineMapService().clearAll();
                            setState(() => _status = 'Requested offline data clear.');
                          } catch (e) {
                            setState(() => _status = 'Failed to clear offline data: $e');
                          } finally {
                            setState(() => _offlineBusy = false);
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear Offline Data'),
                ),
              ],
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _status!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PinPairResult {
  final String newPin;
  const _PinPairResult(this.newPin);
}

class _PinChangeResult {
  final String currentPin;
  final String newPin;
  const _PinChangeResult(this.currentPin, this.newPin);
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog();

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enable PIN'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'New PIN',
                counterText: '',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter a PIN';
                if (!RegExp(r'^\d{6}$').hasMatch(v)) return 'Must be 6 digits';
                return null;
              },
            ),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
                counterText: '',
              ),
              validator: (v) => v == _pinCtrl.text ? null : 'PINs do not match',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_PinPairResult(_pinCtrl.text));
            }
          },
          child: const Text('Enable'),
        ),
      ],
    );
  }
}

class _CurrentPinDialog extends StatefulWidget {
  final String title;
  const _CurrentPinDialog({required this.title});

  @override
  State<_CurrentPinDialog> createState() => _CurrentPinDialogState();
}

class _CurrentPinDialogState extends State<_CurrentPinDialog> {
  final _pinCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _pinCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Current PIN',
            counterText: '',
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter PIN';
            if (!RegExp(r'^\d{6}$').hasMatch(v)) return 'Must be 6 digits';
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Confirm'),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_pinCtrl.text);
    }
  }
}

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog();

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _currentCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change PIN'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _currentCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Current PIN',
                counterText: '',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter current PIN';
                if (!RegExp(r'^\d{6}$').hasMatch(v)) return 'Must be 6 digits';
                return null;
              },
            ),
            TextFormField(
              controller: _pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'New PIN',
                counterText: '',
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter new PIN';
                if (!RegExp(r'^\d{6}$').hasMatch(v)) return 'Must be 6 digits';
                return null;
              },
            ),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Confirm new PIN',
                counterText: '',
              ),
              validator: (v) => v == _pinCtrl.text ? null : 'PINs do not match',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(
                _PinChangeResult(_currentCtrl.text, _pinCtrl.text),
              );
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}