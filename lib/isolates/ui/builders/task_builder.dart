import 'package:flutter/material.dart';
import '../../components/ism.dart';

class TaskBuilder extends StatefulWidget {
  final Function function;
  final List<dynamic> args;
  final int priority;
  final TaskyManager manager;
  final Widget Function(TaskResult) onResult;
  final Widget? Function(String taskId)? onProcessing;
  final Widget? Function(Object error)? onError;

  const TaskBuilder({
    super.key,
    required this.function,
    required this.args,
    required this.priority,
    required this.onResult,
    required this.manager,
    this.onProcessing,
    this.onError,
  });

  @override
  TaskBuilderState createState() => TaskBuilderState();
}

class TaskBuilderState extends State<TaskBuilder> {
  late String taskId;
  late Stream<TaskResult> resultStream;

  @override
  void initState() {
    super.initState();
    resultStream = widget.manager.getResultStream(_startTask());
  }

  String _startTask() {
    final taskId = widget.manager.addTask(
      widget.function,
      widget.args,
      widget.priority,
      maxRetries: 3,
    );
    return taskId;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TaskResult>(
      stream: resultStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.onProcessing?.call(taskId) ??
              const Center(
                child: Text('Tasky Processing...'),
              );
        } else if (snapshot.hasError) {
          return widget.onError?.call(snapshot.error!) ??
              Text('Error: ${snapshot.error}');
        } else if (snapshot.hasData) {
          return widget.onResult(snapshot.data!);
        } else {
          return Container();
        }
      },
    );
  }
}
