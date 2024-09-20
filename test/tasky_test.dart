import 'dart:async';
import 'package:tasky/tasky.dart';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';

import 'package:logger/logger.dart';

class MockLogger extends Mock implements Logger {}

void main() {
  group('TaskyManager', () {
    late TaskyManager taskyManager;
    // ignore: unused_local_variable
    late MockLogger mockLogger;

    setUp(() {
      mockLogger = MockLogger();
      taskyManager = TaskyManager(isolateCount: 2, maxIsolates: 4);
    });

    tearDown(() {
      taskyManager.shutdown();
    });

    test('Should add a task to the queue and assign it to an isolate', () {
      var taskFunction = (int x) => x * 2;
      var args = [10];
      var priority = 1;

      var taskId = taskyManager.addTask(taskFunction, args, priority);

      expect(taskyManager.getIsolateStatuses().isNotEmpty, isTrue);
      expect(taskyManager.getResultStream(taskId), emits(isA<TaskResult>()));
    });

    test('Should execute tasks with correct priority order', () async {
      var task1Completed = Completer();
      var task2Completed = Completer();

      taskyManager.addTask((_) {
        Future.delayed(Duration(milliseconds: 200)).then((value) {
          task1Completed.complete();
        });
      }, [], 1);

      taskyManager.addTask((_) {
        Future.delayed(Duration(milliseconds: 100)).then((value) {
          task2Completed.complete();
        });
      }, [], 2);

      await task2Completed.future;
      expect(task2Completed.isCompleted, isTrue);
      expect(task1Completed.isCompleted, isFalse);

      await task1Completed.future;
      expect(task1Completed.isCompleted, isTrue);
    });

    test('Should retry a task when it fails, up to the max retries', () async {
      int attemptCount = 0;
      var taskId = taskyManager.addTask(() {
        attemptCount++;
        if (attemptCount < 3) throw Exception('Task failed');
        return 'Success';
      }, [], 1, maxRetries: 3);

      var resultStream = taskyManager.getResultStream(taskId);
      expectLater(
        resultStream,
        emitsInOrder([
          predicate<TaskResult>((result) =>
              result.error != null &&
              result.error.toString() == 'Exception: Task failed'),
          predicate<TaskResult>((result) =>
              result.error != null &&
              result.error.toString() == 'Exception: Task failed'),
          predicate<TaskResult>((result) => result.result == 'Success'),
        ]),
      );
    });

    test('Should properly shut down isolates when shutdown is called',
        () async {
      expect(taskyManager.isolateCount, equals(2));

      taskyManager.shutdown();

      await Future.delayed(Duration(seconds: 1));

      expect(taskyManager.getIsolateStatuses().isEmpty, isTrue);
    });

    test('Should manage the number of isolates dynamically based on task queue',
        () async {
      // Initially 2 isolates
      expect(taskyManager.isolateCount, equals(2));

      // Add many tasks to trigger isolate spawning
      for (var i = 0; i < 10; i++) {
        taskyManager.addTask(
            (_) async => await Future.delayed(Duration(milliseconds: 100)),
            [],
            1);
      }

      await Future.delayed(Duration(milliseconds: 200));

      expect(taskyManager.isolateCount, greaterThan(2));
      expect(taskyManager.isolateCount, lessThanOrEqualTo(4));
    });

    test('Should kill a task that is currently running', () async {
      var taskId = taskyManager.addTask(() async {
        await Future.delayed(Duration(seconds: 2));
        return 'Done';
      }, [], 1);

      await Future.delayed(Duration(milliseconds: 500));

      var killResult = taskyManager.killTask(taskId);
      expect(killResult, isTrue);

      // Verify task was killed and not completed
      var resultStream = taskyManager.getResultStream(taskId);
      expect(resultStream, neverEmits(isA<TaskResult>()));
    });
  });
}
