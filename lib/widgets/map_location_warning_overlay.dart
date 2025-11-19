import 'package:flutter/material.dart';
import 'package:intelliboro/services/location_monitor_service.dart';
import 'package:geolocator/geolocator.dart';

/// A full-screen warning overlay that replaces the map when location is disabled.
/// Shows a large, prominent warning message with action button.
class MapLocationWarningOverlay extends StatefulWidget {
  final Widget child;

  const MapLocationWarningOverlay({super.key, required this.child});

  @override
  State<MapLocationWarningOverlay> createState() =>
      _MapLocationWarningOverlayState();
}

class _MapLocationWarningOverlayState extends State<MapLocationWarningOverlay> {
  bool _isLocationEnabled = true;

  @override
  void initState() {
    super.initState();
    _checkInitialStatus();
    _listenToLocationStatus();
  }

  Future<void> _checkInitialStatus() async {
    final isEnabled = await Geolocator.isLocationServiceEnabled();
    if (mounted) {
      setState(() {
        _isLocationEnabled = isEnabled;
      });
    }
  }

  void _listenToLocationStatus() {
    LocationMonitorService().locationStatusStream.listen((isEnabled) {
      if (mounted) {
        setState(() {
          _isLocationEnabled = isEnabled;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocationEnabled) {
      return widget.child;
    }

    // Show full-screen warning instead of map
    return Container(
      color: Colors.red.shade50,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off, size: 120, color: Colors.red.shade700),
              const SizedBox(height: 32),
              Text(
                'LOCATION SERVICES DISABLED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Map and location features are unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.red.shade800),
              ),
              const SizedBox(height: 8),
              Text(
                'Please enable location services to continue',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.red.shade700),
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                onPressed: () async {
                  await Geolocator.openLocationSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                icon: const Icon(Icons.settings, size: 28),
                label: const Text('Open Location Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
