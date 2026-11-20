import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/agent/orchestration/worktree_isolator.dart';

void main() {
  const sha = '68242b42f2c788f97b77323968c857a61a3469dc';
  AgentWorktreeLease lease(String id, String path, String owned) =>
      AgentWorktreeLease(
        agentId: id,
        branch: 'feat/$id',
        worktreePath: '/worktrees/$path',
        baseSha: sha,
        ownedFiles: [owned],
      );

  test('unique isolated worktrees pass conflict preflight', () {
    final subject = AgentWorktreeIsolator();
    subject.register(lease('a', 'one', 'lib/a.dart'));
    subject.register(lease('b', 'two', 'lib/b.dart'));
    expect(
      subject
          .inspect(
            'a',
            changedFiles: ['lib/a.dart'],
            integrationChangedFiles: ['lib/z.dart'],
          )
          .canIntegrate,
      isTrue,
    );
  });

  test('duplicate agent, worktree and branch rejected', () {
    final subject = AgentWorktreeIsolator();
    subject.register(lease('a', 'one', 'lib/a.dart'));
    expect(
      () => subject.register(lease('a', 'two', 'lib/b.dart')),
      throwsStateError,
    );
    expect(
      () => subject.register(lease('b', 'one', 'lib/b.dart')),
      throwsStateError,
    );
  });

  test('overlapping files and unauthorized changes block integration', () {
    final subject = AgentWorktreeIsolator();
    subject.register(lease('a', 'one', 'lib/a.dart'));
    subject.register(lease('b', 'two', 'lib/b.dart'));
    final result = subject.inspect(
      'a',
      changedFiles: ['lib/b.dart', 'lib/a.dart'],
      integrationChangedFiles: ['lib/a.dart'],
    );
    expect(result.canIntegrate, isFalse);
    expect(result.conflicts, {'lib/b.dart', 'lib/a.dart'});
    expect(result.outsideOwnership, {'lib/b.dart'});
  });

  test('unsafe path and incomplete SHA rejected', () {
    expect(() => lease('x', '../bad', 'lib/a.dart'), throwsArgumentError);
    expect(() => lease('x', 'safe', '../bad'), throwsArgumentError);
    expect(
      () => AgentWorktreeLease(
        agentId: 'x',
        branch: 'x',
        worktreePath: '/tmp/x',
        baseSha: 'abc',
        ownedFiles: ['lib/a.dart'],
      ),
      throwsArgumentError,
    );
  });

  test('release permits a fresh lease and unknown lease fails', () {
    final subject = AgentWorktreeIsolator();
    subject.register(lease('a', 'one', 'lib/a.dart'));
    subject.release('a');
    subject.register(lease('a', 'one', 'lib/a.dart'));
    expect(() => subject.release('missing'), throwsStateError);
  });
}
