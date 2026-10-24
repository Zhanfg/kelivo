import 'dart:io';

import 'package:path/path.dart' as p;

/// Crash-aware rootfs replacement without deleting an existing Agent install.
///
/// A previous rootfs may contain user-installed packages. Keep it intact until
/// a later, explicit migration/cleanup operation confirms it is disposable.
final class AgentRootfsSwap {
  const AgentRootfsSwap._();

  static Directory previous(Directory environmentDir) =>
      Directory(p.join(environmentDir.path, '.rootfs-previous'));

  static Directory failed(Directory environmentDir) =>
      Directory(p.join(environmentDir.path, '.rootfs-failed'));

  /// Recover a process death between moving the old rootfs out and installing
  /// the new one. Never discard or auto-promote an unverified staging tree.
  static Future<bool> restoreInterrupted({
    required Directory environmentDir,
    required Directory rootfsDir,
  }) async {
    final backup = previous(environmentDir);
    if (await rootfsDir.exists() || !await backup.exists()) return false;
    await backup.rename(rootfsDir.path);
    return true;
  }

  /// Activates an already validated, fully staged image. The version marker
  /// must be written inside staging BEFORE this call, so power loss immediately
  /// after the rename never leaves a partially marked rootfs.
  ///
  /// A preserved previous image blocks subsequent upgrades until a future
  /// migration/cleanup workflow explicitly handles it. Nothing is overwritten.
  static Future<bool> activate({
    required Directory environmentDir,
    required Directory rootfsDir,
    required Directory staging,
  }) async {
    if (!await staging.exists()) {
      throw StateError('agent_rootfs_staging_missing');
    }
    final backup = previous(environmentDir);
    if (await backup.exists()) {
      throw StateError('agent_rootfs_previous_install_preserved');
    }
    final hadPrevious = await rootfsDir.exists();
    if (hadPrevious) {
      await rootfsDir.rename(backup.path);
    }
    try {
      await staging.rename(rootfsDir.path);
    } catch (_) {
      if (hadPrevious && !await rootfsDir.exists() && await backup.exists()) {
        await backup.rename(rootfsDir.path);
      }
      rethrow;
    }
    return hadPrevious;
  }

  /// Restore the previous image if a newly activated image fails health checks.
  /// Keep the failed image for diagnosis rather than deleting its contents.
  static Future<void> rollBack({
    required Directory environmentDir,
    required Directory rootfsDir,
  }) async {
    final backup = previous(environmentDir);
    if (!await backup.exists()) {
      throw StateError('agent_rootfs_rollback_unavailable');
    }
    final failedDir = failed(environmentDir);
    if (await failedDir.exists()) {
      throw StateError('agent_rootfs_failed_image_preserved');
    }
    if (await rootfsDir.exists()) {
      await rootfsDir.rename(failedDir.path);
    }
    try {
      await backup.rename(rootfsDir.path);
    } catch (_) {
      if (await failedDir.exists() && !await rootfsDir.exists()) {
        await failedDir.rename(rootfsDir.path);
      }
      rethrow;
    }
  }
}
