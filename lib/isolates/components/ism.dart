import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:collection/collection.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

class Task implements Comparable<Task> {
  final String id;
  final Function function;
  final List<dynamic> args;
  final int priority;
  final int maxRetries;
  int retryCount = 0;
  DateTime? startTime;

  Task(this.id, this.function, this.args, this.priority, {this.maxRetries = 3});

  @override
  int compareTo(Task other) => other.priority.compareTo(priority);
}

class TaskResult {
  final String taskId;
  final dynamic result;
  final Exception? error;
  final Duration duration;
  final int? memoryUsage;

  TaskResult(this.taskId, this.result, this.duration, this.memoryUsage,
      [this.error]);
}

class IsolateStatus {
  final Isolate isolate;
  bool isIdle;
  String? currentTaskId;
  DateTime? taskStartTime;

  IsolateStatus(this.isolate,
      {this.isIdle = true, this.currentTaskId, this.taskStartTime});
}

class TaskyManager {
  final _taskQueue = PriorityQueue<Task>();
  final _availableIsolates = <Isolate, SendPort>{};
  final _isolateStatuses = <Isolate, IsolateStatus>{};
  final _taskResults = <String, TaskResult>{};
  final _resultStreamControllers = <String, StreamController<TaskResult>>{};
  int isolateCount;
  final int maxIsolates;
  bool _isShuttingDown = false;
  final Logger _logger = Logger();

  TaskyManager({this.isolateCount = 4, this.maxIsolates = 10}) {
    for (var i = 0; i < isolateCount; i++) {
      _spawnIsolate();
    }
  }

  Stream<TaskResult> getResultStream(String taskId) {
    if (!_resultStreamControllers.containsKey(taskId)) {
      _resultStreamControllers[taskId] =
          StreamController<TaskResult>.broadcast();
    }
    return _resultStreamControllers[taskId]!.stream;
  }

  Stream<List<Map<String, dynamic>>> getIsolateStatusesStream() async* {
    while (!_isShuttingDown) {
      yield getIsolateStatuses();
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  void _spawnIsolate() async {
    final receivePort = ReceivePort();
    final isolate =
        await Isolate.spawn(_isolateEntryPoint, receivePort.sendPort);

    final sendPortCompleter = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        sendPortCompleter.complete(message);
      } else if (message is TaskResult) {
        _handleTaskResult(isolate, message);
      }
    });

    final sendPort = await sendPortCompleter.future;
    _availableIsolates[isolate] = sendPort;
    _isolateStatuses[isolate] = IsolateStatus(isolate);

    _assignTaskToIsolate(isolate);
  }

  void _handleTaskResult(Isolate isolate, TaskResult result) {
    _taskResults[result.taskId] = result;
    _resultStreamControllers[result.taskId]?.add(result);

    if (result.error != null) {
      final task =
          _taskQueue.toList().firstWhereOrNull((t) => t.id == result.taskId);
      if (task != null && task.retryCount < task.maxRetries) {
        task.retryCount++;
        _taskQueue.add(task);

        _logger.d('Retrying task ${task.id}, attempt ${task.retryCount}');
      } else {
        _logger.d(
            'Task ${result.taskId} failed after ${task?.retryCount ?? 0} retries: ${result.error}');
      }
    }

    _updateIsolateStatus(isolate,
        isIdle: true, currentTaskId: null, taskStartTime: null);
    _assignTaskToIsolate(isolate);

    _manageIsolateCount();
  }

  void _assignTaskToIsolate(Isolate isolate) {
    if (_isShuttingDown) {
      _shutdownIsolate(isolate);
      return;
    }

    if (_taskQueue.isNotEmpty && _availableIsolates.containsKey(isolate)) {
      final task = _taskQueue.removeFirst();
      task.startTime = DateTime.now();
      _updateIsolateStatus(isolate,
          isIdle: false, currentTaskId: task.id, taskStartTime: task.startTime);
      _availableIsolates[isolate]?.send(task);
    }
  }

  void _updateIsolateStatus(Isolate isolate,
      {required bool isIdle, String? currentTaskId, DateTime? taskStartTime}) {
    final status = _isolateStatuses[isolate];
    if (status != null) {
      status.isIdle = isIdle;
      status.currentTaskId = currentTaskId;
      status.taskStartTime = taskStartTime;
    }
  }

  String addTask(Function function, List<dynamic> args, int priority,
      {int maxRetries = 3}) {
    final taskId = const Uuid().v4();
    _taskQueue
        .add(Task(taskId, function, args, priority, maxRetries: maxRetries));
    _logger.i('New Task Added To Queue: $taskId');
    _assignTasks();
    return taskId;
  }

  void _assignTasks() {
    final isolates = _availableIsolates.keys.toList();
    for (final isolate in isolates) {
      _assignTaskToIsolate(isolate);
    }
  }

  void _manageIsolateCount() {
    if (_taskQueue.length > isolateCount && isolateCount < maxIsolates) {
      isolateCount++;
      _spawnIsolate();
    }
  }

  void shutdown() {
    _isShuttingDown = true;
    _assignTasks();
  }

  void _shutdownIsolate(Isolate isolate) {
    isolate.kill(priority: Isolate.immediate);
    _availableIsolates.remove(isolate);
    _isolateStatuses.remove(isolate);
  }

  bool killTask(String taskId) {
    final isolateEntry = _isolateStatuses.entries
        .firstWhereOrNull((entry) => entry.value.currentTaskId == taskId);
    if (isolateEntry != null) {
      _shutdownIsolate(isolateEntry.key);
      _taskQueue.toList().removeWhere((task) => task.id == taskId);
      return true;
    } else {
      _logger.w('Task $taskId not found or not running.');
      return false;
    }
  }

  List<Map<String, dynamic>> getIsolateStatuses() {
    return _isolateStatuses.values.map((status) {
      return {
        'isolate': status.isolate,
        'isIdle': status.isIdle,
        'currentTaskId': status.currentTaskId,
        'taskStartTime': status.taskStartTime,
      };
    }).toList();
  }

  static void _isolateEntryPoint(SendPort mainSendPort) async {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    await for (final message in receivePort) {
      if (message is Task) {
        final startTime = DateTime.now();
        dynamic result;
        Exception? error;
        try {
          result = await Function.apply(message.function, message.args);
        } catch (e) {
          error = e as Exception;
          rethrow;
        }
        final duration = DateTime.now().difference(startTime);
        final memoryUsage = await _getMemoryUsage();
        mainSendPort
            .send(TaskResult(message.id, result, duration, memoryUsage, error));
      }
    }
  }

  static Future<int> _getMemoryUsage() async {
    final processInfo = ProcessInfo.currentRss;
    return processInfo;
  }
}
