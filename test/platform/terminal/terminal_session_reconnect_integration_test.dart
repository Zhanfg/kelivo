import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/workspace/terminal/terminal_session_manager.dart';

import '../../features/workspace/terminal/fake_workspace_runtime.dart';

/// W11/#51: in-process disconnect/reconnect behavior with a fake PTY.
/// Not a real Android background kill, persisted PTY or process restoration.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test(
    'reconnect to same in-memory session does not create a second PTY',
    () async {
      final runtime = FakeWorkspaceRuntime();
      final manager = TerminalSessionManager(setWakelock: (_) async {});
      addTearDown(() async {
        await manager.closeAll();
        manager.dispose();
      });
      final session = await manager.open(
        runtime: runtime,
        mounts: const [],
        cwd: '/workspace',
        workspaceId: 'workspace:one',
      );
      runtime.lastPty!.emitString('before disconnect');
      await settle();
      expect(session.terminal.buffer.getText(), contains('before disconnect'));

      // A UI detaching does not close the manager or the PTY.
      final reconnected = manager.findReusable(
        mounts: const [],
        cwd: '/workspace',
        workspaceId: 'workspace:one',
      );
      expect(identical(reconnected, session), isTrue);
      expect(runtime.ptys, hasLength(1));
      expect(
        reconnected!.terminal.buffer.getText(),
        contains('before disconnect'),
      );
      runtime.lastPty!.emitString('after reconnect');
      await settle();
      expect(
        reconnected.terminal.buffer.getText(),
        contains('after reconnect'),
      );
    },
  );

  test('different workspace identity never reuses another session', () async {
    final runtime = FakeWorkspaceRuntime();
    final manager = TerminalSessionManager(setWakelock: (_) async {});
    addTearDown(() async {
      await manager.closeAll();
      manager.dispose();
    });
    final first = await manager.open(
      runtime: runtime,
      mounts: const [],
      cwd: '/workspace',
      workspaceId: 'workspace:one',
    );
    expect(
      manager.findReusable(
        mounts: const [],
        cwd: '/workspace',
        workspaceId: 'workspace:other',
      ),
      isNull,
    );
    expect(manager.byId(first.id), same(first));
  });

  test(
    'explicit close prevents reconnect and closes PTY exactly once',
    () async {
      final runtime = FakeWorkspaceRuntime();
      final manager = TerminalSessionManager(setWakelock: (_) async {});
      addTearDown(() async {
        await manager.closeAll();
        manager.dispose();
      });
      final first = await manager.open(
        runtime: runtime,
        mounts: const [],
        cwd: '/workspace',
      );
      await manager.close(first.id);
      expect(first.isClosed, isTrue);
      expect(runtime.lastPty!.closed, isTrue);
      expect(manager.byId(first.id), isNull);
      expect(manager.findReusable(mounts: const [], cwd: '/workspace'), isNull);
      await manager.close(first.id);
      expect(runtime.ptys, hasLength(1));
    },
  );

  test(
    'PTY process exit cannot be interpreted as a resumable live session',
    () async {
      final runtime = FakeWorkspaceRuntime();
      final manager = TerminalSessionManager(setWakelock: (_) async {});
      addTearDown(() async {
        await manager.closeAll();
        manager.dispose();
      });
      final session = await manager.open(
        runtime: runtime,
        mounts: const [],
        cwd: '/workspace',
      );
      runtime.lastPty!.completeExit(137);
      await settle();
      expect(session.exited, isTrue);
      expect(session.exitCode, 137);
      expect(manager.findReusable(mounts: const [], cwd: '/workspace'), isNull);
    },
  );
}
