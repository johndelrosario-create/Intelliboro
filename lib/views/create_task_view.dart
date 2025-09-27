import 'package:flutter/material.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'package:intl/intl.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/viewModel/Geofencing/map_viewmodel.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:intelliboro/models/geofence_data.dart';
import 'package:intelliboro/services/geofence_storage.dart';
import 'package:intelliboro/model/recurring_pattern.dart';
import 'package:intelliboro/widgets/recurring_selector.dart';
import 'package:intelliboro/services/task_timer_service.dart';
import 'package:intelliboro/services/notification_preferences_service.dart';
import 'package:permission_handler/permission_handler.dart';

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

  // Geofence selection state
  List<GeofenceData> _availableGeofences = [];
  String? _selectedGeofenceId;
  bool _isLoadingGeofences = false;
  bool _useExistingGeofence = false;

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
      _useExistingGeofence = t.geofenceId != null;
    }
    _loadGeofences();
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

  @override
  void dispose() {
    _nameController.dispose();
    _mapViewModel.dispose();
    super.dispose();
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
    if (picked != null && picked != selectedDate) {
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
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedTime) {
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
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: priorityColor,
                          fontWeight: FontWeight.w500,
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
                color: priorityColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: priorityColor.withOpacity(0.2)),
              ),
              child: Text(
                _getPriorityDescription(selectedPriority),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: priorityColor,
                  fontWeight: FontWeight.w500,
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
    switch (priority) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.lightGreen;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.deepOrange;
      case 5:
        return Colors.red;
      default:
        return Colors.orange;
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
              'Default Notification Sound (Android)',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            RadioListTile<String>(
              title: const Text('System Default'),
              value: NotificationPreferencesService.soundDefault,
              groupValue: _selectedSoundKey,
              onChanged: (v) => setState(() => _selectedSoundKey = v!),
            ),
            RadioListTile<String>(
              title: const Text('Silent'),
              value: NotificationPreferencesService.soundSilent,
              groupValue: _selectedSoundKey,
              onChanged: (v) => setState(() => _selectedSoundKey = v!),
            ),
            RadioListTile<String>(
              title: const Text('Alarm style'),
              value: NotificationPreferencesService.soundAlarm,
              groupValue: _selectedSoundKey,
              onChanged: (v) => setState(() => _selectedSoundKey = v!),
            ),
            const SizedBox(height: 4),
            const Text(
              'This sets the app default sound used for task reminders on Android.\nYou can change it later in Settings.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () async {
                  // Open the app's notification settings so the user can configure channel sound
                  try {
                    await openAppSettings();
                  } catch (_) {}
                },
                icon: const Icon(Icons.settings_applications_outlined),
                label: const Text('Open app notification settings'),
              ),
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
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.3,
              width: MediaQuery.of(context).size.width,
              child: Stack(
                children: [
                  MapWidget(
                    key: const ValueKey("embedded_mapwidget"),
                    onMapCreated: _mapViewModel.onMapCreated,
                    onLongTapListener: _mapViewModel.onLongTap,
                    onZoomListener: _mapViewModel.onZoom,
                    onMapIdleListener: _mapViewModel.onCameraIdle,
                  ),
                  if (!_mapViewModel.isMapReady)
                    const Center(child: CircularProgressIndicator()),
                  if (_mapViewModel.selectedPoint != null)
                    Positioned(
                      top: 10,
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
            const SizedBox(height: 8),
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
              'Add a location reminder or leave empty for time-based notifications only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text('No Location Reminder'),
                    value: false,
                    groupValue: _useExistingGeofence,
                    onChanged: (value) {
                      setState(() {
                        _useExistingGeofence = false;
                        _selectedGeofenceId = null;
                        _mapViewModel.clearSelectedPoint();
                      });
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text('Create New Location'),
                    value: false,
                    groupValue: _useExistingGeofence,
                    onChanged: (value) {
                      setState(() {
                        _useExistingGeofence = false;
                        _selectedGeofenceId = null;
                      });
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text('Use Existing Location'),
                    value: true,
                    groupValue: _useExistingGeofence,
                    onChanged:
                        _availableGeofences.isEmpty
                            ? null
                            : (value) {
                              setState(() {
                                _useExistingGeofence = value!;
                              });
                            },
                  ),
                ),
              ],
            ),
            if (_useExistingGeofence) ...[
              const SizedBox(height: 8),
              if (_availableGeofences.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'No existing geofences available. Create a new one instead.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Select Geofence',
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedGeofenceId,
                  items:
                      _availableGeofences.map((geofence) {
                        String displayName =
                            geofence.task != null && geofence.task!.isNotEmpty
                                ? 'Geofence for "${geofence.task}"'
                                : 'Geofence ${geofence.id.substring(0, 8)}';
                        return DropdownMenuItem<String>(
                          value: geofence.id,
                          child: Text(displayName),
                        );
                      }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedGeofenceId = value;
                    });
                  },
                  validator:
                      _useExistingGeofence
                          ? (value) =>
                              value == null ? 'Please select a geofence' : null
                          : null,
                ),
            ],
            if (!_useExistingGeofence) ...[
              const SizedBox(height: 8),
              const Text(
                'Long-press on the map below to select a location for the new geofence.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
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
                if (!_useExistingGeofence) _buildMapSection(),
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
                  String? geofenceIdForTask;
                  if (widget.showMap && _useExistingGeofence) {
                    geofenceIdForTask = _selectedGeofenceId;
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
                        taskTime: selectedTime ?? TimeOfDay.now(),
                        taskDate: selectedDate ?? DateTime.now(),
                        isRecurring:
                            selectedRecurringPattern.type != RecurringType.none,
                        recurringPattern:
                            selectedRecurringPattern.type != RecurringType.none
                                ? selectedRecurringPattern
                                : null,
                        isCompleted: false,
                        geofenceId: geofenceIdForTask,
                      ),
                    );

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Task "$taskName" created.')),
                    );
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
                    );
                    await TaskRepository().updateTask(updated);
                    // Notify listeners that tasks changed
                    TaskTimerService().tasksChanged.value = true;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Task "$taskName" updated.')),
                    );
                  }

                  // Handle geofence creation or association
                  if (widget.showMap) {
                    if (_useExistingGeofence && _selectedGeofenceId != null) {
                      // Task is already associated with the existing geofence via geofenceId
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Task associated with existing geofence.',
                          ),
                        ),
                      );
                    } else if (!_useExistingGeofence &&
                        _mapViewModel.selectedPoint != null) {
                      try {
                        await _mapViewModel.createGeofenceAtSelectedPoint(
                          context,
                          taskName: taskName,
                        );
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