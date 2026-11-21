import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/model3d_viewer.dart';

/// W31 follow-up GPU acceptance evidence contract, not a GPU renderer.
/// Existing GLB parser does NOT render. Native GPU capture must be supplied
/// externally and verified separately on Android plus desktop platforms.
final bool _live = Platform.environment['KELIVO_GLTF_RENDER_TEST'] == '1';

void main() {
  const glb = 'test/features/intelligent_ui/extensions/fixtures/triangle.glb';

  test('real GLB triangle fixture has parseable mesh metadata', () {
    final bytes = File(glb).readAsBytesSync();
    final model = GlbModelDocument.parse(bytes);
    expect(model.meshCount, 1);
    expect(model.nodes, ['Triangle']);
    expect(model.byteLength, bytes.length);
  });

  test('offscreen state pauses interaction, invalid zoom rejected', () {
    final model = GlbModelDocument.parse(File(glb).readAsBytesSync());
    final state = GlbViewerState(model);
    expect(state.paused, isTrue);
    state.setZoom(2);
    expect(state.zoom, 1);
    state.setVisible(true);
    state.orbit(0.25, 0.5);
    state.setZoom(2);
    expect(state.yawRadians, 0.25);
    expect(state.zoom, 2);
    state.setVisible(false);
    state.orbit(0.5, 0.5);
    expect(state.yawRadians, 0.25);
    expect(() => state.setZoom(double.nan), throwsArgumentError);
  });

  test(
    'opt-in real platform GPU render metric envelope',
    () async {
      final path = Platform.environment['KELIVO_GLTF_GPU_EVIDENCE_JSON'];
      final expectedPlatform =
          Platform.environment['KELIVO_GLTF_EXPECTED_PLATFORM'];
      if (path == null ||
          expectedPlatform == null ||
          expectedPlatform.isEmpty) {
        throw StateError('Specify platform and redacted GPU result file');
      }
      final evidenceFile = File(path);
      if (!await evidenceFile.exists() || await evidenceFile.length() > 65536) {
        throw StateError('Missing or oversized GPU result');
      }
      final raw = jsonDecode(await evidenceFile.readAsString());
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid platform GPU result');
      }
      expect(raw['platform'], expectedPlatform);
      expect([
        'android',
        'windows',
        'macos',
        'linux',
      ], contains(raw['platform']));
      expect(raw['modelSha256'] is String, isTrue);
      expect(
        RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['modelSha256'] as String),
        isTrue,
      );
      expect(raw['renderedFrames'], isA<int>());
      expect(raw['renderedFrames'] as int, greaterThan(0));
      final p95 = raw['frameTimeP95Ms'];
      expect(p95, isA<num>());
      expect((p95 as num).isFinite && p95 > 0, isTrue);
      // Fixture self-reports are *not* proof of live GPU rendering; the operator
      // must independently review device screenshot/frame traces and version.
    },
    skip: !_live
        ? 'NOT TESTED: real Android/desktop GPU renderer absent'
        : false,
  );
}
