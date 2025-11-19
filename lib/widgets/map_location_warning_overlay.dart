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

    // Show a responsive warning overlay that adapts when used inside a
    // constrained container (e.g. embedded map in a smaller area).
    return Container(
      color: Colors.red.shade50,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isCompact =
              constraints.maxHeight < 300 || constraints.maxWidth < 320;
          final double padding = isCompact ? 12.0 : 32.0;
          // Ensure icon and text sizes scale to fit inside the provided map
          final double maxContentWidth = (constraints.maxWidth - (padding * 2))
              .clamp(120.0, 800.0);
          final double iconSize = (isCompact ? 64.0 : 120.0).clamp(
            40.0,
            maxContentWidth * 0.28,
          );
          final double titleSize = (isCompact ? 18.0 : 28.0).clamp(
            14.0,
            maxContentWidth * 0.09,
          );
          final double subtitleSize = (isCompact ? 13.0 : 18.0).clamp(
            12.0,
            maxContentWidth * 0.06,
          );

          return Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_off,
                        size: iconSize,
                        color: Colors.red.shade700,
                      ),
                      SizedBox(height: isCompact ? 10 : 20),
                      Text(
                        'LOCATION SERVICES DISABLED',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
                      SizedBox(height: isCompact ? 8 : 12),
                      Text(
                        'Map and location features are unavailable. Geofenced reminders will not work while location is turned off.',
                        textAlign: TextAlign.center,
                        softWrap: true,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          fontSize: subtitleSize,
                          color: Colors.red.shade800,
                        ),
                      ),
                      SizedBox(height: isCompact ? 10 : 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await Geolocator.openLocationSettings();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 12 : 24,
                            vertical: isCompact ? 8 : 12,
                          ),
                          textStyle: TextStyle(
                            fontSize: isCompact ? 13 : 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        icon: Icon(Icons.settings, size: isCompact ? 16 : 22),
                        label: const Text('Open Location Settings'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
