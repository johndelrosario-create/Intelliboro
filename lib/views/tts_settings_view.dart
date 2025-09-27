import 'package:flutter/material.dart';
import 'package:intelliboro/services/text_to_speech_service.dart';
import 'package:intelliboro/services/context_detection_service.dart';

class TtsSettingsView extends StatefulWidget {
  const TtsSettingsView({super.key});

  @override
  State<TtsSettingsView> createState() => _TtsSettingsViewState();
}

class _TtsSettingsViewState extends State<TtsSettingsView> {
  final TextToSpeechService _ttsService = TextToSpeechService();
  final ContextDetectionService _contextService = ContextDetectionService();
  
  bool _isLoading = true;
  List<String> _availableLanguages = [];
  
  // TTS Settings
  bool _ttsEnabled = true;
  double _speechRate = 0.5;
  double _volume = 0.8;
  double _pitch = 1.0;
  String _selectedLanguage = 'en-US';
  
  // Context Settings
  bool _contextDetectionEnabled = true;
  bool _locationContextEnabled = true;
  bool _timeContextEnabled = true;
  bool _batteryContextEnabled = false;
  bool _connectivityContextEnabled = false;
  int _batteryThreshold = 20;
  int _timeWindowMinutes = 5;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      await _ttsService.init();
      await _contextService.init();
      
      // Load current settings
      setState(() {
        _ttsEnabled = _ttsService.isEnabled;
        _speechRate = _ttsService.speechRate;
        _volume = _ttsService.volume;
        _pitch = _ttsService.pitch;
        _selectedLanguage = _ttsService.language;
        
        _contextDetectionEnabled = _contextService.isEnabled;
        _locationContextEnabled = _contextService.locationContextEnabled;
        _timeContextEnabled = _contextService.timeContextEnabled;
        _batteryContextEnabled = _contextService.batteryContextEnabled;
        _connectivityContextEnabled = _contextService.connectivityContextEnabled;
        _batteryThreshold = _contextService.batteryThreshold;
        _timeWindowMinutes = _contextService.timeContextWindow.inMinutes;
      });
      
      // Get available languages
      _availableLanguages = await _ttsService.getLanguages();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateTtsEnabled(bool enabled) async {
    await _ttsService.setEnabled(enabled);
    setState(() {
      _ttsEnabled = enabled;
    });
  }

  Future<void> _updateSpeechRate(double rate) async {
    await _ttsService.setSpeechRate(rate);
    setState(() {
      _speechRate = rate;
    });
  }

  Future<void> _updateVolume(double volume) async {
    await _ttsService.setVolume(volume);
    setState(() {
      _volume = volume;
    });
  }

  Future<void> _updatePitch(double pitch) async {
    await _ttsService.setPitch(pitch);
    setState(() {
      _pitch = pitch;
    });
  }

  Future<void> _updateLanguage(String language) async {
    await _ttsService.setLanguage(language);
    setState(() {
      _selectedLanguage = language;
    });
  }

  Future<void> _updateContextDetectionEnabled(bool enabled) async {
    await _contextService.setEnabled(enabled);
    setState(() {
      _contextDetectionEnabled = enabled;
    });
  }

  Future<void> _updateLocationContextEnabled(bool enabled) async {
    await _contextService.setLocationContextEnabled(enabled);
    setState(() {
      _locationContextEnabled = enabled;
    });
  }

  Future<void> _updateTimeContextEnabled(bool enabled) async {
    await _contextService.setTimeContextEnabled(enabled);
    setState(() {
      _timeContextEnabled = enabled;
    });
  }

  Future<void> _updateBatteryContextEnabled(bool enabled) async {
    await _contextService.setBatteryContextEnabled(enabled);
    setState(() {
      _batteryContextEnabled = enabled;
    });
  }

  Future<void> _updateConnectivityContextEnabled(bool enabled) async {
    await _contextService.setConnectivityContextEnabled(enabled);
    setState(() {
      _connectivityContextEnabled = enabled;
    });
  }

  Future<void> _updateBatteryThreshold(int threshold) async {
    await _contextService.setBatteryThreshold(threshold);
    setState(() {
      _batteryThreshold = threshold;
    });
  }

  Future<void> _updateTimeWindow(int minutes) async {
    await _contextService.setTimeContextWindow(Duration(minutes: minutes));
    setState(() {
      _timeWindowMinutes = minutes;
    });
  }

