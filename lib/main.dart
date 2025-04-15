import 'package:flutter/material.dart';
//import 'package:flutter_svg/svg.dart';
import 'package:intelliboro/theme.dart';
import 'create_task_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

// Define the access token
const String accessToken = String.fromEnvironment('ACCESS_TOKEN');
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken(accessToken);
  runApp(Intelliboro());
}



class Intelliboro extends StatelessWidget {
  const Intelliboro({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Intelliboro',
      theme: appTheme,
      home: const HomePage(title: 'Intelliboro'),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 15.0),
                child: Text('21 March, 2025', style: TextStyle(fontSize: 15)),
              ),
              SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.only(left: 15),
                child: Text(
                  'Welcome!',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(height: 60),
              Padding(
                padding: const EdgeInsets.only(left: 15.0),
                child: Text(
                  'Tasks',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(height: 20),
              Expanded(child: TaskList()),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'New Task',
          child: const Icon(Icons.add),

          onPressed: () async {
            var status = await Permission.location.request();
            if (status.isDenied) {
              await Permission.location.request();
            } else if (status.isPermanentlyDenied) {
              openAppSettings();
            }
            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) {
                    return TaskCreation(showMap: status.isGranted);
                  },
                ),
              );
            }
          },
        ),
      ),
    );
  }
}

class TaskList extends StatelessWidget {
  const TaskList({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> entries = <String>[
      'A',
      'B',
      'C',
      'D',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'K',
      'L',
      'M',
      'N',
    ];

    return ListView.separated(
      padding: const EdgeInsets.all(22),
      itemCount: entries.length,
      itemBuilder: (BuildContext context, int index) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.blueGrey.shade100, width: 1.0),
          ),
          height: 50,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Entry ${entries[index]}',
              style: TextStyle(fontSize: 20),
            ),
          ),
        );
      },
      //separatorBuilder: (BuildContext context, int index) => const Divider(),
      separatorBuilder:
          (BuildContext context, int index) => SizedBox(height: 8),
    );
  }
}
