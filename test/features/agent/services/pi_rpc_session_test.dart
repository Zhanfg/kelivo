import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';
import 'package:Kelivo/features/agent/services/pi_rpc_session.dart';

void main() {
  test('Pi RPC correlates responses and uses persistent stdin', () async {
    final runtime = _FakeStdioRuntime();
    runtime.onWrite = runtime.respondSuccess;
    final session = await PiRpcSession.start(
      runtime: runtime,
      executable: '/pi/pi',
      cwd: '/workspace',
      sessionDir: '/task/session',
      sessionName: 'Task',
    );

    expect(runtime.request?.keepStdinOpen, isTrue);
    expect(runtime.request?.timeout, Duration.zero);
    expect(runtime.request?.command, contains('--mode'));
    expect(runtime.request?.command, contains('rpc'));
    expect(runtime.writes.single['type'], 'set_session_name');
    runtime.writes.clear();

    final response = await session.prompt('hello');
    expect(response['success'], isTrue);
    expect(runtime.writes.single['type'], 'prompt');
    expect(runtime.writes.single['message'], 'hello');

    await session.close();
    expect(runtime.cancelled, isTrue);
  });

  test('Pi RPC splits only on LF and preserves chunked UTF-8', () async {
    final runtime = _FakeStdioRuntime();
    runtime.onWrite = runtime.respondSuccess;
    final session = await PiRpcSession.start(
      runtime: runtime,
      executable: '/pi/pi',
      cwd: '/workspace',
      sessionDir: '/task/session',
      sessionName: 'Task',
    );

    final received = <Map<String, dynamic>>[];
    final sub = session.events.listen(received.add);

    final record = jsonEncode(<String, dynamic>{
      'type': 'message_update',
      'text': 'A\u2028中文B',
    });
    final bytes = utf8.encode('$record\n');
    final split = bytes.indexOf(0xE4);
    runtime.emitBytes(bytes.sublist(0, split + 1));
    runtime.emitBytes(bytes.sublist(split + 1));

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single['text'], 'A\u2028中文B');

    await sub.cancel();
    await session.close();
  });
}

class _FakeStdioRuntime extends WorkspaceRuntime
    implements WorkspaceStdioRuntime {
  final StreamController<CommandEvent> _events =
      StreamController<CommandEvent>.broadcast();

  CommandRequest? request;
  bool cancelled = false;
  final List<Map<String, dynamic>> writes = <Map<String, dynamic>>[];
  void Function(Map<String, dynamic> message)? onWrite;

  @override
  Future<RuntimeStatus> status() async {
    return const RuntimeStatus(ready: true, engine: 'fake', sandboxed: true);
  }

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    this.request = request;
    scheduleMicrotask(() {
      _events.add(const CommandStarted(pid: 1));
    });
    return _events.stream;
  }

  @override
  Future<void> writeStdin(String runId, Uint8List data) async {
    final decoded = jsonDecode(utf8.decode(data));
    final message = (decoded as Map).cast<String, dynamic>();
    writes.add(message);
    onWrite?.call(message);
  }

  void respondSuccess(Map<String, dynamic> message) {
    emitJson(<String, dynamic>{
      'id': message['id'],
      'type': 'response',
      'command': message['type'],
      'success': true,
    });
  }

  void emitJson(Map<String, dynamic> message) {
    emitBytes(utf8.encode('${jsonEncode(message)}\n'));
  }

  void emitBytes(List<int> bytes) {
    _events.add(
      CommandOutput(OutputStreamKind.stdout, Uint8List.fromList(bytes)),
    );
  }

  @override
  Future<void> cancel(String runId) async {
    cancelled = true;
  }
}
