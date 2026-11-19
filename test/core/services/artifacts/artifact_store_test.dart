import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/artifacts/artifact_manifest.dart';
import 'package:Kelivo/core/services/artifacts/artifact_store.dart';

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('artifact-'));
  tearDown(() async => root.delete(recursive: true));

  ArtifactManifest manifest(List<int> data, {String id = 'test-1'}) =>
      ArtifactManifest(
        id: id,
        mimeType: 'application/octet-stream',
        byteLength: data.length,
        sha256Hex: sha256.convert(data).toString(),
        createdAt: DateTime.utc(2026),
        sourceId: 'test',
        ownerScope: ArtifactOwnerScope.task,
        ownerId: 'task1',
      );

  test(
    'publish streaming chunks and reopen with digest verification',
    () async {
      final bytes = [1, 2, 3, 4, 5];
      final store = ArtifactStore(root);
      await store.publish(
        manifest(bytes),
        Stream.fromIterable([
          [1, 2],
          [3, 4, 5],
        ]),
      );
      final result = <int>[];
      await for (final chunk in await store.openVerified(manifest(bytes))) {
        result.addAll(chunk);
      }
      expect(result, bytes);
      await expectLater(
        store.publish(manifest(bytes), Stream.value(bytes)),
        throwsStateError,
      );
    },
  );

  test('invalid hash or short stream leaves no artifact', () async {
    final store = ArtifactStore(root);
    final wanted = manifest([1, 2, 3]);
    await expectLater(
      store.publish(wanted, Stream.value([1, 2])),
      throwsFormatException,
    );
    await expectLater(
      store.publish(wanted, Stream.value([4, 5, 6])),
      throwsFormatException,
    );
    expect(root.listSync().whereType<File>(), isEmpty);
  });

  test('budget, corruption and symlink rejected', () async {
    final bytes = [1, 2, 3];
    final small = ArtifactStore(root, maxBytes: 2);
    await expectLater(
      small.publish(manifest(bytes), Stream.value(bytes)),
      throwsArgumentError,
    );
    final store = ArtifactStore(root);
    await store.publish(manifest(bytes), Stream.value(bytes));
    final file = File('${root.path}/test-1.artifact');
    await file.writeAsBytes([9, 8, 7]);
    await expectLater(
      store.openVerified(manifest(bytes)),
      throwsFormatException,
    );
  });
}
