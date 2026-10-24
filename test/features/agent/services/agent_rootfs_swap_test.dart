import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:Kelivo/features/agent/services/agent_rootfs_swap.dart';

void main() {
  late Directory temp;
  late Directory rootfs;
  late Directory staging;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kelivo-agent-rootfs-');
    rootfs = Directory(p.join(temp.path, 'rootfs'));
    staging = Directory(p.join(temp.path, '.rootfs-staging'));
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> put(Directory dir, String name, String contents) async {
    await dir.create(recursive: true);
    await File(p.join(dir.path, name)).writeAsString(contents, flush: true);
  }

  test('first install is staged, with no previous image', () async {
    await put(staging, '.kelivo-agent-runtime', 'wolfi-v1');
    expect(
      await AgentRootfsSwap.activate(
        environmentDir: temp,
        rootfsDir: rootfs,
        staging: staging,
      ),
      isFalse,
    );
    expect(
      await File(p.join(rootfs.path, '.kelivo-agent-runtime')).readAsString(),
      'wolfi-v1',
    );
    expect(await AgentRootfsSwap.previous(temp).exists(), isFalse);
  });

  test('upgrade retains all previously installed guest packages', () async {
    await put(rootfs, 'user-installed-package', 'important data');
    await put(staging, '.kelivo-agent-runtime', 'wolfi-v2');
    expect(
      await AgentRootfsSwap.activate(
        environmentDir: temp,
        rootfsDir: rootfs,
        staging: staging,
      ),
      isTrue,
    );
    expect(
      await File(
        p.join(AgentRootfsSwap.previous(temp).path, 'user-installed-package'),
      ).readAsString(),
      'important data',
    );
    expect(
      await File(p.join(rootfs.path, '.kelivo-agent-runtime')).readAsString(),
      'wolfi-v2',
    );
  });

  test(
    'power loss during rename restores previous rootfs on next startup',
    () async {
      await put(
        AgentRootfsSwap.previous(temp),
        'user-installed-package',
        'important data',
      );
      expect(
        await AgentRootfsSwap.restoreInterrupted(
          environmentDir: temp,
          rootfsDir: rootfs,
        ),
        isTrue,
      );
      expect(
        await File(
          p.join(rootfs.path, 'user-installed-package'),
        ).readAsString(),
        'important data',
      );
      expect(await AgentRootfsSwap.previous(temp).exists(), isFalse);
    },
  );

  test(
    'another upgrade refuses to discard the preserved old installation',
    () async {
      await put(rootfs, 'current', 'current files');
      await put(staging, 'upgrade', 'new files');
      await put(AgentRootfsSwap.previous(temp), 'old', 'keep me');
      await expectLater(
        AgentRootfsSwap.activate(
          environmentDir: temp,
          rootfsDir: rootfs,
          staging: staging,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        await File(p.join(rootfs.path, 'current')).readAsString(),
        'current files',
      );
      expect(
        await File(
          p.join(AgentRootfsSwap.previous(temp).path, 'old'),
        ).readAsString(),
        'keep me',
      );
    },
  );

  test('failed health check rolls back and preserves failed image', () async {
    await put(rootfs, 'installed-package', 'previous environment');
    await put(staging, 'new', 'broken environment');
    await AgentRootfsSwap.activate(
      environmentDir: temp,
      rootfsDir: rootfs,
      staging: staging,
    );
    await AgentRootfsSwap.rollBack(environmentDir: temp, rootfsDir: rootfs);
    expect(
      await File(p.join(rootfs.path, 'installed-package')).readAsString(),
      'previous environment',
    );
    expect(
      await File(
        p.join(AgentRootfsSwap.failed(temp).path, 'new'),
      ).readAsString(),
      'broken environment',
    );
    expect(await AgentRootfsSwap.previous(temp).exists(), isFalse);
  });

  test('recovery never overwrites an already-active rootfs', () async {
    await put(rootfs, 'current', 'keep current');
    await put(AgentRootfsSwap.previous(temp), 'previous', 'keep previous');
    expect(
      await AgentRootfsSwap.restoreInterrupted(
        environmentDir: temp,
        rootfsDir: rootfs,
      ),
      isFalse,
    );
    expect(
      await File(p.join(rootfs.path, 'current')).readAsString(),
      'keep current',
    );
    expect(
      await File(
        p.join(AgentRootfsSwap.previous(temp).path, 'previous'),
      ).readAsString(),
      'keep previous',
    );
  });
}
