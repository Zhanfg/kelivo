import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/artifacts/artifact_manifest.dart';

/// SHA-256 of the empty input, used as a well-formed 64-char lowercase digest.
const String kEmptySha256 =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

const List<String> kRequiredJsonKeys = <String>[
  'schemaVersion',
  'id',
  'uri',
  'mimeType',
  'byteLength',
  'sha256Hex',
  'createdAt',
  'sourceId',
  'ownerScope',
  'ownerId',
];

ArtifactManifest buildManifest({
  String id = 'art-0001',
  String mimeType = 'text/markdown',
  int byteLength = 42,
  String sha256Hex = kEmptySha256,
  DateTime? createdAt,
  String sourceId = 'tool:workspace_write',
  ArtifactOwnerScope ownerScope = ArtifactOwnerScope.conversation,
  String ownerId = 'conv-7f3a',
  String? displayName,
}) {
  return ArtifactManifest(
    id: id,
    mimeType: mimeType,
    byteLength: byteLength,
    sha256Hex: sha256Hex,
    createdAt: createdAt ?? DateTime.utc(2026, 5, 4, 12, 34, 56, 789),
    sourceId: sourceId,
    ownerScope: ownerScope,
    ownerId: ownerId,
    displayName: displayName,
  );
}

Map<String, dynamic> buildJson() => buildManifest().toJson();

