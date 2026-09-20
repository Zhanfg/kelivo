class PiReleaseAsset {
  const PiReleaseAsset({
    required this.version,
    required this.platform,
    required this.arch,
    required this.uri,
    required this.sha256,
    required this.archiveFileName,
  });

  final String version;
  final String platform;
  final String arch;
  final Uri uri;
  final String sha256;
  final String archiveFileName;

  String get executableRelativePath => 'pi/pi';
}

abstract final class PiDistribution {
  static const String version = '0.85.1';

  static final PiReleaseAsset linuxArm64 = PiReleaseAsset(
    version: version,
    platform: 'linux',
    arch: 'arm64',
    uri: Uri.parse(
      'https://github.com/earendil-works/pi/releases/download/v$version/'
      'pi-linux-arm64.tar.gz',
    ),
    sha256: '042d20ae885ee4f3b102815f3280b962c377b2e9fb44de4037908cc530eae4d4',
    archiveFileName: 'pi-linux-arm64.tar.gz',
  );

  static final PiReleaseAsset linuxX64 = PiReleaseAsset(
    version: version,
    platform: 'linux',
    arch: 'amd64',
    uri: Uri.parse(
      'https://github.com/earendil-works/pi/releases/download/v$version/'
      'pi-linux-x64.tar.gz',
    ),
    sha256: '494e498f47d74d21f40b3386f6a5e921a3d49531a169cab55bbdaca0ea1fe25a',
    archiveFileName: 'pi-linux-x64.tar.gz',
  );

  static PiReleaseAsset? forLinuxArch(String? arch) => switch (arch) {
    'arm64' => linuxArm64,
    'amd64' || 'x86_64' => linuxX64,
    _ => null,
  };
}
