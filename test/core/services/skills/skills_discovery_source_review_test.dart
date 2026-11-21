import 'package:Kelivo/core/services/skills/skills_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

/// #76 catalog API is mocked; no online verification or installation.
void main() {
  test(
    'all untrusted search candidates need review and are de-duplicated',
    () async {
      final discovery = SkillsDiscovery(
        fetch: (_) async => {
          'skills': [
            {
              'id': 'vercel-labs/skills/find-skills',
              'name': 'Find Skills',
              'source': 'vercel-labs/skills',
              'installs': 42,
            },
            {
              'id': 'vercel-labs/skills/find-skills',
              'name': 'Duplicated',
              'source': 'another',
              'installs': 9999,
            },
            {
              'id': 'evil/../../outside',
              'name': 'Unsafe',
              'source': 'unknown',
              'installs': 10,
            },
          ],
        },
        clock: () => DateTime.utc(2026, 11, 21),
      );
      final result = await discovery.search('flutter');
      expect(result, hasLength(1));
      expect(result.single.sourceVerified, isFalse);
      expect(result.single.warning, isNotNull);
      expect(result.single.landingUrl.scheme, 'https');
      expect(result.single.landingUrl.host, 'skills.sh');
      expect(result.single.installs, 42);
      expect(result.single.foundAt.isUtc, isTrue);
    },
  );

  test(
    'unsafe dot-segment IDs remain a blocked acceptance gap',
    () async {
      // Existing SkillsDiscovery currently accepts evil/../outside because its
      // ID regex allows dot-only segments. Owner-file changes were not approved.
      final discovery = SkillsDiscovery(
        fetch: (_) async => {
          'skills': [
            {'id': 'evil/../outside', 'name': 'Unsafe', 'source': 'evil'},
          ],
        },
      );
      final candidates = await discovery.search('unsafe');
      expect(candidates, isEmpty);
    },
    skip:
        'NOT TESTED: existing SkillsDiscovery accepts dot-segment IDs; owner fix required',
  );

  test('invalid input fails before any network request', () async {
    var called = false;
    final discovery = SkillsDiscovery(
      fetch: (_) async {
        called = true;
        return <String, Object?>{'skills': []};
      },
    );
    await expectLater(
      discovery.search('   '),
      throwsA(isA<SkillDiscoveryException>()),
    );
    await expectLater(
      discovery.search('ok', owner: '../unsafe'),
      throwsA(isA<SkillDiscoveryException>()),
    );
    await expectLater(
      discovery.search('ok', limit: 0),
      throwsA(isA<SkillDiscoveryException>()),
    );
    expect(called, isFalse);
  });

  test(
    'network errors and malformed response are explicit, not empty success',
    () async {
      final failed = SkillsDiscovery(
        fetch: (_) async => throw StateError('offline'),
      );
      await expectLater(
        failed.search('flutter'),
        throwsA(isA<SkillDiscoveryException>()),
      );
      final malformed = SkillsDiscovery(
        fetch: (_) async => {'skills': 'unexpected'},
      );
      await expectLater(
        malformed.search('flutter'),
        throwsA(isA<SkillDiscoveryException>()),
      );
    },
  );

  test('result limit and query encoding are enforced', () async {
    Uri? requested;
    final discovery = SkillsDiscovery(
      fetch: (uri) async {
        requested = uri;
        return {
          'skills': [
            {'id': 'a/b/first', 'name': 'A', 'source': 'a/b', 'installs': -9},
            {'id': 'a/b/second', 'name': 'B', 'source': 'a/b', 'installs': 2},
          ],
        };
      },
    );
    final matches = await discovery.search(
      'nested query',
      owner: 'owner',
      limit: 1,
    );
    expect(requested!.queryParameters['q'], 'nested query');
    expect(requested!.queryParameters['owner'], 'owner');
    expect(matches, hasLength(1));
    expect(matches.single.installs, 0);
    expect(() => matches.clear(), throwsUnsupportedError);
  });
}
