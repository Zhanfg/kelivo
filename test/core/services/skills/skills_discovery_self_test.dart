import "dart:io";
import '../../../../lib/core/services/skills/skills_discovery.dart';

Future<void> main() async {
  final now = DateTime.utc(2026, 11, 18);
  var calls = 0;
  final client = SkillsDiscovery(
    clock: () => now,
    fetch: (uri) async {
      calls++;
      assert(uri.scheme == 'https');
      assert(uri.host == 'skills.sh');
      assert(uri.queryParameters['q'] == 'flutter');
      assert(uri.queryParameters['owner'] == 'vercel-labs');
      return <String, Object?>{
        'skills': [
          {'id': 'vercel-labs/skills/find-skills', 'name': 'find-skills',
           'source': 'vercel-labs/skills', 'installs': 42},
          {'id': 'vercel-labs/skills/find-skills', 'name': 'duplicate',
           'source': 'vercel-labs/skills', 'installs': 1},
          {'id': '../unsafe', 'name': 'unsafe', 'source': 'x', 'installs': 99},
        ],
      };
    },
  );
  final found = await client.search(' flutter ', owner: 'vercel-labs');
  assert(calls == 1);
  assert(found.length == 1);
  assert(found.single.slug == 'find-skills');
  assert(found.single.installs == 42);
  assert(!found.single.sourceVerified);
  assert(found.single.landingUrl.host == 'skills.sh');
  assert(found.single.foundAt == now);
  try {
    found.add(found.first);
    throw StateError('results must be immutable');
  } on UnsupportedError {
    // Expected.
  }
  for (final invalid in <String>['', '   ']) {
    try {
      await client.search(invalid);
      throw StateError('expected invalid query');
    } on SkillDiscoveryException catch (e) {
      assert(e.code == 'invalid_query');
    }
  }
  try {
    await client.search('flutter', owner: '../../evil');
    throw StateError('expected invalid owner');
  } on SkillDiscoveryException catch (e) {
    assert(e.code == 'invalid_owner');
  }
  try {
    await SkillsDiscovery(fetch: (_) async => {'x': true}).search('test');
    throw StateError('expected invalid response');
  } on SkillDiscoveryException catch (e) {
    assert(e.code == 'invalid_response');
  }
  try {
    await SkillsDiscovery(fetch: (_) async {
      throw const SocketException('offline');
    }).search('test');
    throw StateError('expected network error');
  } on SkillDiscoveryException catch (e) {
    assert(e.code == 'network_error');
  }
  print('skills_discovery self-test: PASS');
}