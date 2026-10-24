import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/workspace/desktop_process_runtime.dart';
import 'package:Kelivo/core/services/workspace/workspace_runtime.dart';

class _SandboxRuntime extends WorkspaceRuntime {
  @override
  bool get supportsPty => true;

  @override
  Future<RuntimeStatus> status() async {
    return const RuntimeStatus(
      ready: true,
      engine: 'fake',
      sandboxed: true,
    );
  }

  @override
  Stream<CommandEvent> run(CommandRequest request) {
    return const Stream<CommandEvent>.empty();
  }

  @override
  Future<void> cancel(String runId) async {}
}

void main() {
  test('sandbox PTY availability does not imply a host file manager', () {
    final runtime = _SandboxRuntime();
    expect(runtime.supportsPty, isTrue);
    expect(runtime.supportsSystemTerminal, isFalse);
    expect(runtime.supportsFileManager, isFalse);
    expect(
      () => runtime.revealInFileManager('/guest/workspace'),
      throwsUnsupportedError,
    );
  });

  test('desktop host runtime advertises external host actions', () {
    final runtime = DesktopProcessRuntime();
    expect(runtime.supportsSystemTerminal, isTrue);
    expect(runtime.supportsFileManager, isTrue);
    expect(runtime.supportsPty, isFalse);
  });
}
