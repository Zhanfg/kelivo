import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../utils/app_directories.dart';
import 'agent_engine_distribution.dart';
import 'agent_runtime_bootstrap.dart';

class AgentEngineInstallation {
  const AgentEngineInstallation({
    required this.engine,
    required this.version,
    required this.hostRoot,
    required this.guestRoot,
    required this.guestExecutable,
  });

  final String engine;
  final String version;
  final String hostRoot;
  final String guestRoot;
  final String guestExecutable;

  Mount asMount() => Mount(host: hostRoot, guest: guestRoot, readOnly: true);
}

class AgentEngineInstaller {
  AgentEngineInstaller({
    required this.runtimeBootstrap,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const String guestRoot = '/kelivo-agent-engine';
  static const String _environmentGuestRoot = '/kelivo-agent-env';

  final AgentRuntimeBootstrap runtimeBootstrap;
  final http.Client _client;

  Future<AgentEngineInstallation> ensureInstalled({
    String environmentId = 'default',
  }) async {
    final handle = await runtimeBootstrap.ensureReady(
      environmentId: environmentId,
    );
    final asset = AgentEngineDistribution.forLinuxArch(handle.arch);
    if (asset == null) {
      throw StateError('agent_engine_unsupported_arch:${handle.arch}');
    }

    final environmentDir = handle.environmentDir;
    final installDir = Directory(
      p.join(
        environmentDir.path,
        'engine',
        AgentEngineDistribution.engineName,
        'v${asset.version}',
      ),
    );
    final executable = File(p.join(installDir.path, 'omp'));
    final marker = File(p.join(installDir.path, '.kelivo-agent-engine.json'));

    if (await _validInstallation(
      executable: executable,
      marker: marker,
      asset: asset,
    )) {
      await _ensureExecutable(handle.runtime, environmentDir, executable);
      return _installation(asset, installDir);
    }

    final packageStore = await AppDirectories.getAgentPackageStoreDirectory();
    final packageDir = Directory(
      p.join(
        packageStore.path,
        'engine',
        AgentEngineDistribution.engineName,
        'v${asset.version}',
      ),
    );
    await packageDir.create(recursive: true);
    final packageFile = File(p.join(packageDir.path, asset.fileName));
    await _ensureBinary(asset, packageFile);

    final staging = Directory(
      p.join(
        environmentDir.path,
        'engine',
        '.staging-${asset.version}-${const Uuid().v4().replaceAll('-', '')}',
      ),
    );
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    final stagedExecutable = File(p.join(staging.path, 'omp'));
    await packageFile.copy(stagedExecutable.path);

    if (await installDir.exists()) await installDir.delete(recursive: true);
    await installDir.parent.create(recursive: true);
    await staging.rename(installDir.path);

    await marker.writeAsString(
      jsonEncode(<String, Object>{
        'engine': AgentEngineDistribution.engineName,
        'version': asset.version,
        'sha256': asset.sha256,
        'asset': asset.fileName,
      }),
      flush: true,
    );

    await _ensureExecutable(handle.runtime, environmentDir, executable);
    return _installation(asset, installDir);
  }

  Future<void> _ensureExecutable(
    WorkspaceStdioRuntime runtime,
    Directory environmentDir,
    File executable,
  ) async {
    if (!await executable.exists()) {
      throw StateError('agent_engine_executable_missing');
    }
    final relative = p.relative(executable.path, from: environmentDir.path);
    final guestPath = '$_environmentGuestRoot/${relative.replaceAll('\\', '/')}';
    CommandExited? exit;
    final stderr = StringBuffer();
    final runId = 'engine-chmod-${const Uuid().v4()}';
    await for (final event in runtime.run(
      CommandRequest(
        runId: runId,
        command:
            "chmod +x ${_quote(guestPath)} && "
            "${_quote(guestPath)} --version >/dev/null",
        cwd: '/',
        mounts: <Mount>[
          Mount(host: environmentDir.path, guest: _environmentGuestRoot),
        ],
        timeout: const Duration(seconds: 30),
      ),
    )) {
      switch (event) {
        case CommandOutput(kind: OutputStreamKind.stderr):
          if (stderr.length < 8192) {
            stderr.write(utf8.decode(event.bytes, allowMalformed: true));
          }
        case CommandExited():
          exit = event;
        default:
          break;
      }
    }
    if (exit == null || exit.exitCode != 0) {
      final details = stderr.toString().trim();
      throw StateError(
        details.isEmpty
            ? 'agent_engine_healthcheck_failed'
            : 'agent_engine_healthcheck_failed:$details',
      );
    }
  }

  Future<bool> _validInstallation({
    required File executable,
    required File marker,
    required AgentEngineAsset asset,
  }) async {
    if (!await executable.exists() || !await marker.exists()) return false;
    try {
      final data =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      if (data['engine'] != AgentEngineDistribution.engineName ||
          data['version'] != asset.version ||
          data['sha256'] != asset.sha256 ||
          data['asset'] != asset.fileName) {
        return false;
      }
      return await _sha256(executable) == asset.sha256;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureBinary(
    AgentEngineAsset asset,
    File destination,
  ) async {
    if (await destination.exists()) {
      final digest = await _sha256(destination);
      if (digest == asset.sha256) return;
      await destination.delete();
    }

    final part = File('${destination.path}.part');
    if (await part.exists()) await part.delete();
    await part.parent.create(recursive: true);

    final response = await _client
        .send(http.Request('GET', asset.uri))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      await response.stream.drain<void>();
      throw HttpException(
        'Agent engine download HTTP ${response.statusCode}',
        uri: asset.uri,
      );
    }

    final sink = part.openWrite();
    try {
      await response.stream.timeout(const Duration(minutes: 5)).pipe(sink);
    } catch (_) {
      await sink.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }

    final digest = await _sha256(part);
    if (digest != asset.sha256) {
      await part.delete();
      throw StateError('agent_engine_checksum_mismatch');
    }
    await part.rename(destination.path);
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  AgentEngineInstallation _installation(
    AgentEngineAsset asset,
    Directory installDir,
  ) {
    return AgentEngineInstallation(
      engine: AgentEngineDistribution.engineName,
      version: asset.version,
      hostRoot: installDir.path,
      guestRoot: guestRoot,
      guestExecutable: '$guestRoot/omp',
    );
  }

  static String _quote(String value) {
    if (value.contains('\u0000')) throw ArgumentError('NUL in shell argument');
    final escaped = value.replaceAll("'", "'\\''");
    return "'$escaped'";
  }
}
