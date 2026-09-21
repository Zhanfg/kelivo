class AgentEngineAsset {
  const AgentEngineAsset({
    required this.version,
    required this.platform,
    required this.arch,
    required this.uri,
    required this.sha256,
    required this.fileName,
  });

  final String version;
  final String platform;
  final String arch;
  final Uri uri;
  final String sha256;
  final String fileName;
}

/// KELIVO Agent uses Oh My Pi as its coding-agent execution engine.
///
/// The large standalone executable is deliberately downloaded on first Agent
/// use and cached outside the APK. This keeps the mobile package small while
/// giving the managed runtime OMP's task/subagent/job/worktree tool layer.
abstract final class AgentEngineDistribution {
  static const String engineName = 'omp';
  static const String version = '18.2.7';

  static final AgentEngineAsset linuxMuslArm64 = AgentEngineAsset(
    version: version,
    platform: 'linux-musl',
    arch: 'arm64',
    uri: Uri.parse(
      'https://github.com/can1357/oh-my-pi/releases/download/v$version/'
      'omp-linux-musl-arm64',
    ),
    sha256: 'aaaeb6821a1cebc4c2203e616cec949ff8b760a61f3ae8dfd98f32ef24eca983',
    fileName: 'omp-linux-musl-arm64',
  );

  static AgentEngineAsset? forLinuxArch(String? arch) => switch (arch) {
    'arm64' => linuxMuslArm64,
    _ => null,
  };
}
