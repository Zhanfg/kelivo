import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../../core/services/workspace/workspace_runtime.dart';

class PiRpcSession {
  PiRpcSession._({required this._runtime, required this._runId});

  final WorkspaceStdioRuntime _runtime;
  final String _runId;
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final Completer<void> _started = Completer<void>();
  final Completer<void> _closed = Completer<void>();
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};

  StreamSubscription<CommandEvent>? _runtimeEvents;
  StreamSubscription<String>? _decodedStdout;
  String _lineBuffer = '';
  String _stderrTail = '';
  bool _closing = false;
  int? _exitCode;

  static const int _stderrLimit = 16 * 1024;

  Stream<Map<String, dynamic>> get events => _events.stream;
  Future<void> get closed => _closed.future;
  int? get exitCode => _exitCode;
  String get stderrTail => _stderrTail;

  static Future<PiRpcSession> start({
    required WorkspaceStdioRuntime runtime,
    required String executable,
    required String cwd,
    required String sessionDir,
    required String sessionName,
    String? appendSystemPrompt,
    List<String> skills = const <String>[],
    List<String> extraArgs = const <String>[],
    List<Mount> mounts = const <Mount>[],
    Map<String, String> environment = const <String, String>{},
    Duration startupTimeout = const Duration(seconds: 20),
  }) async {
    final runId = 'pi-rpc-${const Uuid().v4()}';
    final session = PiRpcSession._(runtime: runtime, runId: runId);
    session._decodedStdout = utf8.decoder
        .bind(session._stdout.stream)
        .listen(
          session._consumeText,
          onError: (Object error, StackTrace stack) {
            session._fail(error, stack);
          },
        );

    final arguments = <String>[
      executable,
      '--mode',
      'rpc',
      '--session-dir',
      sessionDir,
      '--name',
      sessionName,
      '--no-approve',
      if (appendSystemPrompt != null && appendSystemPrompt.isNotEmpty) ...[
        '--append-system-prompt',
        appendSystemPrompt,
      ],
      for (final skill in skills) ...['--skill', skill],
      ...extraArgs,
    ];
    final launch =
        'mkdir -p ${_quote(sessionDir)}; exec ${arguments.map(_quote).join(' ')}';

    session._runtimeEvents = runtime
        .run(
          CommandRequest(
            runId: runId,
            command: launch,
            cwd: cwd,
            mounts: mounts,
            env: environment,
            keepStdinOpen: true,
            timeout: Duration.zero,
            isCancelled: () => session._closing,
          ),
        )
        .listen(
          (event) {
            switch (event) {
              case CommandStarted():
                if (!session._started.isCompleted) {
                  session._started.complete();
                }
              case CommandOutput(kind: OutputStreamKind.stdout):
                if (!session._closing) session._stdout.add(event.bytes);
              case CommandOutput(kind: OutputStreamKind.stderr):
                session._recordStderr(event.bytes);
              case CommandExited():
                session._exitCode = event.exitCode;
                if (!session._started.isCompleted) {
                  session._started.completeError(
                    StateError(session._exitDescription()),
                  );
                }
                unawaited(session._finishProcess());
            }
          },
          onError: (Object error, StackTrace stack) {
            session._fail(error, stack);
          },
          onDone: () {
            if (!session._started.isCompleted) {
              session._started.completeError(
                StateError('Pi RPC process closed before startup'),
              );
            }
            unawaited(session._finishProcess());
          },
        );

    try {
      await session._started.future.timeout(startupTimeout);
      if (session._closing) {
        throw StateError('Pi RPC startup cancelled');
      }
      return session;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> send(
    Map<String, dynamic> command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_closing) throw StateError('Pi RPC session is closed');
    final id = command['id']?.toString() ?? const Uuid().v4();
    final payload = <String, dynamic>{...command, 'id': id};
    final completer = Completer<Map<String, dynamic>>();
    if (_pending.containsKey(id)) {
      throw StateError('Duplicate Pi RPC request id: $id');
    }
    _pending[id] = completer;

    try {
      await _write(payload);
    } catch (_) {
      _pending.remove(id);
      rethrow;
    }

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      throw TimeoutException('Pi RPC command timed out: ${command['type']}');
    }
  }

  Future<Map<String, dynamic>> prompt(
    String message, {
    String? streamingBehavior,
  }) {
    return send(<String, dynamic>{
      'type': 'prompt',
      'message': message,
      if (streamingBehavior != null) 'streamingBehavior': streamingBehavior,
    });
  }

  Future<Map<String, dynamic>> getState() {
    return send(const <String, dynamic>{'type': 'get_state'});
  }

  Future<void> abort() async {
    if (_closing) return;
    try {
      await send(const <String, dynamic>{
        'type': 'abort',
      }, timeout: const Duration(seconds: 10));
    } catch (_) {
      // Process cancellation below remains authoritative.
    }
  }

  Future<void> respondToExtensionUi(Map<String, dynamic> response) {
    return _write(response);
  }

  Future<void> _write(Map<String, dynamic> message) {
    final bytes = Uint8List.fromList(utf8.encode('${jsonEncode(message)}\n'));
    return _runtime.writeStdin(_runId, bytes);
  }

  void _consumeText(String chunk) {
    if (_closing) return;
    _lineBuffer += chunk;
    while (true) {
      final newline = _lineBuffer.indexOf('\n');
      if (newline < 0) break;
      var line = _lineBuffer.substring(0, newline);
      _lineBuffer = _lineBuffer.substring(newline + 1);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.trim().isEmpty) continue;
      _consumeLine(line);
    }
  }

  void _consumeLine(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('Pi RPC record is not an object');
      }
      final message = decoded.cast<String, dynamic>();
      if (message['type'] == 'response') {
        final id = message['id']?.toString();
        final pending = id == null ? null : _pending.remove(id);
        if (pending != null && !pending.isCompleted) {
          pending.complete(message);
          return;
        }
      }
      if (!_events.isClosed) _events.add(message);
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _recordStderr(List<int> bytes) {
    final next = '$_stderrTail${utf8.decode(bytes, allowMalformed: true)}';
    _stderrTail = next.length <= _stderrLimit
        ? next
        : next.substring(next.length - _stderrLimit);
  }

  String _exitDescription() {
    final suffix = _stderrTail.trim();
    final base = _exitCode == null
        ? 'Pi RPC exited'
        : 'Pi RPC exited with code $_exitCode';
    return suffix.isEmpty ? base : '$base: $suffix';
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (!_started.isCompleted) _started.completeError(error, stack);
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(error, stack);
    }
    _pending.clear();
    unawaited(close());
  }

  Future<void> _finishProcess() async {
    if (!_stdout.isClosed) await _stdout.close();
    if (_lineBuffer.isNotEmpty && !_closing) {
      final line = _lineBuffer.endsWith('\r')
          ? _lineBuffer.substring(0, _lineBuffer.length - 1)
          : _lineBuffer;
      _lineBuffer = '';
      if (line.trim().isNotEmpty) _consumeLine(line);
    }
    if (!_closing) {
      final error = StateError(_exitDescription());
      for (final pending in _pending.values) {
        if (!pending.isCompleted) pending.completeError(error);
      }
      _pending.clear();
    }
    await _closeStreams();
  }

  Future<void> close() async {
    if (_closing) {
      await _closed.future;
      return;
    }
    _closing = true;
    final error = StateError('Pi RPC session closed');
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    _pending.clear();

    try {
      await _runtime.cancel(_runId);
    } finally {
      if (!_stdout.isClosed) await _stdout.close();
      await _closeStreams();
    }
  }

  Future<void> _closeStreams() async {
    await _runtimeEvents?.cancel();
    await _decodedStdout?.cancel();
    if (!_events.isClosed) await _events.close();
    if (!_closed.isCompleted) _closed.complete();
  }

  static String _quote(String value) {
    if (value.contains('\u0000')) throw ArgumentError('NUL in shell argument');
    final escaped = value.replaceAll("'", "'\\''");
    return "'$escaped'";
  }
}