void main() {
  group('identity URI', () {
    test('renders the authority form with an empty path', () {
      final manifest = buildManifest();
      expect(manifest.uri, 'artifact://art-0001');

      final parsed = Uri.parse(manifest.uri);
      expect(parsed.scheme, 'artifact');
      expect(parsed.hasAuthority, isTrue);
      expect(parsed.userInfo, isEmpty);
      expect(parsed.host, 'art-0001');
      expect(parsed.hasPort, isFalse);
      expect(parsed.hasEmptyPath, isTrue);
      expect(parsed.hasQuery, isFalse);
      expect(parsed.hasFragment, isFalse);
    });

    test('parsed host equals the id, so the id survives every hop', () {
      for (final id in <String>[
        'a',
        '0',
        'art-0001',
        'a.b_c-d~e',
        '0123456789abcdef0123456789abcdef',
      ]) {
        final manifest = buildManifest(id: id);
        expect(manifest.uri, ArtifactManifest.uriPrefix + id);
        expect(Uri.parse(manifest.uri).host, id);
        expect(ArtifactManifest.uriFor(id), manifest.uri);
        expect(ArtifactManifest.idFromUri(manifest.uri), id);
      }
    });

    test('rejects the opaque form and any structural URI tail', () {
      expect(
        () => ArtifactManifest.idFromUri('artifact:art-0001'),
        throwsFormatException,
      );
      expect(
        () => ArtifactManifest.idFromUri('artifact:///art-0001'),
        throwsFormatException,
      );
      expect(
        () => ArtifactManifest.idFromUri('artifact://art-0001/extra'),
        throwsFormatException,
      );
      expect(
        () => ArtifactManifest.idFromUri('artifact://art-0001?x=1'),
        throwsFormatException,
      );
      expect(
        () => ArtifactManifest.idFromUri('artifact://art-0001#frag'),
        throwsFormatException,
      );
      expect(
        () => ArtifactManifest.idFromUri('file://art-0001'),
        throwsFormatException,
      );
      expect(
        () => ArtifactManifest.idFromUri('artifact://Art-1'),
        throwsFormatException,
      );
      expect(() => ArtifactManifest.uriFor('a/b'), throwsArgumentError);
    });
  });

  group('roundtrip', () {
    test('toJson emits the documented keys in order', () {
      final json = buildJson();
      expect(json.keys.toList(), kRequiredJsonKeys);
      expect(json['schemaVersion'], 1);
      expect(json['id'], 'art-0001');
      expect(json['uri'], 'artifact://art-0001');
      expect(json['mimeType'], 'text/markdown');
      expect(json['byteLength'], 42);
      expect(json['sha256Hex'], kEmptySha256);
      expect(json['createdAt'], '2026-05-04T12:34:56.789Z');
      expect(json['sourceId'], 'tool:workspace_write');
      expect(json['ownerScope'], 'conversation');
      expect(json['ownerId'], 'conv-7f3a');
      expect(json.containsKey('displayName'), isFalse);
    });

    test('fromJson(toJson()) restores an equal manifest', () {
      final original = buildManifest(displayName: 'notes.md');
      final restored = ArtifactManifest.fromJson(original.toJson());
      expect(restored, original);
      expect(restored.hashCode, original.hashCode);
      expect(restored.toJson(), original.toJson());
    });

    test('survives an encode/decode roundtrip through JSON text', () {
      final original = buildManifest(
        id: 'task-42-run-7',
        mimeType: 'application/pdf',
        byteLength: 1048576,
        ownerScope: ArtifactOwnerScope.task,
        ownerId: 'task-42',
        displayName: 'summary.pdf',
      );
      final encoded = jsonEncode(original.toJson());
      final decoded = ArtifactManifest.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(decoded, original);
      expect(decoded.toJson(), original.toJson());
    });

    test('roundtrips every owner scope by wire token, not index', () {
      for (final scope in ArtifactOwnerScope.values) {
        final manifest = buildManifest(ownerScope: scope);
        final json = manifest.toJson();
        expect(json['ownerScope'], scope.wireName);
        expect(json['ownerScope'], isA<String>());
        expect(ArtifactManifest.fromJson(json).ownerScope, scope);
      }
      expect(
        ArtifactOwnerScope.values.map((scope) => scope.wireName).toList(),
        <String>['conversation', 'workspace', 'task'],
      );
    });

    test('preserves microsecond precision and the UTC flag', () {
      final createdAt = DateTime.utc(2026, 12, 31, 23, 59, 59, 999, 123);
      final manifest = buildManifest(createdAt: createdAt);
      final json = manifest.toJson();
      expect(json['createdAt'], '2026-12-31T23:59:59.999123Z');

      final restored = ArtifactManifest.fromJson(json);
      expect(restored.createdAt.isUtc, isTrue);
      expect(restored.createdAt, createdAt);
    });

    test('returns a fresh map that cannot mutate the manifest', () {
      final manifest = buildManifest();
      final json = manifest.toJson();
      json['id'] = 'tampered';
      json['byteLength'] = -1;

      expect(manifest.id, 'art-0001');
      expect(manifest.byteLength, 42);
      expect(manifest.toJson()['id'], 'art-0001');
      expect(identical(manifest.toJson(), manifest.toJson()), isFalse);
    });
  });

  group('id validation', () {
    test('rejects path traversal, separators, query, and control chars', () {
      for (final id in <String>[
        '',
        '..',
        '../etc/passwd',
        'a..b',
        'a/b',
        'sub/dir/file',
        'a\\b',
        'a?token=secret',
        'a#fragment',
        'a\u0000b',
        'a\nb',
        'a\tb',
        'a b',
        'a%2Fb',
        '.hidden',
        '-leading',
        '_leading',
        'Art-1',
        'UPPER',
      ]) {
        expect(
          () => buildManifest(id: id),
          throwsArgumentError,
          reason: 'id should be rejected: ${jsonEncode(id)}',
        );
      }
    });

    test('accepts the unreserved identifier alphabet', () {
      for (final id in <String>['a', '0', 'A'.toLowerCase(), 'a.b_c-d~e']) {
        expect(buildManifest(id: id).id, id);
      }
    });
  });

  group('sha256Hex validation', () {
    test('requires exactly 64 lowercase hex characters', () {
      for (final digest in <String>[
        '',
        'abc',
        kEmptySha256.substring(0, 63),
        '${kEmptySha256}a',
        kEmptySha256.toUpperCase(),
        kEmptySha256.replaceFirst('e', 'g'),
        ' $kEmptySha256',
        '$kEmptySha256 ',
        '0x$kEmptySha256',
      ]) {
        expect(
          () => buildManifest(sha256Hex: digest),
          throwsArgumentError,
          reason: 'digest should be rejected: $digest',
        );
      }
      expect(buildManifest(sha256Hex: 'a' * 64).sha256Hex, 'a' * 64);
      expect(buildManifest(sha256Hex: '0' * 64).sha256Hex, '0' * 64);
    });
  });

  group('byteLength validation', () {
    test('accepts zero and rejects negatives', () {
      expect(buildManifest(byteLength: 0).byteLength, 0);
      expect(
        buildManifest(byteLength: 1099511627776).byteLength,
        1099511627776,
      );
      expect(() => buildManifest(byteLength: -1), throwsArgumentError);
      expect(() => buildManifest(byteLength: -1024), throwsArgumentError);
    });
  });

  group('mimeType validation', () {
    test('accepts lowercase type/subtype and rejects anything else', () {
      for (final mimeType in <String>[
        'text/plain',
        'application/pdf',
        'image/svg+xml',
      ]) {
        expect(buildManifest(mimeType: mimeType).mimeType, mimeType);
      }
      for (final mimeType in <String>[
        '',
        'text',
        'text/',
        '/plain',
        'TEXT/PLAIN',
        'text/plain; charset=utf-8',
        'text/plain charset',
        'text plain',
        'text//plain',
      ]) {
        expect(
          () => buildManifest(mimeType: mimeType),
          throwsArgumentError,
          reason: 'mimeType should be rejected: $mimeType',
        );
      }
    });
  });

  group('createdAt validation', () {
    test('rejects a local (non-UTC) instant', () {
      expect(
        () => buildManifest(createdAt: DateTime(2026, 5, 4, 12, 34, 56)),
        throwsArgumentError,
      );
    });

    test('accepts a local instant converted with toUtc()', () {
      final local = DateTime(2026, 5, 4, 12, 34, 56);
      final manifest = buildManifest(createdAt: local.toUtc());
      expect(manifest.createdAt.isUtc, isTrue);
      expect(manifest.createdAt, local);
      expect(manifest.toJson()['createdAt'], endsWith('Z'));
    });

    test('json requires an explicit offset and normalizes to Z', () {
      final json = buildJson();
      json['createdAt'] = '2026-05-04T12:34:56.789';
      expect(() => ArtifactManifest.fromJson(json), throwsFormatException);

      final offsetJson = buildJson();
      offsetJson['createdAt'] = '2026-05-04T12:34:56.789+02:00';
      final fromOffset = ArtifactManifest.fromJson(offsetJson);
      expect(fromOffset.createdAt.isUtc, isTrue);
      expect(fromOffset.createdAt, DateTime.utc(2026, 5, 4, 10, 34, 56, 789));
      expect(fromOffset.toJson()['createdAt'], '2026-05-04T10:34:56.789Z');

      final garbageJson = buildJson();
      garbageJson['createdAt'] = 'yesterday';
      expect(
        () => ArtifactManifest.fromJson(garbageJson),
        throwsFormatException,
      );
    });
  });

  group('displayName', () {
    test('is optional and omitted from json when null', () {
      final manifest = buildManifest();
      expect(manifest.displayName, isNull);
      expect(manifest.toJson().containsKey('displayName'), isFalse);
      expect(ArtifactManifest.fromJson(manifest.toJson()).displayName, isNull);
    });

    test('roundtrips a safe label without affecting identity', () {
      final manifest = buildManifest(displayName: 'Q3 report (draft) v2.md');
      final json = manifest.toJson();
      expect(json['displayName'], 'Q3 report (draft) v2.md');
      expect(ArtifactManifest.fromJson(json), manifest);

      final restored = ArtifactManifest.fromJson(json);
      expect(restored.id, manifest.id);
      expect(restored.uri, 'artifact://art-0001');
      expect(restored.uri, isNot(contains('Q3')));
    });

    test('rejects path separators, traversal, and control characters', () {
      for (final displayName in <String>[
        '',
        '   ',
        '.',
        '..',
        '../secret.md',
        'dir/secret.md',
        'dir\\secret.md',
        'a\u0000b',
        'a\nb',
        'C:secret',
        'report|1.md',
        'what?.md',
        'a<b>c',
        'n' * 256,
      ]) {
        expect(
          () => buildManifest(displayName: displayName),
          throwsArgumentError,
          reason: 'displayName should be rejected: $displayName',
        );
      }
    });
  });

  group('strict parsing', () {
    test('rejects unknown or wrongly typed schemaVersion', () {
      for (final version in <Object?>[2, 0, 3, 1.0, '1', null]) {
        final json = buildJson();
        json['schemaVersion'] = version;
        expect(
          () => ArtifactManifest.fromJson(json),
          throwsFormatException,
          reason: 'schemaVersion should be rejected: $version',
        );
      }

      final missing = buildJson()..remove('schemaVersion');
      expect(() => ArtifactManifest.fromJson(missing), throwsFormatException);
    });

    test('rejects unknown enum tokens for ownerScope', () {
      for (final scope in <Object?>[
        'folder',
        'Conversation',
        'WORKSPACE',
        'task ',
        '',
        1,
        null,
        <String, dynamic>{'scope': 'task'},
      ]) {
        final json = buildJson();
        json['ownerScope'] = scope;
        expect(
          () => ArtifactManifest.fromJson(json),
          throwsFormatException,
          reason: 'ownerScope should be rejected: $scope',
        );
      }
    });

    test('rejects every missing required key', () {
      for (final key in kRequiredJsonKeys) {
        final json = buildJson()..remove(key);
        expect(
          () => ArtifactManifest.fromJson(json),
          throwsFormatException,
          reason: 'missing key should be rejected: $key',
        );
      }
    });

    test('rejects unknown keys instead of dropping them', () {
      for (final key in <String>[
        'localPath',
        'path',
        'absolutePath',
        'url',
        'credential',
        'accessToken',
      ]) {
        final json = buildJson();
        json[key] = '/tmp/leak';
        expect(
          () => ArtifactManifest.fromJson(json),
          throwsFormatException,
          reason: 'unknown key should be rejected: $key',
        );
      }
    });

    test('rejects wrongly typed values', () {
      final cases = <String, Object?>{
        'id': 42,
        'uri': null,
        'mimeType': <String>['text/plain'],
        'byteLength': '42',
        'sha256Hex': 7,
        'createdAt': 1777894496,
        'sourceId': null,
        'ownerId': true,
        'displayName': null,
      };
      for (final entry in cases.entries) {
        final json = buildJson();
        json[entry.key] = entry.value;
        expect(
          () => ArtifactManifest.fromJson(json),
          throwsFormatException,
          reason: 'wrong type should be rejected: ${entry.key}',
        );
      }

      final fractional = buildJson()..['byteLength'] = 42.5;
      expect(
        () => ArtifactManifest.fromJson(fractional),
        throwsFormatException,
      );
    });

    test('rejects semantic violations carried in json', () {
      final negative = buildJson()..['byteLength'] = -5;
      expect(() => ArtifactManifest.fromJson(negative), throwsFormatException);

      final badDigest = buildJson()..['sha256Hex'] = 'ABC';
      expect(() => ArtifactManifest.fromJson(badDigest), throwsFormatException);

      final badId = buildJson()
        ..['id'] = '../escape'
        ..['uri'] = 'artifact://../escape';
      expect(() => ArtifactManifest.fromJson(badId), throwsFormatException);
    });

    test('rejects a uri that disagrees with the id', () {
      final mismatched = buildJson()..['uri'] = 'artifact://other';
      expect(
        () => ArtifactManifest.fromJson(mismatched),
        throwsFormatException,
      );

      final withPath = buildJson()..['uri'] = 'artifact://art-0001/extra';
      expect(() => ArtifactManifest.fromJson(withPath), throwsFormatException);

      final withQuery = buildJson()..['uri'] = 'artifact://art-0001?x=1';
      expect(() => ArtifactManifest.fromJson(withQuery), throwsFormatException);

      final localFile = buildJson()..['uri'] = 'file:///tmp/art-0001';
      expect(() => ArtifactManifest.fromJson(localFile), throwsFormatException);
    });
  });

  group('no local path or credential leakage', () {
    test('serialized manifest carries identity only', () {
      final manifest = buildManifest(
        sourceId: 'tool:workspace_write',
        ownerId: 'ws-1',
        ownerScope: ArtifactOwnerScope.workspace,
        displayName: 'report.md',
      );
      final encoded = jsonEncode(manifest.toJson());

      for (final fragment in <String>[
        '/tmp',
        '/home',
        '/Users',
        '/var/',
        'C:',
        'file://',
        'http://',
        'https://',
        '\\\\',
        'token',
        'secret',
        'password',
        'Bearer',
      ]) {
        expect(
          encoded.contains(fragment),
          isFalse,
          reason: 'serialized manifest leaked: $fragment',
        );
      }

      expect(
        manifest.toJson().keys.toSet(),
        kRequiredJsonKeys.toSet()..add('displayName'),
      );
      expect(manifest.uri, 'artifact://art-0001');
      expect(Uri.parse(manifest.uri).hasQuery, isFalse);
      expect(Uri.parse(manifest.uri).userInfo, isEmpty);

      final printed = manifest.toString();
      for (final fragment in <String>['/tmp', 'file://', 'secret']) {
        expect(printed.contains(fragment), isFalse);
      }
    });
  });

  group('value semantics', () {
    test('equal fields give equal manifests and distinct ones differ', () {
      final first = buildManifest(displayName: 'a.md');
      final second = buildManifest(displayName: 'a.md');
      expect(first, second);
      expect(first.hashCode, second.hashCode);

      expect(first, isNot(buildManifest(displayName: 'b.md')));
      expect(first, isNot(buildManifest(displayName: null)));
      expect(first, isNot(buildManifest(id: 'art-0002')));
      expect(first, isNot(buildManifest(ownerScope: ArtifactOwnerScope.task)));
      expect(first, isNot(buildManifest(byteLength: 43)));
    });
  });
}
