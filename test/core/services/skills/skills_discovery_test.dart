import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/skills/skills_discovery.dart';

void main() {
  test('read-only discovery filters invalid and duplicate responses', () async {
    final client = SkillsDiscovery(
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
            'name': 'Duplicate',
            'source': 'vercel-labs/skills',
          },
          {'id': '../unsafe', 'name': 'Unsafe', 'source': 'unknown'},
        ],
      },
    );
    final found = await client.search('flutter');
    expect(found, hasLength(1));
    expect(found.single.slug, 'find-skills');
    expect(found.single.sourceVerified, isFalse);
    expect(found.single.installs, 42);
  });

  test('invalid owner fails closed before calling network', () async {
    var called = false;
    final client = SkillsDiscovery(fetch: (_) async {
      called = true;
      return <String, Object?>{'skills': []};
    });
    await expectLater(
      client.search('x', owner: '../../unsafe'),
      throwsA(isA<SkillDiscoveryException>()),
    );
    expect(called, isFalse);
  });
}