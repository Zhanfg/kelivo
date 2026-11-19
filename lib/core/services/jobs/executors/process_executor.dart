import 'dart:async';
import 'dart:convert';

/// Runtime-owned process handle. The adapter never invokes OS shell APIs
/// directly; WorkspaceRuntime integration must supply this authorized port.
abstract interface class JobProcessPort {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  Future<void> requestTermination();
}

abstract interface class JobProcessRuntime {
  Future<JobProcessPort> start({
    required String executableRef,
    required List<String> arguments,
  });
}

enum ProcessJobOutcome { exited, failed, outcomeUnknown }

final class ProcessJobReceipt {
  const ProcessJobReceipt({
    required this.outcome,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.truncated,
  });

  final ProcessJobOutcome outcome;
  final int? exitCode;
  final String stdout;
  final String stderr;
  final bool truncated;
}

final class ProcessJobHandle {
  ProcessJobHandle(this.finished, this.requestCancel);
  final Future<ProcessJobReceipt> finished;
  final Future<void> Function() requestCancel;
}

/// Explicit per-job process adapter with bounded log capture.
final class ProcessJobAdapter {
  ProcessJobAdapter({required this.runtime, this.maxLogBytes = 8192}) {
    if (maxLogBytes < 1 || maxLogBytes > 1024 * 1024) {
      throw ArgumentError('Invalid process output budget');
    }
  }

  final JobProcessRuntime runtime;
  final int maxLogBytes;

  Future<ProcessJobHandle> start({
    required String executableRef,
    List<String> arguments = const [],
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9_.:-]{1,160}$').hasMatch(executableRef) ||
        arguments.length > 32 ||
        arguments.any(
          (value) => value.length > 4096 || value.contains('\u0000'),
        )) {
      throw ArgumentError('Unsafe process invocation receipt');
    }
    final port = await runtime.start(
      executableRef: executableRef,
      arguments: List.unmodifiable(arguments),
    );
    var cancellationRequested = false;
    var truncated = false;
    final stdoutChunks = <int>[];
    final stderrChunks = <int>[];

    Future<void> capture(
      Stream<List<int>> stream,
      List<int> destination,
    ) async {
      await for (final chunk in stream) {
        final capacity = maxLogBytes - destination.length;
        if (chunk.length > capacity) truncated = true;
        if (capacity > 0) {
          destination.addAll(chunk.take(capacity));
        }
      }
    }

    final stdoutDone = capture(port.stdout, stdoutChunks);
    final stderrDone = capture(port.stderr, stderrChunks);
    final result = () async {
      try {
        final code = await port.exitCode;
        await Future.wait([stdoutDone, stderrDone]);
        return ProcessJobReceipt(
          outcome: cancellationRequested
              ? ProcessJobOutcome.outcomeUnknown
              : code == 0
              ? ProcessJobOutcome.exited
              : ProcessJobOutcome.failed,
          exitCode: code,
          stdout: utf8.decode(stdoutChunks, allowMalformed: true),
          stderr: utf8.decode(stderrChunks, allowMalformed: true),
          truncated: truncated,
        );
      } catch (_) {
        return ProcessJobReceipt(
          outcome: ProcessJobOutcome.outcomeUnknown,
          exitCode: null,
          stdout: utf8.decode(stdoutChunks, allowMalformed: true),
          stderr: utf8.decode(stderrChunks, allowMalformed: true),
          truncated: truncated,
        );
      }
    }();

    return ProcessJobHandle(result, () async {
      if (cancellationRequested) return;
      cancellationRequested = true;
      try {
        await port.requestTermination();
      } catch (_) {
        // Cancellation acceptance is not proof of process termination.
      }
    });
  }
}
