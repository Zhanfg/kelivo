import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/workspace/runtime/environment_instance_layout_contract.dart';

void main() {
  EnvironmentInstanceLayout layout(String id) => EnvironmentInstanceLayout(
    instanceId: id,
    distribution: 'alpine',
    release: '3.20',
  );

  test('two instances have non-overlapping logical rootfs and snapshots', () {
    final first = layout('alpha');
    final second = layout('beta');
    expect(first.rootfsKey, isNot(second.rootfsKey));
    expect(first.snapshotIndexKey, isNot(second.snapshotIndexKey));
  });

  test('matching instance and release required for snapshot reference', () {
    final cat = EnvironmentInstanceCatalog([layout('alpha'), layout('beta')]);
    final snapshot = EnvironmentSnapshotReference(
      id: 'snapshot1',
      instanceId: 'alpha',
      sourceRelease: '3.20',
      contentDigest: 'a' * 64,
    );
    expect(cat.canRestore('alpha', snapshot), isTrue);
    expect(cat.canRestore('beta', snapshot), isFalse);
    expect(cat.canRestore('missing', snapshot), isFalse);
  });

  test('invalid paths, digest and duplicate IDs denied', () {
    expect(() => layout('../bad'), throwsArgumentError);
    expect(
      () => EnvironmentInstanceCatalog([layout('alpha'), layout('alpha')]),
      throwsArgumentError,
    );
    expect(
      () => EnvironmentSnapshotReference(
        id: 's',
        instanceId: 'alpha',
        sourceRelease: '3.20',
        contentDigest: 'not-a-digest',
      ),
      throwsArgumentError,
    );
  });

  test('catalog immutable, cannot trigger real filesystem operations', () {
    final source = <EnvironmentInstanceLayout>[layout('alpha')];
    final cat = EnvironmentInstanceCatalog(source);
    source.clear();
    expect(cat.instances.keys, {'alpha'});
    expect(() => cat.instances.clear(), throwsUnsupportedError);
  });
}
