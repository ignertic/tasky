import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tasky/tasky.dart';

class TaskManagerScreenPage extends StatefulWidget {
  const TaskManagerScreenPage({super.key});

  @override
  _TaskManagerScreenPageState createState() => _TaskManagerScreenPageState();
}

class _TaskManagerScreenPageState extends State<TaskManagerScreenPage> {
  final TaskyManager taskyManager = TaskyManager(maxIsolates: 2);
  List<String> taskIds = [];
  Map<String, String> taskResults = {};

  @override
  void initState() {
    super.initState();

    for (int index = 0; index < 100; index++) {
      final taskN = taskyManager.addTask(computeFactorial, [20 + index], index,
          maxRetries: 5);
      taskIds.add(taskN);
      taskyManager.getResultStream(taskN).listen((result) {
        setState(() {
          taskResults[result.taskId] = result.error != null
              ? 'Failed: ${result.error}'
              : 'Success: ${result.result}';
        });
      });
    }
  }

  @override
  void dispose() {
    taskyManager.shutdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D2B),
      appBar: AppBar(
        title:
            const Text('Tasky Manager', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A1A40),
        elevation: 10,
        shadowColor: Colors.blueAccent.withOpacity(0.3),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: taskyManager.getIsolateStatusesStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.cyan),
              ),
            );
          }

          final isolateStatuses = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Isolates & Tasks',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ...isolateStatuses.map(
                (status) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F1F43),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ListTile(
                      title: Text(
                        'Isolate ${status['isolate'].hashCode}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        status['isIdle']
                            ? 'Status: Idle'
                            : 'Executing Task ${status['currentTaskId']}',
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      trailing: status['isIdle']
                          ? const Icon(
                              Icons.check_circle,
                              color: Colors.greenAccent,
                            )
                          : const CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
              const Divider(
                color: Colors.blueAccent,
                height: 30,
              ),
              ...taskIds.map((taskId) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F1F43),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.purpleAccent.withOpacity(0.5),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ListTile(
                        title: Text(
                          'Task $taskId',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          taskResults[taskId] ?? 'Pending...',
                          style: const TextStyle(
                            color: Colors.purpleAccent,
                          ),
                        ),
                        trailing: taskResults[taskId] == null
                            ? const CircularProgressIndicator()
                            : const Icon(
                                Icons.check_circle,
                                color: Colors.greenAccent,
                              ),
                      ),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

int computeFactorial(int n) {
  if (n <= 1) return 1;
  return (n * computeFactorial(n - 1));
}

Future<String> fetchDataFromNetwork(String url) async {
  final response = await HttpClient().getUrl(Uri.parse(url));
  final data = await response.close();
  return await data.transform(const Utf8Decoder()).join();
}
