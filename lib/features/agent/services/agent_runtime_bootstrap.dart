import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/sandbox/channel_command_run.dart';
import '../../../core/services/sandbox/workspace_channel.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../utils/app_directories.dart';

/// KELIVO-owned execution environment for Agent mode.
///
/// Product code talks to this boundary, never to a user-configured Workspace
/// Linux installation. On Android the current compatibility engine is PRoot,
/// but the environment ownership, persistent HOME and filesystem contract do
/// not depend on PRoot and can be moved to a faster backend later.
class AgentRuntimeBootstrap {
  AgentRuntimeBootstrap({WorkspaceChannel? channel})
      : channel = channel ?? WorkspaceChannel();

  static const String runtimeVersion = 'wolfi-v1';
  static const String arm64Asset =
      'assets/agent_runtime/wolfi-arm64.tar.gz';

  final WorkspaceChannel channel;
  final Map<String, Future<AgentRuntimeHandle>> _pending =
      <String, Future<AgentRuntimeHandle>>{};

  Future<AgentRuntimeHandle> ensureReady({
    String environmentId = 'default',
  }) {
    return _pending.putIfAbsent(
      environmentId,
      () => _prepare(environmentId).whenComplete(
        () => _pending.remove(environmentId),
      ),
    );
  }

  Future<AgentRuntimeHandle> _prepare(String environmentId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('agent_managed_runtime_android_only');
    }

    final probe = await channel.probe();
    if (!probe.supported) {
      throw StateError(probe.reason ?? 'agent_runtime_unavailable');
    }
    final arch = switch (probe.abi) {
      'arm64-v8a' || 'arm64' => 'arm64',
      _ => throw UnsupportedError('agent_runtime_unsupported_abi:${probe.abi}'),
    };

    final environmentDir =
        await AppDirectories.agentEnvironmentDir(environmentId);
    final rootfsDir = Directory(p.join(environmentDir.path, 'rootfs'));
    final homeDir = Directory(p.join(environmentDir.path, 'home'));
    final tmpDir = Directory(p.join(environmentDir.path, 'tmp'));
    final marker = File(p.join(rootfsDir.path, '.kelivo-agent-runtime'));

    await homeDir.create(recursive: true);
    await tmpDir.create(recursive: true);
    final piAgentDir = Directory(p.join(homeDir.path, '.pi', 'agent'));
    await piAgentDir.create(recursive: true);
    final persistentModelsFile = File(p.join(piAgentDir.path, 'models.json'));
    if (!await persistentModelsFile.exists()) {
      await persistentModelsFile.writeAsString('{}', flush: true);
    }

    if (!await _validInstall(rootfsDir, marker)) {
      await _installEmbeddedRuntime(
        environmentDir: environmentDir,
        rootfsDir: rootfsDir,
        marker: marker,
        assetPath: arm64Asset,
      );
    }

    final runtime = AgentAndroidRuntime(
      channel: channel,
      rootfsDir: rootfsDir,
      homeDir: homeDir,
      tmpDir: tmpDir,
    );
    final status = await runtime.status();
    if (!status.ready) {
      throw StateError(status.reason ?? 'agent_runtime_healthcheck_failed');
    }

