import 'package:flutter/material.dart';
import 'package:intelliboro/services/pin_service.dart';
import 'package:intelliboro/services/offline_map_service.dart';
import 'package:intelliboro/services/backup_service.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:intelliboro/models/download_progress.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intelliboro/services/notification_service.dart'
    show notificationPlugin;
import 'package:intelliboro/views/tts_settings_view.dart';
import 'package:intelliboro/widgets/numeric_keypad.dart';
import 'package:intelliboro/widgets/pin_display.dart';
import 'package:intelliboro/widgets/offline_queue_status.dart';

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
  bool _backupBusy = false;

  // Download progress tracking
  StreamSubscription<DownloadProgress>? _progressSubscription;
  DownloadProgress? _currentProgress;

  // Downloaded regions tracking
  bool _homeRegionDownloaded = false;
  bool _hasOfflineData = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _setupProgressListener();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  void _setupProgressListener() {
    _progressSubscription = OfflineMapService().progressStream.listen((
      progress,
    ) {
      if (mounted) {
        setState(() {
          _currentProgress = progress;
          if (progress.isCompleted ||
              progress.isCancelled ||
              progress.error != null) {
            _offlineBusy = false;
          }
        });

        // Refresh download status when a download completes successfully
        if (progress.isCompleted) {
          _checkDownloadStatus();
        }
      }
    });
  }

  Widget _buildProgressDisplay() {
    // Show download progress if there's active progress
    if (_currentProgress != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _currentProgress!.isCompleted
                          ? Icons.check_circle
                          : _currentProgress!.isCancelled
                          ? Icons.cancel
                          : _currentProgress!.error != null
                          ? Icons.error
                          : Icons.downloading,
                      color:
                          _currentProgress!.isCompleted
                              ? Colors.green
                              : _currentProgress!.isCancelled
                              ? Colors.orange
                              : _currentProgress!.error != null
                              ? Colors.red
                              : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentProgress!.phase,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (_offlineBusy &&
                        !_currentProgress!.isCompleted &&
                        !_currentProgress!.isCancelled)
                      TextButton(
                        onPressed: () {
                          OfflineMapService().cancelDownload();
                        },
                        child: const Text('Cancel'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_currentProgress!.totalTiles > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: _currentProgress!.progress,
                        backgroundColor: Colors.grey[300],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_currentProgress!.progressPercentage} (${_currentProgress!.downloadedTiles}/${_currentProgress!.totalTiles} tiles)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (_currentProgress!.downloadSpeedText != null)
                            Text(
                              _currentProgress!.downloadSpeedText!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                      if (_currentProgress!.estimatedTimeRemainingText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _currentProgress!.estimatedTimeRemainingText!,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (_currentProgress!.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Error: ${_currentProgress!.error}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Show simple status message if no progress but there's a status
    if (_status != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          _status!,
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _checkDownloadStatus() async {
    try {
      final downloadedRegions =
          await OfflineMapService().getDownloadedRegions();

      // Check if there's any offline data
      final hasData = downloadedRegions.isNotEmpty;

      // Check if home region is downloaded
      final homeDownloaded = downloadedRegions.contains('home_region');

      if (mounted) {
        setState(() {
          _hasOfflineData = hasData;
          _homeRegionDownloaded = homeDownloaded;
        });
      }
    } catch (e) {
      // If there's an error checking download status, assume nothing is downloaded
      if (mounted) {
        setState(() {
          _hasOfflineData = false;
          _homeRegionDownloaded = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    final enabled = await PinService().isPinEnabled();
    await _checkDownloadStatus();

    // Additional refresh after import: ensure all app components are notified
    try {
      // This triggers a broader refresh of task-related data
      final taskTimerService = TaskTimerService();
      taskTimerService.tasksChanged.value = true;
    } catch (e) {
      developer.log('[Settings] Warning: Could not trigger task refresh: $e');
    }

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
      if (!mounted) return;
      setState(() {
        _pinEnabled = true;
        _status = 'PIN enabled';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Failed to enable PIN: $e');
    }
  }

  // Add test notification and platform status call
  Future<void> _sendTestNotification() async {
    // Send an immediate test notification
    try {
      await notificationPlugin.show(
        999999,
        'Test Notification',
        'This is a test from IntelliBoro',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_alarms',
            'Task Alarms',
            channelDescription: 'Time-based task alarms',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post test notification: $e')),
        );
      }
      return;
    }

    if (!Platform.isAndroid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Test notification sent (non-Android status not available)',
            ),
          ),
        );
      }
      return;
    }

    // Query platform for notification status
    try {
      const platform = MethodChannel('exact_alarms');
      final Map<dynamic, dynamic> status = await platform.invokeMethod(
        'notification_status',
      );
      final bool enabled = status['enabled'] as bool? ?? false;
      final int importance = status['channelImportance'] as int? ?? -1;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Notifications enabled: $enabled, channel importance: $importance',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (e is MissingPluginException) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Platform plugin not available yet. Please fully stop the app and rebuild (flutter run) to apply native changes.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to query notification status: $e')),
          );
        }
      }
    }
  }

  Future<void> _scheduleTestSystemAlarm() async {
    if (!Platform.isAndroid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('System alarms are Android-only')),
        );
      }
      return;
    }
    try {
      final now = DateTime.now();
      final trigger = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      ).add(const Duration(minutes: 1));
      final platform = const MethodChannel('exact_alarms');
      final args = {
        'id': 123456,
        'triggerAtMillis': trigger.millisecondsSinceEpoch,
        'title': 'Test System Alarm',
        'body': 'This is a 1-minute test system alarm',
      };
      await platform.invokeMethod('scheduleAlarm', args);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scheduled system alarm in ~1 minute (id=123456)'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to schedule system alarm: $e')),
        );
      }
    }
  }

  /// Run a quick diagnostics flow for alarms/notifications.
  Future<void> _runAlarmDiagnostics() async {
    // Ensure timezone data is available for plugin scheduling
    try {
      tzdata.initializeTimeZones();
      final locName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(locName));
    } catch (_) {}

    // 1) Query platform exact alarm capability and notification channel status
    String msg = '';
    try {
      final platform = const MethodChannel('exact_alarms');
      final bool canSchedule = await platform.invokeMethod(
        'canScheduleExactAlarms',
      );
      msg += 'Exact alarms allowed: $canSchedule\n';
      final Map status = await platform.invokeMethod('notification_status');
      msg +=
          'Notifications enabled: ${status['enabled']}, channelImportance: ${status['channelImportance']}\n';
    } catch (e) {
      msg += 'Platform query failed: $e\n';
    }

    // 2) Post a short-lived plugin notification in ~15s and schedule system alarm in ~30s
    try {
      final now = tz.TZDateTime.now(tz.local);
      final pluginTime = now.add(const Duration(seconds: 15));
      final systemTime = DateTime.now().add(const Duration(seconds: 30));

      await notificationPlugin.zonedSchedule(
        999997,
        'Diag: Plugin Notification',
        'Plugin alarm scheduled for diagnostics',
        pluginTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_alarms',
            'Task Alarms',
            channelDescription: 'Time-based task alarms',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'diag_plugin',
      );
      msg += 'Plugin notification scheduled in ~15s\n';

      // Schedule system alarm via platform
      try {
        final platform = const MethodChannel('exact_alarms');
        final args = {
          'id': 999998,
          'triggerAtMillis': systemTime.millisecondsSinceEpoch,
          'title': 'Diag: System Alarm',
          'body': 'System alarm scheduled by diagnostics',
        };
        await platform.invokeMethod('scheduleAlarm', args);
        msg += 'System alarm scheduled in ~30s\n';
      } catch (e) {
        msg += 'Scheduling system alarm failed: $e\n';
      }
    } catch (e) {
      msg += 'Scheduling diagnostics failed: $e\n';
    }

    // 3) Read pending notifications from plugin
    try {
      final pending = await notificationPlugin.pendingNotificationRequests();
      msg += 'Pending notifications count: ${pending.length}\n';
    } catch (e) {
      msg += 'Could not read pending notifications: $e\n';
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
      if (!mounted) return;
      setState(() => _status = 'Incorrect current PIN');
      return;
    }
    await PinService().disablePin();
    if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _status = 'Incorrect current PIN');
      return;
    }
    try {
      await PinService().setPin(res.newPin);
      if (!mounted) return;
      setState(() => _status = 'PIN changed');
    } catch (e) {
      if (!mounted) return;
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
          // Offline operation queue status
          const OfflineQueueStatus(),

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
            leading: const Icon(Icons.volume_up),
            title: const Text('Text-to-Speech Settings'),
            subtitle: const Text('Configure voice, speed, and test TTS'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const TtsSettingsView(),
                ),
              );
            },
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Send test notification / Status'),
            subtitle: const Text(
              'Send an immediate test notification and show channel/permission status',
            ),
            onTap: _sendTestNotification,
          ),
          ListTile(
            leading: const Icon(Icons.health_and_safety_outlined),
            title: const Text('Run Alarm Diagnostics'),
            subtitle: const Text(
              'Schedules short plugin + system alarms and reports channel/status to help debug alarms not firing',
            ),
            onTap: _runAlarmDiagnostics,
          ),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Schedule test system alarm (1 min)'),
            subtitle: const Text(
              'Schedules a real system alarm that should ring like an alarm',
            ),
            onTap: _scheduleTestSystemAlarm,
          ),
          // Exact alarms control (user can request exact-alarm permission)
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Exact Alarms'),
            subtitle: const Text(
              'Request system setting to allow exact alarms',
            ),
            onTap: () async {
              if (!Platform.isAndroid) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Exact alarms are Android-only'),
                    ),
                  );
                }
                return;
              }
              try {
                const platform = MethodChannel('exact_alarms');
                final bool result = await platform.invokeMethod(
                  'requestExactAlarmPermission',
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        result
                            ? 'Requested exact alarm permission'
                            : 'Could not request exact alarm permission',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Error requesting exact alarm permission: $e',
                      ),
                    ),
                  );
                }
              }
            },
          ),
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
                  onPressed:
                      _offlineBusy || _homeRegionDownloaded
                          ? null
                          : () async {
                            setState(() {
                              _offlineBusy = true;
                              _status = null; // Clear previous status
                              _currentProgress =
                                  null; // Clear previous progress
                            });
                            try {
                              await OfflineMapService().init(
                                styleUri: 'mapbox://styles/mapbox/streets-v12',
                              );
                              await OfflineMapService().ensureHomeRegion();
                              // Status will be updated via progress stream
                            } catch (e) {
                              setState(
                                () =>
                                    _status =
                                        'Offline init/download failed: $e',
                              );
                            } finally {
                              // Don't set _offlineBusy = false here; let progress stream handle it
                            }
                          },
                  icon: const Icon(Icons.home_work_outlined),
                  label: Text(
                    _homeRegionDownloaded
                        ? 'Home Region Already Downloaded'
                        : 'Download Home Region (25 km)',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      _offlineBusy || !_hasOfflineData
                          ? null
                          : () async {
                            if (!mounted) return;
                            setState(() {
                              _offlineBusy = true;
                              _status = 'Clearing offline data...';
                            });
                            try {
                              await OfflineMapService().clearAll();
                              await _checkDownloadStatus(); // Refresh download status after clearing
                              if (!mounted) return;
                              setState(
                                () => _status = 'Requested offline data clear.',
                              );
                            } catch (e) {
                              if (!mounted) return;
                              setState(
                                () =>
                                    _status =
                                        'Failed to clear offline data: $e',
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _offlineBusy = false);
                              }
                            }
                          },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    _hasOfflineData ? 'Clear Offline Data' : 'No Offline Data',
                  ),
                ),
              ],
            ),
          ),
          _buildProgressDisplay(),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup & Restore'),
            subtitle: const Text(
              'Export tasks and statistics, or restore from JSON',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                FilledButton.icon(
                  onPressed:
                      _backupBusy
                          ? null
                          : () async {
                            if (!mounted) return;
                            setState(() {
                              _backupBusy = true;
                              _status = 'Preparing export...';
                            });
                            try {
                              final path =
                                  await BackupService().exportWithFilePicker();
                              if (!mounted) return;
                              if (path != null) {
                                setState(
                                  () =>
                                      _status =
                                          'Backup exported successfully!\nSaved to: ${path.split('\\').last}',
                                );
                              } else {
                                setState(
                                  () => _status = 'Export cancelled by user.',
                                );
                              }
                            } catch (e) {
                              if (!mounted) return;
                              setState(() => _status = 'Export failed: $e');
                            } finally {
                              if (mounted) {
                                setState(() => _backupBusy = false);
                              }
                            }
                          },
                  icon: const Icon(Icons.save_alt_outlined),
                  label: const Text('Export to JSON file'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed:
                      _backupBusy
                          ? null
                          : () async {
                            if (!mounted) return;
                            setState(() {
                              _backupBusy = true;
                              _status = 'Opening file picker...';
                            });
                            try {
                              if (!mounted) return;
                              setState(() {
                                _status = 'Selecting backup file...';
                              });

                              final success =
                                  await BackupService().importWithFilePicker();

                              if (!mounted) return;
                              if (success) {
                                setState(() {
                                  _status = 'Processing import...';
                                });

                                // Give a moment for UI to update
                                await Future.delayed(
                                  const Duration(milliseconds: 100),
                                );

                                if (!mounted) return;
                                setState(
                                  () =>
                                      _status =
                                          'Import successful! All tasks, history, and geofences restored.',
                                );

                                // Refresh all local data to reflect changes
                                _refresh();
                              } else {
                                setState(
                                  () => _status = 'Import cancelled by user.',
                                );
                              }
                            } catch (e) {
                              if (!mounted) return;
                              setState(() => _status = 'Import failed: $e');
                            } finally {
                              if (mounted) {
                                setState(() => _backupBusy = false);
                              }
                            }
                          },
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Import from JSON file'),
                ),
              ],
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
  String _enteredPin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  final _maxPinLength = 6;
  String? _error;

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

        // Auto-validate when confirmation is complete
        if (_confirmPin.length == _maxPinLength) {
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) _validateAndComplete();
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

  void _validateAndComplete() {
    if (_enteredPin.length != _maxPinLength) {
      setState(() => _error = 'Enter a PIN');
      return;
    }

    if (!RegExp(r'^\d{6}$').hasMatch(_enteredPin)) {
      setState(() => _error = 'Must be 6 digits');
      return;
    }

    if (_enteredPin != _confirmPin) {
      setState(() => _error = 'PINs do not match');
      return;
    }

    Navigator.of(context).pop(_PinPairResult(_enteredPin));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_isConfirming ? 'Confirm PIN' : 'Enable PIN'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isConfirming
                  ? 'Confirm your 6-digit PIN'
                  : 'Create a 6-digit PIN',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // PIN Display
            PinDisplay(
              pin: _isConfirming ? _confirmPin : _enteredPin,
              maxLength: _maxPinLength,
              dotSize: 12,
              spacing: 12,
            ),

            const SizedBox(height: 16),

            // Step indicator
            Text(
              _isConfirming ? 'Step 2 of 2' : 'Step 1 of 2',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            // Error message
            if (_error != null)
              Container(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            // Compact Numeric Keypad
            NumericKeypad(
              onNumberTap: _onNumberTap,
              onBackspace: _onBackspace,
              showBackspace: true,
              buttonSize: 50,
              fontSize: 24,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_isConfirming && _confirmPin.length == _maxPinLength)
          FilledButton(
            onPressed: _validateAndComplete,
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
  String _currentPin = '';
  String? _error;
  final int _maxPinLength = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Instructions
            Text(
              'Enter your current PIN',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // PIN Display
            PinDisplay(
              pin: _currentPin,
              maxLength: _maxPinLength,
              dotSize: 14,
              spacing: 12,
            ),

            const SizedBox(height: 16),

            // Error message
            if (_error != null)
              Container(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            // Compact Numeric Keypad
            NumericKeypad(
              onNumberTap: _onNumberTap,
              onBackspace: _onBackspace,
              showBackspace: true,
              buttonSize: 50,
              fontSize: 24,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_currentPin.length == _maxPinLength)
          FilledButton(onPressed: _submit, child: const Text('Confirm')),
      ],
    );
  }

  void _onNumberTap(String number) {
    if (_currentPin.length < _maxPinLength) {
      setState(() {
        _currentPin += number;
        _error = null;
      });

      // Auto-submit when PIN is complete
      if (_currentPin.length == _maxPinLength) {
        Future.delayed(const Duration(milliseconds: 200), () {
          _submit();
        });
      }
    }
  }

  void _onBackspace() {
    if (_currentPin.isNotEmpty) {
      setState(() {
        _currentPin = _currentPin.substring(0, _currentPin.length - 1);
        _error = null;
      });
    }
  }

  void _submit() {
    if (_currentPin.length == _maxPinLength) {
      Navigator.of(context).pop(_currentPin);
    } else {
      setState(() {
        _error = 'PIN must be $_maxPinLength digits';
      });
    }
  }
}

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog();

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

enum _ChangeStep { current, newPin, confirm }

class _ChangePinDialogState extends State<_ChangePinDialog> {
  _ChangeStep _currentStep = _ChangeStep.current;
  String _currentPin = '';
  String _newPin = '';
  String _confirmPin = '';
  String? _error;
  final int _maxPinLength = 6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Change PIN'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Instructions
            Text(
              _getInstructionText(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            // Step indicator
            Text(
              _getStepText(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            // PIN Display
            PinDisplay(
              pin: _getCurrentPin(),
              maxLength: _maxPinLength,
              dotSize: 14,
              spacing: 12,
            ),

            const SizedBox(height: 16),

            // Error message
            if (_error != null)
              Container(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            // Compact Numeric Keypad
            NumericKeypad(
              onNumberTap: _onNumberTap,
              onBackspace: _onBackspace,
              showBackspace: true,
              buttonSize: 50,
              fontSize: 24,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_isStepComplete())
          FilledButton(onPressed: _handleNext, child: Text(_getActionText())),
      ],
    );
  }

  String _getInstructionText() {
    switch (_currentStep) {
      case _ChangeStep.current:
        return 'Enter your current PIN';
      case _ChangeStep.newPin:
        return 'Enter your new PIN';
      case _ChangeStep.confirm:
        return 'Confirm your new PIN';
    }
  }

  String _getStepText() {
    switch (_currentStep) {
      case _ChangeStep.current:
        return 'Step 1 of 3';
      case _ChangeStep.newPin:
        return 'Step 2 of 3';
      case _ChangeStep.confirm:
        return 'Step 3 of 3';
    }
  }

  String _getCurrentPin() {
    switch (_currentStep) {
      case _ChangeStep.current:
        return _currentPin;
      case _ChangeStep.newPin:
        return _newPin;
      case _ChangeStep.confirm:
        return _confirmPin;
    }
  }

  bool _isStepComplete() {
    return _getCurrentPin().length == _maxPinLength;
  }

  String _getActionText() {
    switch (_currentStep) {
      case _ChangeStep.current:
        return 'Next';
      case _ChangeStep.newPin:
        return 'Next';
      case _ChangeStep.confirm:
        return 'Save';
    }
  }

  void _onNumberTap(String number) {
    final currentPin = _getCurrentPin();
    if (currentPin.length < _maxPinLength) {
      setState(() {
        switch (_currentStep) {
          case _ChangeStep.current:
            _currentPin += number;
            break;
          case _ChangeStep.newPin:
            _newPin += number;
            break;
          case _ChangeStep.confirm:
            _confirmPin += number;
            break;
        }
        _error = null;
      });

      // Auto-proceed when PIN is complete
      if (_getCurrentPin().length == _maxPinLength) {
        Future.delayed(const Duration(milliseconds: 300), () {
          _handleNext();
        });
      }
    }
  }

  void _onBackspace() {
    final currentPin = _getCurrentPin();
    if (currentPin.isNotEmpty) {
      setState(() {
        switch (_currentStep) {
          case _ChangeStep.current:
            _currentPin = _currentPin.substring(0, _currentPin.length - 1);
            break;
          case _ChangeStep.newPin:
            _newPin = _newPin.substring(0, _newPin.length - 1);
            break;
          case _ChangeStep.confirm:
            _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
            break;
        }
        _error = null;
      });
    }
  }

  void _handleNext() {
    if (!_isStepComplete()) {
      setState(() {
        _error = 'PIN must be $_maxPinLength digits';
      });
      return;
    }

    switch (_currentStep) {
      case _ChangeStep.current:
        setState(() {
          _currentStep = _ChangeStep.newPin;
          _error = null;
        });
        break;
      case _ChangeStep.newPin:
        setState(() {
          _currentStep = _ChangeStep.confirm;
          _error = null;
        });
        break;
      case _ChangeStep.confirm:
        if (_newPin == _confirmPin) {
          Navigator.of(context).pop(_PinChangeResult(_currentPin, _newPin));
        } else {
          setState(() {
            _error = 'PINs do not match';
            _confirmPin = '';
          });
        }
        break;
    }
  }
}
