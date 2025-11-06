import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'package:intl/intl.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/viewmodel/Geofencing/map_viewmodel.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/model/recurring_pattern.dart';
import 'package:intelliboro/widgets/recurring_selector.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:intelliboro/services/notification_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intelliboro/services/mapbox_search_service.dart';
import 'dart:async';

class TaskCreation extends StatefulWidget {
  final bool showMap;
  final String? name;
  final TaskModel? initialTask;

  // Call this function when submit
  //final Function(Task) onSubmit;
  const TaskCreation({
    super.key,
    required this.showMap,
    this.name,
    this.initialTask,
  });
  @override
  State<TaskCreation> createState() => _TaskCreationState();
}

class _TaskCreationState extends State<TaskCreation> {
  // Add state properties

  // Stores selected time
  TimeOfDay? selectedTime;
  // Stores selected date
  DateTime? selectedDate;
  // Stores selected priority (1-5 scale)
  int selectedPriority = 3; // Default to medium priority
  // Stores recurring pattern
  RecurringPattern selectedRecurringPattern = RecurringPattern.none();

  final DateTime _firstDate = DateTime(DateTime.now().year);
  final DateTime _lastDate = DateTime(DateTime.now().year + 1);
  final TextEditingController _nameController = TextEditingController();

  late final MapboxMapViewModel _mapViewModel;

  // Notification sound preference (app-wide default)
  String _selectedSoundKey = NotificationPreferencesService.soundDefault;

  // Task-specific notification sound (overrides app default)
  String? _taskNotificationSound;

  // Geofence selection state
  List<GeofenceData> _availableGeofences = [];
  String? _selectedGeofenceId;
  bool _isLoadingGeofences = false;

  // Snooze settings state
  int _currentSnoozeDuration = 5; // Default 5 minutes
  bool _isLoadingSnoozeSettings = false;

  // Search functionality state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<SearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  MapboxSearchService? _searchService;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _mapViewModel = MapboxMapViewModel();
    if (widget.name != null) {
      _nameController.text = widget.name!;
    }
    // If editing, prefill fields from initialTask
    if (widget.initialTask != null) {
      final t = widget.initialTask!;
      _nameController.text = t.taskName;
      selectedPriority = t.taskPriority;
      selectedTime = t.taskTime;
      selectedDate = t.taskDate;
      selectedRecurringPattern = t.recurringPattern ?? RecurringPattern.none();
      _selectedGeofenceId = t.geofenceId;
      _taskNotificationSound = t.notificationSound;
    }
    _loadGeofences();
    _loadSnoozeSettings();

    // Initialize search service if Mapbox is configured
    if (MapboxSearchService.isConfigured) {
      _searchService = MapboxSearchService();
      _searchFocusNode.addListener(_onSearchFocusChanged);
    }