    return AgentRuntimeHandle(
      runtime: runtime,
      environmentDir: environmentDir,
      rootfsDir: rootfsDir,
      homeDir: homeDir,
      tmpDir: tmpDir,
      arch: arch,
    );
  }

  Future<bool> _validInstall(Directory rootfsDir, File marker) async {
    if (!await marker.exists()) return false;
    if ((await marker.readAsString()).trim() != runtimeVersion) return false;
    return File(p.join(rootfsDir.path, 'bin', 'sh')).existsSync() &&
        File(p.join(rootfsDir.path, 'usr', 'bin', 'env')).existsSync();
  }

  Future<void> _installEmbeddedRuntime({
    required Directory environmentDir,
    required Directory rootfsDir,
    required File marker,
    required String assetPath,
  }) async {
    final staging = Directory(p.join(environmentDir.path, '.rootfs-staging'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    final packageStore = await AppDirectories.getAgentPackageStoreDirectory();
    final runtimeStore = Directory(p.join(packageStore.path, 'runtime'));
    await runtimeStore.create(recursive: true);
    final archive = File(p.join(runtimeStore.path, 'wolfi-arm64.tar.gz'));

    if (!await archive.exists() || await archive.length() == 0) {
      ByteData data;
      try {
        data = await rootBundle.load(assetPath);
      } on FlutterError {
        throw StateError('agent_runtime_asset_missing');
      }
      await archive.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    try {
      await channel.extractRootfs(
        archivePath: archive.path,
        destDir: staging.path,
        format: 'tar.gz',
      );
      final shell = File(p.join(staging.path, 'bin', 'sh'));
      final env = File(p.join(staging.path, 'usr', 'bin', 'env'));
      final osRelease = File(p.join(staging.path, 'etc', 'os-release'));
      if (!await shell.exists() ||
          !await env.exists() ||
          !await osRelease.exists() ||
          !(await osRelease.readAsString()).contains('ID=wolfi')) {
        throw StateError('agent_runtime_invalid_image');
      }

      if (await rootfsDir.exists()) await rootfsDir.delete(recursive: true);
      await staging.rename(rootfsDir.path);
      await marker.writeAsString(runtimeVersion, flush: true);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }
}

class AgentRuntimeHandle {
  const AgentRuntimeHandle({
    required this.runtime,
    required this.environmentDir,
    required this.rootfsDir,
    required this.homeDir,
    required this.tmpDir,
    required this.arch,
  });

  final AgentAndroidRuntime runtime;
  final Directory environmentDir;
  final Directory rootfsDir;
  final Directory homeDir;
  final Directory tmpDir;
  final String arch;
}

/// Android compatibility implementation of the Agent execution contract.
///
/// The guest always sees a stable persistent HOME at /home/kelivo. Workspace,
/// skills and task state are mounted by the task runner. /tmp is runtime-owned.
class AgentAndroidRuntime implements WorkspaceStdioRuntime {
  AgentAndroidRuntime({
    required this.channel,
    required this.rootfsDir,
    required this.homeDir,
    required this.tmpDir,
  });

  final WorkspaceChannel channel;
  final Directory rootfsDir;
  final Directory homeDir;
  final Directory tmpDir;

  @override
  bool get supportsPty => false;

  @override
  bool get supportsSystemTerminal => false;

  @override
  Future<RuntimeStatus> status() async {
    if (!await rootfsDir.exists() ||
        !await File(p.join(rootfsDir.path, 'bin', 'sh')).exists()) {
      return const RuntimeStatus(
        ready: false,
        reason: 'agent_runtime_not_installed',
        engine: 'agent-compat',
        sandboxed: true,
      );
    }
    final probe = await channel.probe();
    if (!probe.supported) {
      return RuntimeStatus(
        ready: false,
        reason: probe.reason ?? 'agent_runtime_unavailable',
        engine: 'agent-compat',
        sandboxed: true,
      );
    }
    return const RuntimeStatus(
      ready: true,
      engine: 'agent-compat',
      sandboxed: true,
    );
  }

  List<Mount> _mounts(List<Mount> mounts) => <Mount>[
        Mount(host: homeDir.path, guest: '/home/kelivo'),
        ...mounts,
      ];

  Map<String, String> _env(Map<String, String> env) => <String, String>{
        'HOME': '/home/kelivo',
        'USER': 'kelivo',
        'LOGNAME': 'kelivo',
        'SHELL': '/bin/sh',
        'PATH':
            '/home/kelivo/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
        'LANG': 'C.UTF-8',
        ...env,
      };

  @override
  Stream<CommandEvent> run(CommandRequest request) async* {
    final status = await this.status();
    if (!status.ready) {
      throw StateError(status.reason ?? 'agent_runtime_unavailable');
    }
    yield* runChannelCommand(
      channel: channel,
      request: request,
      args: ExecArgs(
        runId: request.runId,
        rootfsDir: rootfsDir.path,
        tmpDir: tmpDir.path,
        cwd: request.cwd,
        command: request.command,
        timeoutMs: request.timeout.inMilliseconds,
        keepStdinOpen: request.keepStdinOpen,
        env: _env(request.env),
        binds: [
          for (final mount in _mounts(request.mounts))
            BindMount(
              host: mount.host,
              guest: mount.guest,
              readOnly: mount.readOnly,
            ),
        ],
        shell: '/bin/sh',
      ),
    );
  }

  @override
  Future<void> writeStdin(String runId, Uint8List data) =>
      channel.stdinWrite(runId, data);

  @override
  Future<void> cancel(String runId) async {
    await channel.cancel(runId);
  }

  @override
  Future<PtySession> openPty({
    required List<Mount> mounts,
    required String cwd,
    required Map<String, String> env,
    required int cols,
    required int rows,
  }) {
    throw UnsupportedError('Agent runtime does not expose an interactive PTY');
  }

  @override
  Future<void> openInSystemTerminal(String hostDir) {
    throw UnsupportedError('Agent runtime is not exposed as a system terminal');
  }

  @override
  Future<void> revealInFileManager(String hostPath) {
    throw UnsupportedError('Agent runtime filesystem is implementation detail');
  }
}