  Future<void> _testTts() async {
    await _ttsService.testSpeech();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TTS test completed'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Text-to-Speech Settings'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Text-to-Speech Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Text-to-Speech Settings Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Text-to-Speech Settings',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  
                  // Enable/Disable TTS
                  SwitchListTile(
                    title: const Text('Enable Text-to-Speech'),
                    subtitle: const Text('Turn on spoken notifications for tasks'),
                    value: _ttsEnabled,
                    onChanged: _updateTtsEnabled,
                  ),
                  
                  const Divider(),
                  
                  // Language Selection
                  if (_availableLanguages.isNotEmpty) ...[
                    ListTile(
                      title: const Text('Language'),
                      subtitle: Text(_selectedLanguage),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () async {
                        final result = await showDialog<String>(
                          context: context,
                          builder: (context) => _LanguageSelectionDialog(
                            languages: _availableLanguages,
                            currentLanguage: _selectedLanguage,
                          ),
                        );
                        if (result != null) {
                          await _updateLanguage(result);
                        }
                      },
                    ),
                    const Divider(),
                  ],
                  
                  // Speech Rate
                  ListTile(
                    title: const Text('Speech Rate'),
                    subtitle: Slider(
                      value: _speechRate,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      label: '${(_speechRate * 100).round()}%',
                      onChanged: _ttsEnabled ? _updateSpeechRate : null,
                    ),
                  ),
                  
                  // Volume
                  ListTile(
                    title: const Text('Volume'),
                    subtitle: Slider(
                      value: _volume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      label: '${(_volume * 100).round()}%',
                      onChanged: _ttsEnabled ? _updateVolume : null,
                    ),
                  ),
                  
                  // Pitch
                  ListTile(
                    title: const Text('Pitch'),
                    subtitle: Slider(
                      value: _pitch,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      label: _pitch.toStringAsFixed(1),
                      onChanged: _ttsEnabled ? _updatePitch : null,
                    ),
                  ),
                  
                  const Divider(),
                  
                  // Test Button
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _ttsEnabled ? _testTts : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Test Speech'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Context Detection Settings Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Context Detection Settings',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  
                  // Enable/Disable Context Detection
                  SwitchListTile(
                    title: const Text('Enable Context Detection'),
                    subtitle: const Text('Automatically detect contexts for TTS notifications'),
                    value: _contextDetectionEnabled,
                    onChanged: _updateContextDetectionEnabled,
                  ),
                  
                  const Divider(),
                  
                  // Location Context
                  SwitchListTile(
                    title: const Text('Location Context'),
                    subtitle: const Text('Trigger TTS when entering geofence areas'),
                    value: _locationContextEnabled,
                    onChanged: _contextDetectionEnabled ? _updateLocationContextEnabled : null,
                  ),
                  
                  // Time Context
                  SwitchListTile(
                    title: const Text('Time Context'),
                    subtitle: const Text('Trigger TTS based on scheduled times'),
                    value: _timeContextEnabled,
                    onChanged: _contextDetectionEnabled ? _updateTimeContextEnabled : null,
                  ),
                  
                  // Battery Context
                  SwitchListTile(
                    title: const Text('Battery Context'),
                    subtitle: const Text('Trigger TTS when battery is low'),
                    value: _batteryContextEnabled,
                    onChanged: _contextDetectionEnabled ? _updateBatteryContextEnabled : null,
                  ),
                  
                  // Battery Threshold
                  if (_batteryContextEnabled && _contextDetectionEnabled) ...[
                    ListTile(
                      title: const Text('Battery Threshold'),
                      subtitle: Text('${_batteryThreshold}%'),
                      trailing: SizedBox(
                        width: 200,
                        child: Slider(
                          value: _batteryThreshold.toDouble(),
                          min: 5,
                          max: 50,
                          divisions: 9,
                          label: '${_batteryThreshold}%',
                          onChanged: (value) => _updateBatteryThreshold(value.round()),
                        ),
                      ),
                    ),
                  ],
                  
                  // Connectivity Context
                  SwitchListTile(
                    title: const Text('Connectivity Context'),
                    subtitle: const Text('Trigger TTS based on network changes'),
                    value: _connectivityContextEnabled,
                    onChanged: _contextDetectionEnabled ? _updateConnectivityContextEnabled : null,
                  ),
                  
                  const Divider(),
                  
                  // Time Window
                  if (_timeContextEnabled && _contextDetectionEnabled) ...[
                    ListTile(
                      title: const Text('Time Context Window'),
                      subtitle: Text('${_timeWindowMinutes} minutes'),
                      trailing: SizedBox(
                        width: 200,
                        child: Slider(
                          value: _timeWindowMinutes.toDouble(),
                          min: 1,
                          max: 30,
                          divisions: 29,
                          label: '${_timeWindowMinutes}m',
                          onChanged: (value) => _updateTimeWindow(value.round()),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageSelectionDialog extends StatelessWidget {
  final List<String> languages;
  final String currentLanguage;

  const _LanguageSelectionDialog({
    required this.languages,
    required this.currentLanguage,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Language'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: languages.length,
          itemBuilder: (context, index) {
            final language = languages[index];
            return RadioListTile<String>(
              title: Text(language),
              value: language,
              groupValue: currentLanguage,
              onChanged: (value) {
                Navigator.of(context).pop(value);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}