import 'package:flutter/material.dart';
import 'package:intelliboro/services/geofence_diagnostic_service.dart';
import 'dart:developer' as developer;

/// Debug screen to diagnose geofence and task issues
/// Add this to your app temporarily to run diagnostics
class GeofenceDiagnosticView extends StatefulWidget {
  const GeofenceDiagnosticView({Key? key}) : super(key: key);

  @override
  State<GeofenceDiagnosticView> createState() => _GeofenceDiagnosticViewState();
}

class _GeofenceDiagnosticViewState extends State<GeofenceDiagnosticView> {
  final _geofenceIdController = TextEditingController();
  final _diagnosticService = GeofenceDiagnosticService();
  bool _isRunning = false;
  String _status = 'Ready to run diagnostics';

  @override
  void dispose() {
    _geofenceIdController.dispose();
    super.dispose();
  }

  Future<void> _runFullDiagnostic() async {
    setState(() {
      _isRunning = true;
      _status = 'Running full diagnostic...';
    });

    try {
      await _diagnosticService.diagnoseGeofenceTasks();
      setState(() {
        _status = 'Diagnostic complete! Check logs for results.';
      });
      developer.log('[DiagnosticView] Full diagnostic completed');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
      developer.log('[DiagnosticView] Error: $e');
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  Future<void> _simulateTrigger() async {
    final geofenceId = _geofenceIdController.text.trim();
    if (geofenceId.isEmpty) {
      setState(() {
        _status = 'Please enter a geofence ID';
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _status = 'Simulating trigger for geofence: $geofenceId...';
    });

    try {
      await _diagnosticService.simulateGeofenceTrigger(geofenceId);
      setState(() {
        _status = 'Simulation complete! Check logs for what would be found.';
      });
      developer.log('[DiagnosticView] Simulation completed for $geofenceId');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
      });
      developer.log('[DiagnosticView] Error: $e');
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geofence Diagnostics'),
        backgroundColor: Colors.orange,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Full Database Diagnostic',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This will scan all geofences and tasks, checking which tasks '
                      'are linked to geofences and their status.',
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isRunning ? null : _runFullDiagnostic,
                      icon: const Icon(Icons.bug_report),
                      label: const Text('Run Full Diagnostic'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Simulate Geofence Trigger',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Test what the background callback would find when entering '
                      'a specific geofence.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _geofenceIdController,
                      decoration: const InputDecoration(
                        labelText: 'Geofence ID',
                        hintText: 'Enter the geofence ID to test',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isRunning ? null : _simulateTrigger,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Simulate Trigger'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_status),
                    if (_isRunning) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            const Spacer(),
            const Text(
              'Results will appear in the app logs. '
              'Use "flutter run" or check logcat for detailed output.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
