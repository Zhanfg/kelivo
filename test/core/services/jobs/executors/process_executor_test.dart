import 'dart:async';
import 'dart:convert';

import 'package:Kelivo/core/services/jobs/executors/process_executor.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeProcess implements JobProcessPort {
  final StreamController<List<int>> out = StreamController();
  final StreamController<List<int>> err = StreamController();
  final Completer<int> result = Completer();
  int terminationRequests = 0;

  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Future<int> get exitCode => result.future;
  @override
  Future<void> requestTermination() async => terminationRequests++;

  Future<void> finish(int exit) async {
    await out.close();
    await err.close();
    result.complete(exit);
  }
}

final class FakeRuntime implements JobProcessRuntime {
  final process = FakeProcess();
  String? executable;
  List<String>? args;

  @override
  Future<JobProcessPort> start({
    required String executableRef,
    required List<String> arguments,
  }) async {
    executable = executableRef;
    args = arguments;
    return process;
  }
}

void main() {
  late FakeRuntime runtime;
  late ProcessJobAdapter adapter;
  setUp(() {
    runtime = FakeRuntime();
    adapter = ProcessJobAdapter(runtime: runtime, maxLogBytes: 12);
  });

  test('starts only via injected authorized runtime', () async {
    final handle = await adapter.start(
      executableRef: 'runtime:compile',
      arguments: ['--fast'],
    );
    expect(runtime.executable, 'runtime:compile');
    expect(runtime.args, ['--fast']);
    runtime.process.out.add(utf8.encode('stdout'));
    runtime.process.err.add(utf8.encode('stderr'));
    await runtime.process.finish(0);
    final receipt = await handle.finished;
    expect(receipt.outcome, ProcessJobOutcome.exited);
    expect(receipt.exitCode, 0);
    expect(receipt.stdout, 'stdout');
    expect(receipt.stderr, 'stderr');
  });

  test('nonzero process exit preserves output and failure result', () async {
    final handle = await adapter.start(executableRef: 'runtime:compiler');
    runtime.process.err.add(utf8.encode('compiler error'));
    await runtime.process.finish(7);
    final receipt = await handle.finished;
    expect(receipt.outcome, ProcessJobOutcome.failed);
    expect(receipt.exitCode, 7);
    expect(receipt.stderr, 'compiler err');
  });

  test('bounded stdout/stderr capture marks truncation', () async {
    final handle = await adapter.start(executableRef: 'runtime:compiler');
    runtime.process.out.add(utf8.encode('12345678901234567890'));
    await runtime.process.finish(0);
    final receipt = await handle.finished;
    expect(receipt.stdout, '123456789012');
    expect(receipt.truncated, isTrue);
  });

  test('cancellation is idempotent but never assumes outcome', () async {
    final handle = await adapter.start(executableRef: 'runtime:compiler');
    await handle.requestCancel();
    await handle.requestCancel();
    expect(runtime.process.terminationRequests, 1);
    await runtime.process.finish(0);
    expect((await handle.finished).outcome, ProcessJobOutcome.outcomeUnknown);
  });

  test('rejected executable and arguments never reach runtime', () async {
    expect(
      () => adapter.start(executableRef: '/bin/sh', arguments: ['-c', 'echo']),
      throwsArgumentError,
    );
    expect(
      () =>
          adapter.start(executableRef: 'runtime:test', arguments: ['x\u0000y']),
      throwsArgumentError,
    );
    expect(runtime.executable, isNull);
  });

  test('budget validation rejects unlimited output receipts', () {
    expect(
      () => ProcessJobAdapter(runtime: runtime, maxLogBytes: 1024 * 1024 + 1),
      throwsArgumentError,
    );
  });
}
