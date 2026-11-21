import 'package:Kelivo/features/agent/orchestration/worktree_isolator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = '4e957c50fd2bb6863e12eb3e67460aa2d8ad3c78';
  AgentWorktreeLease lease(String agent, String file, {String sha = base}) =>
      AgentWorktreeLease(
        agentId: agent,
        branch: 'feat/$agent',
        worktreePath: '/mock/$agent',
        baseSha: sha,
        ownedFiles: [file],
      );

  test('disjoint ownership passes read-only integration preflight', () {
    final inspector = AgentWorktreeIsolator();
    inspector.register(lease('alpha', 'lib/alpha.dart'));
    inspector.register(lease('beta', 'lib/beta.dart'));
    expect(
      inspector
          .inspect(
            'alpha',
            changedFiles: ['lib/alpha.dart'],
            integrationChangedFiles: ['lib/beta.dart'],
          )
          .canIntegrate,
      isTrue,
    );
  });

  test('overlapping staged paths and cross-owner changes are blocked', () {
    final inspector = AgentWorktreeIsolator();
    inspector.register(lease('alpha', 'lib/alpha.dart'));
    inspector.register(lease('beta', 'lib/beta.dart'));
    final report = inspector.inspect(
      'alpha',
      changedFiles: ['lib/alpha.dart', 'lib/beta.dart'],
      integrationChangedFiles: ['lib/alpha.dart'],
    );
    expect(report.canIntegrate, isFalse);
    expect(report.conflicts, {'lib/alpha.dart', 'lib/beta.dart'});
    expect(report.outsideOwnership, {'lib/beta.dart'});
  });

  test('different base SHAs require explicit revalidation', () {
    final inspector = AgentWorktreeIsolator();
    inspector.register(lease('alpha', 'lib/alpha.dart'));
    expect(
      () => inspector.register(lease('beta', 'lib/beta.dart', sha: 'a' * 40)),
      throwsStateError,
    );
  });

  test('release has no implicit commit, merge or filesystem side effects', () {
    final inspector = AgentWorktreeIsolator();
    inspector.register(lease('alpha', 'lib/alpha.dart'));
    inspector.release('alpha');
    expect(
      () => inspector.inspect(
        'alpha',
        changedFiles: const [],
        integrationChangedFiles: const [],
      ),
      throwsStateError,
    );
  });
}
