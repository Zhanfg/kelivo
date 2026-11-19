import 'package:Kelivo/core/services/phone/phone_observation_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

final _time = DateTime.utc(2026, 11, 20);

PhoneObservedNode _node(
  String id, {
  String? parentId,
  String? label,
  bool sensitive = false,
}) => PhoneObservedNode(
  id: id,
  parentId: parentId,
  label: label,
  sensitive: sensitive,
  bounds: PhoneNodeBounds(0.1, 0.2, 0.8, 0.9),
);

PhoneObservation _observation({
  List<PhoneObservedNode>? nodes,
  PhoneObservationSource source = PhoneObservationSource.combined,
  String? screenshotRef = 'artifact:image1',
}) => PhoneObservation(
  deviceRef: 'device:demo',
  windowRef: 'window:main',
  source: source,
  capturedAt: _time,
  screenshotRef: screenshotRef,
  nodes: nodes ?? [_node('parent'), _node('child', parentId: 'parent')],
);

void main() {
  test('roundtrip window/source/timestamp and normalized nodes', () {
    final first = _observation();
    final decoded = PhoneObservation.fromJson(first.toJson());
    expect(decoded.toJson(), first.toJson());
    expect(decoded.source, PhoneObservationSource.combined);
    expect(decoded.capturedAt.isUtc, isTrue);
    expect(decoded.nodes, hasLength(2));
  });

  test('sensitive tree nodes cannot retain raw labels', () {
    expect(
      () => _node('password', label: 'secret', sensitive: true),
      throwsArgumentError,
    );
    expect(_node('password', sensitive: true).toJson()['label'], isNull);
  });

  test('bounds reject non-finite/out-of-range and inverted coordinates', () {
    for (final bounds in [
      [0, 0, 1.1, 1],
      [0.8, 0.2, 0.1, 0.9],
      [double.nan, 0, 1, 1],
      [-1, 0, 1, 1],
    ]) {
      expect(() => PhoneNodeBounds.fromJson(bounds), throwsFormatException);
    }
  });

  test('parent existence and cycles are checked', () {
    expect(
      () => _observation(nodes: [_node('orphan', parentId: 'missing')]),
      throwsArgumentError,
    );
    expect(
      () => _observation(
        nodes: [
          _node('a', parentId: 'b'),
          _node('b', parentId: 'a'),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('duplicate node identities cannot alias sensitive regions', () {
    expect(
      () => _observation(nodes: [_node('duplicate'), _node('duplicate')]),
      throwsArgumentError,
    );
  });

  test('screenshot mode requires opaque screenshot artifact handle', () {
    expect(
      () => _observation(
        source: PhoneObservationSource.screenshot,
        screenshotRef: null,
      ),
      throwsArgumentError,
    );
    expect(
      _observation(source: PhoneObservationSource.screenshot).screenshotRef,
      'artifact:image1',
    );
  });

  test('untrusted snapshots reject unknown schemas and raw sensitive keys', () {
    final valid = _observation().toJson();
    expect(
      () => PhoneObservation.fromJson({...valid, 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => PhoneObservation.fromJson({...valid, 'screenshotBytes': 'raw'}),
      throwsFormatException,
    );
    expect(
      () => PhoneObservation.fromJson({...valid, 'source': 'root'}),
      throwsFormatException,
    );
  });

  test('observed node rejects unexpected properties and invalid types', () {
    final original = _node('a').toJson();
    expect(
      () => PhoneObservedNode.fromJson({...original, 'password': 'data'}),
      throwsFormatException,
    );
    expect(
      () => PhoneObservedNode.fromJson({...original, 'sensitive': 'yes'}),
      throwsFormatException,
    );
  });
}
