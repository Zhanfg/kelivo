import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/phone/phone_observation_adapter.dart';

void main() {
  final captured = DateTime.utc(2026, 11, 21, 0, 0, 0);

  PhoneObservedNode node(
    String id, {
    String? parent,
    bool sensitive = false,
    String? label,
    List<double> rect = const [0.1, 0.2, 0.8, 0.9],
  }) => PhoneObservedNode(
    id: id,
    parentId: parent,
    bounds: PhoneNodeBounds(rect[0], rect[1], rect[2], rect[3]),
    label: label,
    sensitive: sensitive,
  );

  PhoneObservation observation(
    PhoneObservationSource source, {
    List<PhoneObservedNode>? nodes,
    String? screenshot = 'artifact:img',
    String device = 'device:emulator',
  }) => PhoneObservation(
    deviceRef: device,
    windowRef: 'window:main',
    source: source,
    capturedAt: captured,
    screenshotRef: screenshot,
    nodes: nodes ?? [node('root'), node('child', parent: 'root')],
  );

  test('version fixture matrix: 26, 28, 30, 33, 35, 36', () {
    // Schema checks are platform-neutral; this is NOT an Android device test.
    for (final sdk in [26, 28, 30, 33, 35, 36]) {
      final result = observation(
        PhoneObservationSource.combined,
        device: 'android:sdk$sdk',
      );
      expect(
        PhoneObservation.fromJson(result.toJson()).toJson(),
        result.toJson(),
        reason: 'SDK $sdk fixture',
      );
    }
  });

  test('accessibility-only receipt needs no screenshot', () {
    final result = observation(
      PhoneObservationSource.accessibility,
      screenshot: null,
    );
    expect(result.screenshotRef, isNull);
    expect(result.nodes.length, 2);
  });

  test('screenshot-only requires opaque image artifact', () {
    expect(
      () => observation(PhoneObservationSource.screenshot, screenshot: null),
      throwsArgumentError,
    );
    final result = observation(PhoneObservationSource.screenshot, nodes: []);
    expect(result.nodes, isEmpty);
    expect(result.screenshotRef, 'artifact:img');
  });

  test('portrait and landscape normalized coordinate fixtures', () {
    for (final rect in [
      [0.10, 0.20, 0.80, 0.90],
      [0.20, 0.10, 0.90, 0.80],
    ]) {
      final result = observation(
        PhoneObservationSource.combined,
        nodes: [node('root', rect: rect)],
      );
      final decoded = PhoneObservation.fromJson(result.toJson());
      expect(decoded.nodes.single.bounds.toJson(), rect);
    }
  });

  test('reject invalid or inverted normalized coordinates', () {
    for (final rect in <List<double>>[
      [-0.1, 0.0, 1.0, 1.0],
      [0.0, 0.0, 1.1, 1.0],
      [0.9, 0.0, 0.2, 1.0],
      [0.0, 0.9, 1.0, 0.2],
      [double.nan, 0.0, 1.0, 1.0],
    ]) {
      expect(() => node('bad', rect: rect), throwsArgumentError);
    }
  });

  test('permission revoked fixture has no nodes or screenshot', () {
    // A revoked permission must not be represented by synthetic tree content.
    final result = observation(
      PhoneObservationSource.accessibility,
      nodes: [],
      screenshot: null,
    );
    final roundtrip = PhoneObservation.fromJson(result.toJson());
    expect(roundtrip.nodes, isEmpty);
    expect(roundtrip.screenshotRef, isNull);
  });

  test('sensitive node labels must be omitted at capture', () {
    expect(
      () => node('password', sensitive: true, label: 'private'),
      throwsArgumentError,
    );
    final result = observation(
      PhoneObservationSource.accessibility,
      nodes: [node('password', sensitive: true)],
      screenshot: null,
    );
    expect(result.toJson().toString().contains('private'), isFalse);
    expect(result.nodes.single.label, isNull);
  });

  test('reject duplicate nodes, missing parents and cyclic ancestry', () {
    expect(
      () => observation(
        PhoneObservationSource.accessibility,
        nodes: [node('same'), node('same')],
      ),
      throwsArgumentError,
    );
    expect(
      () => observation(
        PhoneObservationSource.accessibility,
        nodes: [node('child', parent: 'missing')],
      ),
      throwsArgumentError,
    );
    expect(
      () => observation(
        PhoneObservationSource.accessibility,
        nodes: [
          node('a', parent: 'b'),
          node('b', parent: 'a'),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('strict schema rejects extra fields, invalid time and source', () {
    final original = observation(PhoneObservationSource.combined).toJson();
    expect(
      () => PhoneObservation.fromJson({...original, 'unknown': true}),
      throwsFormatException,
    );
    expect(
      () => PhoneObservation.fromJson({...original, 'source': 'none'}),
      throwsFormatException,
    );
    expect(
      () => PhoneObservation.fromJson({
        ...original,
        'capturedAt': '2026-11-21T00:00:00',
      }),
      throwsFormatException,
    );
  });
}
