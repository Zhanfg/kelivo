import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/providers/environment_provider.dart';
import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../utils/app_directories.dart';
import 'pi_distribution.dart';

class PiInstallation {
  const PiInstallation({
    required this.version,
    required this.hostRoot,
    required this.guestRoot,
    required this.guestExecutable,
  });

  final String version;
  final String hostRoot;
  final String guestRoot;
  final String guestExecutable;

  Mount asMount() => Mount(host: hostRoot, guest: guestRoot, readOnly: true);
}

class PiBinaryInstaller {
  PiBinaryInstaller({
    required this.runtimeProvider,
    required this.environment,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const String guestRoot = '/kelivo-agent-pi';
  static const String _packageGuestRoot = '/kelivo-agent-package';
  static const String _environmentGuestRoot = '/kelivo-agent-env';

  final WorkspaceRuntimeProvider runtimeProvider;
  final EnvironmentProvider environment;
  final http.Client _client;

  Future<PiInstallation> ensureInstalled({
    String environmentId = 'default',
  }) async {
    await environment.loaded;
    await runtimeProvider.initialization;

    final runtime = runtimeProvider.runtime;
    if (runtime == null) {
      throw StateError('agent_runtime_unavailable');
    }
    final status = await runtime.status();
    if (!status.ready) {
      throw StateError(status.reason ?? 'agent_environment_not_ready');
    }
    if (!status.sandboxed) {
      throw UnsupportedError('pi_managed_install_requires_sandbox');
    }

    final asset = PiDistribution.forLinuxArch(environment.state.arch);
    if (asset == null) {
      throw StateError(
        'pi_unsupported_arch:' + (environment.state.arch ?? 'unknown'),
      );
    }

    final environmentDir = await AppDirectories.agentEnvironmentDir(
      environmentId,
    );
    final installDir = Directory(
      p.join(environmentDir.path, 'pi', 'v' + asset.version),
    );
    final executable = File(
      p.join(installDir.path, asset.executableRelativePath),
    );
    final marker = File(p.join(installDir.path, '.kelivo-pi.json'));

    if (await _validInstallation(
      executable: executable,
      marker: marker,
      asset: asset,
    )) {
      return _installation(asset.version, installDir);
    }

    final packageStore = await AppDirectories.getAgentPackageStoreDirectory();
    final packageDir = Directory(
      p.join(packageStore.path, 'pi', 'v' + asset.version),
    );
    await packageDir.create(recursive: true);
    final archive = File(p.join(packageDir.path, asset.archiveFileName));
    await _ensureArchive(asset, archive);

    final piRoot = Directory(p.join(environmentDir.path, 'pi'));
    await piRoot.create(recursive: true);
    final stagingName =
        '.staging-v' +
        asset.version +
        '-' +
        const Uuid().v4().replaceAll('-', '');
    final stagingDir = Directory(p.join(piRoot.path, stagingName));
    if (await stagingDir.exists()) {
      await stagingDir.delete(recursive: true);
    }

    final guestStaging = '$_environmentGuestRoot/pi/$stagingName';
    final guestArchive = '$_packageGuestRoot/${asset.archiveFileName}';
    final runId = 'pi-install-${const Uuid().v4()}';
    final stderr = StringBuffer();
    CommandExited? exit;

    try {
      await for (final event in runtime.run(
        CommandRequest(
          runId: runId,
          command:
              "set -eu; "
              "rm -rf ${_quote(guestStaging)}; "
              "mkdir -p ${_quote(guestStaging)}; "
              "tar -xzf ${_quote(guestArchive)} -C ${_quote(guestStaging)}; "
              "chmod +x ${_quote('$guestStaging/pi/pi')}; "
              "test -x ${_quote('$guestStaging/pi/pi')}",
          cwd: '/',
          mounts: <Mount>[
            Mount(
              host: packageDir.path,
              guest: _packageGuestRoot,
              readOnly: true,
            ),
            Mount(host: environmentDir.path, guest: _environmentGuestRoot),
          ],
          timeout: const Duration(minutes: 2),
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
    } catch (_) {
      await runtime.cancel(runId);
      rethrow;
    }

    if (exit == null || exit.exitCode != 0) {
      if (await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }
      final details = stderr.toString().trim();
      throw StateError(
        details.isEmpty ? 'pi_extract_failed' : 'pi_extract_failed:$details',
      );
    }

    if (await installDir.exists()) {
      await installDir.delete(recursive: true);
    }
    await stagingDir.rename(installDir.path);
    await marker.writeAsString(
      jsonEncode(<String, Object>{
        'version': asset.version,
        'sha256': asset.sha256,
        'asset': asset.archiveFileName,
      }),
      flush: true,
    );

    if (!await executable.exists()) {
      throw StateError('pi_executable_missing_after_extract');
    }
    return _installation(asset.version, installDir);
  }

  Future<bool> _validInstallation({
    required File executable,
    required File marker,
    required PiReleaseAsset asset,
  }) async {
    if (!await executable.exists() || !await marker.exists()) return false;
    try {
      final data =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      return data['version'] == asset.version &&
          data['sha256'] == asset.sha256 &&
          data['asset'] == asset.archiveFileName;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureArchive(PiReleaseAsset asset, File archive) async {
    if (await archive.exists()) {
      final digest = await _sha256(archive);
      if (digest == asset.sha256) return;
      await archive.delete();
    }

    final part = File(archive.path + '.part');
    if (await part.exists()) await part.delete();
    await part.parent.create(recursive: true);

    final request = http.Request('GET', asset.uri);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw HttpException(
        'Pi download HTTP ' + response.statusCode.toString(),
        uri: asset.uri,
      );
    }

    final sink = part.openWrite();
    try {
      await response.stream.timeout(const Duration(seconds: 30)).pipe(sink);
    } catch (_) {
      await sink.close();
      rethrow;
    }

    final digest = await _sha256(part);
    if (digest != asset.sha256) {
      await part.delete();
      throw StateError('pi_checksum_mismatch');
    }
    await part.rename(archive.path);
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  PiInstallation _installation(String version, Directory installDir) {
    return PiInstallation(
      version: version,
      hostRoot: installDir.path,
      guestRoot: guestRoot,
      guestExecutable: '$guestRoot/pi/pi',
    );
  }

  static String _quote(String value) {
    if (value.contains('\u0000')) throw ArgumentError('NUL in shell argument');
    return "'" + value.replaceAll("'", "'\\''") + "'";
  }
}