    // Load default notification sound preference
    Future.microtask(() async {
      final key = await NotificationPreferencesService().getDefaultSound();
      if (!mounted) return;
      setState(() {
        _selectedSoundKey = key;
      });
    });
  }

  Future<void> _loadGeofences() async {
    setState(() {
      _isLoadingGeofences = true;
    });
    try {
      final geofenceStorage = GeofenceStorage();
      final geofences = await geofenceStorage.loadGeofences();
      setState(() {
        _availableGeofences = geofences;
        _isLoadingGeofences = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingGeofences = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading geofences: $e')));
      }
    }
  }

  Future<void> _loadSnoozeSettings() async {
    setState(() {
      _isLoadingSnoozeSettings = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final snoozeDuration =
          prefs.getInt('snooze_minutes') ??
          TaskTimerService().defaultSnoozeDuration.inMinutes;
      setState(() {
        _currentSnoozeDuration = snoozeDuration;
        _isLoadingSnoozeSettings = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingSnoozeSettings = false;
      });
    }
  }

  String formatDuration(int minutes) {
    if (minutes < 60) {
      return '${minutes}m';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return '${hours}h';
      } else {
        return '${hours}h ${remainingMinutes}m';
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounceTimer?.cancel();
    _searchService?.dispose();
    _mapViewModel.dispose();
    super.dispose();
  }

  // Search functionality methods
  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      _clearSearch();
      return;
    }

    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  void _onSearchFocusChanged() {
    setState(() {
      _showSearchResults =
          _searchFocusNode.hasFocus && _searchResults.isNotEmpty;
    });
  }

  Future<void> _performSearch(String query) async {
    if (_searchService == null || query.trim().isEmpty) return;

    if (!mounted) return;
    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _searchService!.searchPlaces(query: query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _showSearchResults = _searchFocusNode.hasFocus && results.isNotEmpty;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _showSearchResults = false;
          _isSearching = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    }
  }

  Future<void> _selectSearchResult(SearchResult result) async {
    if (_searchService == null) return;

    try {
      final retrievedPlace = await _searchService!.retrievePlace(result.id);
      if (retrievedPlace != null && mounted) {
        await _placeGeofenceAtSearchResult(retrievedPlace);
        _clearSearch();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location details: $e')),
        );
      }
    }
  }

  Future<void> _placeGeofenceAtSearchResult(SearchResult place) async {
    final point = Point(coordinates: Position(place.longitude, place.latitude));

    debugPrint('[Search] Search result location received');
    debugPrint(
      '[Search] Current pending radius: ${_mapViewModel.pendingRadiusMeters}m',
    );
    debugPrint(
      '[Search] Existing geofences count: ${_mapViewModel.savedGeofences.length}',
    );

    // Move map to the selected location
    // Null safety: Verify map is initialized before camera operations
    if (_mapViewModel.mapboxMap != null && _mapViewModel.isMapReady) {
      try {
        final cameraOptions = CameraOptions(center: point, zoom: 15.0);
        await _mapViewModel.mapboxMap!.flyTo(cameraOptions, null);
      } catch (e) {
        debugPrint('[Search] Error flying to location: $e');
        // Continue with geofence placement even if flyTo fails
      }
    } else {
      debugPrint('[Search] Warning: Map not ready for flyTo operation');
    }

    // Auto-adjust the point to avoid overlapping with existing geofences
    final adjustedPoint = await _mapViewModel.autoAdjustCenter(
      point,
      _mapViewModel.pendingRadiusMeters,
    );

    debugPrint('[Search] Point adjusted to avoid overlap');

    // Check if adjustment occurred
    final latDiff =
        (adjustedPoint.coordinates.lat - point.coordinates.lat).abs();
    final lngDiff =
        (adjustedPoint.coordinates.lng - point.coordinates.lng).abs();
    if (latDiff > 0.000001 || lngDiff > 0.000001) {
      debugPrint('[Search] Point was adjusted to avoid overlap!');
    } else {
      debugPrint('[Search] No adjustment needed - no overlaps detected');
    }

    // Set the adjusted point for geofence creation by calling displayExistingGeofence
    // This will show the geofence preview at the adjusted location
    await _mapViewModel.displayExistingGeofence(
      adjustedPoint,
      _mapViewModel.pendingRadiusMeters,
    );

    // Update the selected point in the view model for later geofence creation
    _mapViewModel.selectedPoint = adjustedPoint;

    debugPrint('[Search] Geofence helper placed at adjusted position');
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchResults = [];
      _showSearchResults = false;
      _isSearching = false;
    });
    _searchFocusNode.unfocus();
  }

  // Configure date format
  String formatDate(DateTime? dateTime) {
    if (dateTime == null) {
      return 'Select Date';
    }
    final formatter = DateFormat('yyyy-MM-dd');
    return formatter.format(dateTime);
  }

  // Configure time of Day
  String formatTimeOfDay(TimeOfDay? timeOfDay) {
    if (timeOfDay == null) {
      return 'Select Time';
    }

    final hour = timeOfDay.hour.toString().padLeft(2, '0');
    final minute = timeOfDay.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Select Date picker
  void _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: _firstDate,
      lastDate: _lastDate,
    );
    if (picked != null && picked != selectedDate && mounted) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  // Select Time picker
  void _selectTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: selectedTime ?? TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedTime && mounted) {
      setState(() {
        selectedTime = picked;
      });
    }
  }

  // Build Task name Textfield
  Widget _buildTextField() {
    return TextField(
      controller: _nameController,
      decoration: const InputDecoration(labelText: 'Task Name'),
    );
  }

  // Build Priority Selector
  Widget _buildPrioritySelector() {
    final theme = Theme.of(context);
    final priorityColor = _getPriorityColor(selectedPriority);

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: priorityColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: priorityColor.withOpacity(0.3)),
                  ),
                  child: Icon(
                    _getPriorityIcon(selectedPriority),
                    color: priorityColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Task Priority',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _getPriorityString(selectedPriority),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: priorityColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Low',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: selectedPriority.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    onChanged: (value) {
                      setState(() {
                        selectedPriority = value.round();
                      });
                    },
                    activeColor: priorityColor,
                    thumbColor: priorityColor,
                  ),
                ),
                Text(
                  'High',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: priorityColor.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: Text(
                _getPriorityDescription(selectedPriority),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getPriorityIcon(int priority) {
    switch (priority) {
      case 1:
        return Icons.low_priority_rounded;
      case 2:
        return Icons.expand_more_rounded;
      case 3:
        return Icons.radio_button_unchecked_rounded;
      case 4:
        return Icons.expand_less_rounded;
      case 5:
        return Icons.priority_high_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _getPriorityString(int priority) {
    switch (priority) {
      case 1:
        return 'Very Low';
      case 2:
        return 'Low';
      case 3:
        return 'Medium';
      case 4:
        return 'High';
      case 5:
        return 'Very High';
      default:
        return 'Medium';
    }
  }

  Color _getPriorityColor(int priority) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    switch (priority) {
      case 1:
        return const Color(0xFF1B5E20); // Very Low - Darker green 900 (better contrast)
      case 2:
        return const Color(0xFF827717); // Low - Darker lime 900 (better contrast)
      case 3:
        return const Color(0xFFF57F17); // Medium - Darker yellow 900 (better contrast)
      case 4:
        return const Color(0xFFE65100); // High - Darker orange 900 (better contrast)
      case 5:
        return const Color(0xFFB71C1C); // Very High - Red 900 (better contrast)
      default:
        return colorScheme.primary;
    }
  }

  String _getPriorityDescription(int priority) {
    switch (priority) {
      case 1:
        return 'Can be done later';
      case 2:
        return 'Not urgent';
      case 3:
        return 'Normal importance';
      case 4:
        return 'Important task';
      case 5:
        return 'Critical - highest priority';
      default:
        return 'Normal importance';
    }
  }

  // Build Recurring Pattern Selector
  Widget _buildRecurringSelector() {
    return RecurringSelector(
      initialPattern: selectedRecurringPattern,
      onPatternChanged: (pattern) {
        setState(() {
          selectedRecurringPattern = pattern;
        });
      },
    );
  }

  Widget _buildNotificationSoundSelector() {
    final theme = Theme.of(context);
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Task Notification Sound',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _taskNotificationSound,
                  hint: const Text('Use app default'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Use app default'),
                    ),
                    ...NotificationPreferencesService.getAvailableSounds().map(
                      (sound) => DropdownMenuItem<String>(
                        value: sound['key'],
                        child: Text(sound['name']!),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _taskNotificationSound = value;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a specific notification sound for this task, or leave as "Use app default" to use the global app setting.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapSection() {
    return ListenableBuilder(
      listenable: _mapViewModel,
      builder: (context, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Map container with proper gesture handling
            Container(
              height: MediaQuery.of(context).size.height * 0.35,
              width: MediaQuery.of(context).size.width,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  children: [
                    MapWidget(
                      key: const ValueKey("embedded_mapwidget"),
                      onMapCreated: _mapViewModel.onMapCreated,
                      onLongTapListener: _mapViewModel.onLongTap,
                      onZoomListener: _mapViewModel.onZoom,
                      onMapIdleListener: _mapViewModel.onCameraIdle,
                      // ScaleGestureRecognizer handles both panning and pinch-to-zoom
                      gestureRecognizers:
                          <Factory<OneSequenceGestureRecognizer>>{
                            Factory<ScaleGestureRecognizer>(
                              () => ScaleGestureRecognizer(),
                            ),
                            Factory<EagerGestureRecognizer>(
                              () => EagerGestureRecognizer(),
                            ),
                          },
                    ),
                    if (!_mapViewModel.isMapReady)
                      const Center(child: CircularProgressIndicator()),

                    // Search UI - only show if search service is available
                    if (_searchService != null)
                      Positioned(
                        top: 10,
                        left: 10,
                        right: 80, // Leave space for the "Saved" indicator
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                onChanged: _onSearchChanged,
                                decoration: InputDecoration(
                                  hintText: 'Search for places...',
                                  prefixIcon: Icon(Icons.search),
                                  suffixIcon:
                                      _isSearching
                                          ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : (_searchController.text.isNotEmpty
                                              ? IconButton(
                                                icon: Icon(Icons.clear),
                                                onPressed: _clearSearch,
                                              )
                                              : null),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),

                            // Search results dropdown
                            if (_showSearchResults && _searchResults.isNotEmpty)
                              Container(
                                margin: EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                constraints: BoxConstraints(maxHeight: 200),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _searchResults.length,
                                  itemBuilder: (context, index) {
                                    final result = _searchResults[index];
                                    return ListTile(
                                      leading: Icon(
                                        Icons.location_on,
                                        color: Colors.blue,
                                      ),
                                      title: Text(
                                        result.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      subtitle: Text(
                                        result.fullName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      onTap: () => _selectSearchResult(result),
                                      dense: true,
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),

                    if (_mapViewModel.selectedPoint != null)
                      Positioned(
                        bottom: 10,
                        left: 10,
                        child: Chip(
                          label: Text('Location Selected for Geofence'),
                          backgroundColor: Colors.greenAccent,
                        ),
                      ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Saved: ${_mapViewModel.savedGeofences.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Radius: ${_mapViewModel.pendingRadiusMeters.toStringAsFixed(0)} m',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Slider(
              value: _mapViewModel.pendingRadiusMeters.clamp(1.0, 1000.0),
              min: 1,
              max: 1000,
              divisions: 999,
              label:
                  '${_mapViewModel.pendingRadiusMeters.toStringAsFixed(0)} m',
              onChanged: (v) => _mapViewModel.setPendingRadius(v),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMapDisabled() {
    return const Text(
      'Location permissions are disabled or map display is turned off. Map functions will not work.',
    );
  }

  Widget _buildGeofenceSelector() {
    if (_isLoadingGeofences) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location-based Reminder (Optional)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Select an existing geofence for location reminders, or leave empty for time-based notifications only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_availableGeofences.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No existing geofences available. You can create new ones on the map view.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Select Geofence (Optional)',
                  border: OutlineInputBorder(),
                ),
                value: _selectedGeofenceId,
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('No location reminder'),
                  ),
                  ..._availableGeofences.map((geofence) {
                    String displayName =
                        geofence.task != null && geofence.task!.isNotEmpty
                            ? 'Geofence for "${geofence.task}"'
                            : 'Geofence ${geofence.id.substring(0, 8)}';
                    return DropdownMenuItem<String>(
                      value: geofence.id,
                      child: Text(displayName),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedGeofenceId = value;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnoozeSettingsSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.snooze_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Snooze Settings',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _isLoadingSnoozeSettings
                            ? 'Loading...'
                            : 'Current default: ${formatDuration(_currentSnoozeDuration)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Tasks are automatically snoozed when postponed or interrupted by higher priority tasks.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            // Inline snooze duration selector
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [5, 10, 15, 30, 60, 120].map((minutes) {
                    final isSelected = _currentSnoozeDuration == minutes;
                    return FilterChip(
                      label: Text(formatDuration(minutes)),
                      selected: isSelected,
                      onSelected: (selected) async {
                        if (selected) {
                          setState(() {
                            _currentSnoozeDuration = minutes;
                          });
                          // Save to preferences
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt(
                            'default_snooze_duration',
                            minutes,
                          );
                          // Update TaskTimerService
                          TaskTimerService().setDefaultSnoozeDuration(
                            Duration(minutes: minutes),
                          );
                        }
                      },
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(
      context,
    ).textTheme.apply(displayColor: Theme.of(context).colorScheme.onSurface);

    if (widget.name != null && _nameController.text.isEmpty) {
      _nameController.text = widget.name!;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialTask == null ? 'Create Task' : 'Edit Task'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Task Details', style: textTheme.headlineMedium),
              const SizedBox(height: 16.0),
              _buildTextField(),
              const SizedBox(height: 16.0),
              _buildPrioritySelector(),
              const SizedBox(height: 16.0),
              _buildRecurringSelector(),
              const SizedBox(height: 16.0),
              _buildSnoozeSettingsSection(),
              const SizedBox(height: 16.0),
              _buildNotificationSoundSelector(),
              const SizedBox(height: 16.0),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: () => _selectDate(context),
                      label: Text(formatDate(selectedDate)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(Icons.access_time),
                      onPressed: () => _selectTime(context),
                      label: Text(formatTimeOfDay(selectedTime)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              if (widget.showMap) ...[
                _buildGeofenceSelector(),
                const SizedBox(height: 16.0),
                if (_selectedGeofenceId == null) _buildMapSection(),
              ] else
                _buildMapDisabled(),
              const SizedBox(height: 24.0),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () async {
                  final taskName = _nameController.text;
                  debugPrint(
                    "[CreateTaskView] Task name being sent to ViewModel: '$taskName'",
                  );
                  if (taskName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a task name.'),
                      ),
                    );
                    return;
                  }

                  // Determine the geofence ID to use (if any)
                  String? geofenceIdForTask = _selectedGeofenceId;
                  debugPrint(
                    '[CreateTaskView] geofenceIdForTask: $geofenceIdForTask',
                  );

                  // Validate that either date/time OR geofence is provided
                  final hasDateTime =
                      selectedDate != null || selectedTime != null;
                  final hasGeofence =
                      geofenceIdForTask != null ||
                      _mapViewModel.selectedPoint != null;

                  debugPrint(
                    '[CreateTaskView] hasDateTime: $hasDateTime, hasGeofence: $hasGeofence (selectedGeofenceId: $geofenceIdForTask, selectedPoint: ${_mapViewModel.selectedPoint})',
                  );

                  if (!hasDateTime && !hasGeofence) {
                    showDialog(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: const Text('Task Timing Required'),
                            content: const Text(
                              'Every task needs either:\n\n'
                              '• A specific date and/or time (for time-based reminders)\n'
                              'OR\n'
                              '• A geofence location (for location-based reminders)\n\n'
                              'Please set one of these options to continue.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                    );
                    return;
                  }

                  // Persist default notification sound preference
                  try {
                    await NotificationPreferencesService().setDefaultSound(
                      _selectedSoundKey,
                    );
                  } catch (_) {}

                  // Create or update the task
                  if (widget.initialTask == null) {
                    await TaskRepository().insertTask(
                      TaskModel(
                        taskName: taskName,
                        taskPriority: selectedPriority,
                        taskTime:
                            selectedTime, // Only set if explicitly selected
                        taskDate:
                            selectedDate ??
                            DateTime.now(), // Default to today if not selected
                        isRecurring:
                            selectedRecurringPattern.type != RecurringType.none,
                        recurringPattern:
                            selectedRecurringPattern.type != RecurringType.none
                                ? selectedRecurringPattern
                                : null,
                        isCompleted: false,
                        geofenceId: geofenceIdForTask,
                        notificationSound: _taskNotificationSound,
                      ),
                    );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Task "$taskName" created.')),
                      );
                    }
                  } else {
                    // Update existing task
                    final existing = widget.initialTask!;
                    final updated = existing.copyWith(
                      taskName: taskName,
                      taskPriority: selectedPriority,
                      taskTime: selectedTime ?? existing.taskTime,
                      taskDate: selectedDate ?? existing.taskDate,
                      isRecurring:
                          selectedRecurringPattern.type != RecurringType.none,
                      recurringPattern:
                          selectedRecurringPattern.type != RecurringType.none
                              ? selectedRecurringPattern
                              : null,
                      isCompleted: existing.isCompleted,
                      geofenceId: geofenceIdForTask ?? existing.geofenceId,
                      notificationSound: _taskNotificationSound,
                    );
                    await TaskRepository().updateTask(updated);
                    // Notify listeners that tasks changed
                    TaskTimerService().tasksChanged.value = true;

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Task "$taskName" updated.')),
                      );
                    }
                  }

                  // Handle geofence creation or association
                  if (widget.showMap) {
                    if (_selectedGeofenceId != null) {
                      // Task is already associated with the existing geofence via geofenceId
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Task associated with existing geofence.',
                            ),
                          ),
                        );
                      }
                    } else if (_mapViewModel.selectedPoint != null) {
                      try {
                        final createdGeofenceId = await _mapViewModel
                            .createGeofenceAtSelectedPoint(
                              context,
                              taskName: taskName,
                            );

                        // Set the newly created geofence as selected
                        if (createdGeofenceId != null) {
                          debugPrint(
                            '[CreateTaskView] Setting _selectedGeofenceId to: $createdGeofenceId',
                          );
                          setState(() {
                            _selectedGeofenceId = createdGeofenceId;
                          });
                        } else {
                          debugPrint(
                            '[CreateTaskView] Warning: createGeofenceAtSelectedPoint returned null',
                          );
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'New geofence created for "$taskName".',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error creating geofence: $e'),
                            ),
                          );
                        }
                      }
                    }
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                child: ListenableBuilder(
                  listenable: _mapViewModel,
                  builder: (context, child) {
                    final buttonText =
                        (widget.showMap && _mapViewModel.selectedPoint != null)
                            ? "Create Task & Geofence"
                            : "Create Task";
                    return Text(
                      buttonText,
                      style: const TextStyle(fontSize: 16),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
