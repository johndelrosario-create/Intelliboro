import 'package:flutter/material.dart';
import 'package:intelliboro/services/location_monitor_service.dart';
import 'package:geolocator/geolocator.dart';

/// A persistent red warning banner that appears when location services are disabled.
/// Shows at the top of screens to alert the user.
class LocationWarningBanner extends StatefulWidget {
  const LocationWarningBanner({super.key});

  @override
  State<LocationWarningBanner> createState() => _LocationWarningBannerState();
}

class _LocationWarningBannerState extends State<LocationWarningBanner> {
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
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '⚠️ LOCATION SERVICES DISABLED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Geofenced reminders will not work while location is turned off',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () async {
              await Geolocator.openLocationSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }
}
