import 'package:flutter/material.dart';
import 'package:intelliboro/repository/task_repository.dart';
import 'package:intl/intl.dart';
import 'package:intelliboro/model/task_model.dart';
import 'package:intelliboro/viewModel/Geofencing/map_viewmodel.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class TaskCreation extends StatefulWidget {
  final bool showMap;
  final String? name;

  // Call this function when submit
  //final Function(Task) onSubmit;
  const TaskCreation({super.key, required this.showMap, this.name});
  @override
  State<TaskCreation> createState() => _TaskCreationState();
}

class _TaskCreationState extends State<TaskCreation> {
  // Add state properties

  // Stores selected time
  TimeOfDay? selectedTime;
  // Stores selected date
  DateTime? selectedDate;

  final DateTime _firstDate = DateTime(DateTime.now().year);
  final DateTime _lastDate = DateTime(DateTime.now().year + 1);
  final TextEditingController _nameController = TextEditingController();

  late final MapboxMapViewModel _mapViewModel;

  @override
  void initState() {
    super.initState();
    _mapViewModel = MapboxMapViewModel();
    if (widget.name != null) {
      _nameController.text = widget.name!;
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

  Widget _buildMapSection() {
    return ListenableBuilder(
      listenable: _mapViewModel,
      builder: (context, child) {
        return SizedBox(
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
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapDisabled() {
    return const Text(
      'Location permissions are disabled or map display is turned off. Map functions will not work.',
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
        title: const Text('Create Task'),
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
                Text('Geofence', style: textTheme.titleMedium),
                const Text(
                  'Long-press on the map below to select a location for the geofence.',
                ),
                const SizedBox(height: 8.0),
                _buildMapSection(),
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

                  await TaskRepository().insertTask(
                    TaskModel(
                      taskName: taskName,
                      taskPriority: 1,
                      taskTime: selectedTime ?? TimeOfDay.now(),
                      taskDate: selectedDate ?? DateTime.now(),
                      isRecurring: false,
                      isCompleted: false,
                    ),
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Task "$taskName" created.')),
                  );

                  if (widget.showMap && _mapViewModel.selectedPoint != null) {
                    try {
                      await _mapViewModel.createGeofenceAtSelectedPoint(
                        context,
                        taskName: taskName,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Geofence added for "$taskName" at selected location.',
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
                  } else if (widget.showMap &&
                      _mapViewModel.selectedPoint == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No location selected on map. Geofence not created.',
                        ),
                      ),
                    );
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
