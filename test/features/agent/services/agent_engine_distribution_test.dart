import 'package:Kelivo/features/agent/services/agent_engine_distribution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Agent engine is pinned to the KELIVO Mobile OMP v18.2.8 release', () {
    final asset = AgentEngineDistribution.linuxMuslArm64;

    expect(AgentEngineDistribution.engineName, 'omp');
    expect(AgentEngineDistribution.version, '18.2.8');
    expect(asset.version, '18.2.8');
    expect(asset.platform, 'linux-musl');
    expect(asset.arch, 'arm64');
    expect(asset.fileName, 'omp-kelivo-mobile-linux-musl-arm64');
    expect(
      asset.uri.toString(),
      'https://github.com/Zhanfg/oh-my-pi/releases/download/'
      'kelivo-mobile-v18.2.8-1c5802c9/'
      'omp-kelivo-mobile-linux-musl-arm64',
    );
    expect(
      asset.sha256,
      '1e617d191468de58c1988cacdf077ba1e864ca259cd7b2236cb5d953316f61aa',
    );
    expect(
      AgentEngineDistribution.forLinuxArch('arm64'),
      same(asset),
    );
  });
}
