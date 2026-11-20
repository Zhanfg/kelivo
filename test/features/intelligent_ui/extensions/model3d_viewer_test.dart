import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/model3d_viewer.dart';

void main() {
  final path = 'test/features/intelligent_ui/extensions/fixtures/triangle.glb';
  late Uint8List fixture;
  setUpAll(() => fixture = File(path).readAsBytesSync());

  test('actual glTF 2.0 triangle GLB fixture decodes', () {
    final document = GlbModelDocument.parse(fixture);
    expect(document.meshCount, 1);
    expect(document.nodes, ['Triangle']);
    expect(document.byteLength, fixture.length);
  });

  test('corrupted magic, version and truncated length rejected', () {
    for (final index in [0, 4, 8, 12]) {
      final broken = Uint8List.fromList(fixture)..[index] = 0xff;
      expect(() => GlbModelDocument.parse(broken), throwsFormatException);
    }
    expect(
      () => GlbModelDocument.parse(fixture, maxBytes: 16),
      throwsFormatException,
    );
  });

  test('viewer state rotation zoom and selection are bounded', () {
    final state = GlbViewerState(GlbModelDocument.parse(fixture));
    state.orbit(1, 1);
    expect(state.yawRadians, 0);
    state.setVisible(true);
    state.orbit(0.5, 5);
    expect(state.yawRadians, 0.5);
    expect(state.pitchRadians, 1.5);
    state.setZoom(2);
    expect(state.zoom, 2);
    state.select(0);
    expect(state.selectedNode, 0);
    expect(() => state.select(99), throwsRangeError);
    expect(() => state.setZoom(double.infinity), throwsArgumentError);
    state.setVisible(false);
    state.select(null);
    expect(state.selectedNode, 0);
  });
}
