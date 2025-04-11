import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intelliboro/theme.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: appTheme,
      home: Scaffold(
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
            FloatingActionButton(onPressed:_newTask,
            tooltip: 'Hi',
            child: const Icon(Icons.add),)
            ],
          ),
        ),
      ),
    );
  }
}

void _newTask(){
}
class TaskList extends StatelessWidget {
  const TaskList({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> entries = <String>['A', 'B', 'C'];

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
      separatorBuilder: (BuildContext context, int index) => SizedBox(height: 8,),
    );
  }
}
