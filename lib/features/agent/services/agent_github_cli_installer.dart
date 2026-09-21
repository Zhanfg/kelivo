import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/services/workspace/workspace_runtime.dart';
import '../../../utils/app_directories.dart';
import 'agent_runtime_bootstrap.dart';

class AgentGithubCliInstallation {
  const AgentGithubCliInstallation({
    required this.version,
    required this.hostRoot,
    required this.guestRoot,
  });

  final String version;
  final String hostRoot;
  final String guestRoot;

  Mount asMount() => Mount(host: hostRoot, guest: guestRoot, readOnly: true);
}

class AgentGithubCliInstaller {
  AgentGithubCliInstaller({
    required this.runtimeBootstrap,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const String version = '2.101.0';
  static const String archiveName = 'gh_2.101.0_linux_arm64.tar.gz';
  static const String sha256sum =
      'b57e8063f18862647c9d22727c32e9da1b963f8bf9db648fe123a6975695640f';
  static const String guestRoot = '/kelivo-agent-tools';
  static const String _packageGuestRoot = '/kelivo-agent-package';
  static const String _environmentGuestRoot = '/kelivo-agent-env';

  static final Uri archiveUri = Uri.parse(
    'https://github.com/cli/cli/releases/download/v$version/$archiveName',
  );

  final AgentRuntimeBootstrap runtimeBootstrap;
  final http.Client _client;

  Future<AgentGithubCliInstallation> ensureInstalled({
    String environmentId = 'default',
  }) async {
    final handle = await runtimeBootstrap.ensureReady(
      environmentId: environmentId,
    );
    if (handle.arch != 'arm64') {
      throw StateError('github_cli_unsupported_arch:${handle.arch}');
    }

    final environmentDir = handle.environmentDir;
    final installDir = Directory(
      p.join(environmentDir.path, 'tools', 'github-cli', 'v$version'),
    );
    final executable = File(p.join(installDir.path, 'bin', 'gh'));
    final marker = File(p.join(installDir.path, '.kelivo-gh.json'));

    if (await _valid(executable, marker)) {
      return AgentGithubCliInstallation(
        version: version,
        hostRoot: installDir.path,
        guestRoot: guestRoot,
      );
    }

    final packageStore = await AppDirectories.getAgentPackageStoreDirectory();
    final packageDir = Directory(
      p.join(packageStore.path, 'tools', 'github-cli', 'v$version'),
    );
    await packageDir.create(recursive: true);
    final archive = File(p.join(packageDir.path, archiveName));
    await _ensureArchive(archive);

    final stagingName =
        '.gh-staging-$version-${const Uuid().v4().replaceAll('-', '')}';
    final staging = Directory(p.join(environmentDir.path, 'tools', stagingName));
    await staging.create(recursive: true);

    final guestStaging = '$_environmentGuestRoot/tools/$stagingName';
    final guestArchive = '$_packageGuestRoot/$archiveName';
    final guestInstall =
        '$_environmentGuestRoot/tools/github-cli/v$version';
    CommandExited? exit;
    final stderr = StringBuffer();
    final runId = 'gh-install-${const Uuid().v4()}';

    try {
      await for (final event in handle.runtime.run(
        CommandRequest(
          runId: runId,
          command:
              "set -eu; "
              "rm -rf ${_quote(guestStaging)}; "
              "mkdir -p ${_quote(guestStaging)}; "
              "tar -xzf ${_quote(guestArchive)} -C ${_quote(guestStaging)}; "
              "src=\$(find ${_quote(guestStaging)} -type f -path '*/bin/gh' -print -quit); "
              "test -n \"\$src\"; "
              "rm -rf ${_quote(guestInstall)}; "
              "mkdir -p ${_quote('$guestInstall/bin')}; "
              "cp \"\$src\" ${_quote('$guestInstall/bin/gh')}; "
              "chmod +x ${_quote('$guestInstall/bin/gh')}; "
              "${_quote('$guestInstall/bin/gh')} --version >/dev/null",
          cwd: '/',
          mounts: <Mount>[
            Mount(host: packageDir.path, guest: _packageGuestRoot, readOnly: true),
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
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }

    if (exit == null || exit.exitCode != 0 || !await executable.exists()) {
      final details = stderr.toString().trim();
      throw StateError(
        details.isEmpty ? 'github_cli_install_failed' : 'github_cli_install_failed:$details',
      );
    }

    await marker.writeAsString(
      jsonEncode(<String, Object>{
        'version': version,
        'sha256': sha256sum,
        'asset': archiveName,
      }),
      flush: true,
    );
    return AgentGithubCliInstallation(
      version: version,
      hostRoot: installDir.path,
      guestRoot: guestRoot,
    );
  }

  Future<bool> _valid(File executable, File marker) async {
    if (!await executable.exists() || !await marker.exists()) return false;
    try {
      final data =
          jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      return data['version'] == version &&
          data['sha256'] == sha256sum &&
          data['asset'] == archiveName;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureArchive(File archive) async {
    if (await archive.exists()) {
      if (await _sha256(archive) == sha256sum) return;
      await archive.delete();
    }
    final part = File('${archive.path}.part');
    if (await part.exists()) await part.delete();

    final response = await _client
        .send(http.Request('GET', archiveUri))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      await response.stream.drain<void>();
      throw HttpException(
        'GitHub CLI download HTTP ${response.statusCode}',
        uri: archiveUri,
      );
    }

    final sink = part.openWrite();
    try {
      await response.stream.timeout(const Duration(minutes: 2)).pipe(sink);
    } catch (_) {
      await sink.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
    if (await _sha256(part) != sha256sum) {
      await part.delete();
      throw StateError('github_cli_checksum_mismatch');
    }
    await part.rename(archive.path);
  }

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
  }

  static String _quote(String value) {
    if (value.contains('\u0000')) throw ArgumentError('NUL in shell argument');
    final escaped = value.replaceAll("'", "'\\''");
    return "'$escaped'";
  }
}
