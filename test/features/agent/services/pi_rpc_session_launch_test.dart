import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/agent/services/pi_rpc_session.dart';

void main() {
  test('new sessions use RPC UI without restoring an unrelated history', () {
    final args = PiRpcSession.buildLaunchArguments(
      executable: '/opt/omp',
      sessionDir: '/kelivo-agent-task/pi-session',
      approvalMode: 'always-ask',
    );

    expect(args, containsAllInOrder(<String>[
      '--mode',
      'rpc-ui',
      '--session-dir',
      '/kelivo-agent-task/pi-session',
    ]));
    expect(args, isNot(contains('--continue')));
  });

  test('resuming uses an isolated transcript and interactive approval mode', () {
    final args = PiRpcSession.buildLaunchArguments(
      executable: '/opt/omp',
      sessionDir: '/kelivo-agent-task/pi-session',
      approvalMode: 'always-ask',
      resumeExisting: true,
      appendSystemPrompt: '/workspace/context.md',
      extraArgs: const <String>['--model', 'kelivo/current'],
    );

    expect(args, contains('--continue'));
    expect(args, containsAllInOrder(<String>[
      '--mode',
      'rpc-ui',
      '--session-dir',
      '/kelivo-agent-task/pi-session',
      '--continue',
      '--approval-mode',
      'always-ask',
    ]));
    expect(args, containsAllInOrder(<String>[
      '--append-system-prompt',
      '/workspace/context.md',
      '--model',
      'kelivo/current',
    ]));
  });
}
