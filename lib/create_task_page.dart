import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  // Store selected geofence

  final DateTime _firstDate = DateTime(DateTime.now().year);
  final DateTime _lastDate = DateTime(DateTime.now().year + 1);
  final TextEditingController _nameController = TextEditingController();

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

  // Check if location permissions were granted disable map if not

  // Choose the latitude and longitude from the map
  //// Submit
  //Widget _buildSubmitButton(){
  //return ElevatedButton(onPressed: widget., child: Padding(padding: const EdgeInsets.all(16.0),
  //child: Text('Create Task'),));
  //}
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(
      context,
    ).textTheme.apply(displayColor: Theme.of(context).colorScheme.onSurface);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tasks', style: textTheme.headlineMedium),
            const SizedBox(height: 16.0),
            _buildTextField(),

            // Select Date picker
            const SizedBox(height: 16.0),
            // Select TimePicker
            Row(
              children: [
                TextButton(
                  onPressed: () => _selectDate(context),
                  child: Text(formatDate(selectedDate)),
                ),
                TextButton(
                  onPressed: () => _selectTime(context),
                  child: Text(formatTimeOfDay(selectedTime)),
                ),
              ],
            ),
            // Select Location picker
            if(showMap)
            _buildMapSection()
          ],
        ),
      ),
    );
  }

  // Create task control
}
