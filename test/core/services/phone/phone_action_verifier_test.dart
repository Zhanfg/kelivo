import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/phone/phone_action_verifier.dart';
import 'package:Kelivo/core/services/phone/phone_observation_adapter.dart';

void main() {
  PhoneObservation observation(
    int second, {
    String label = 'before',
    String device = 'device:1',
    String window = 'window:1',
  }) => PhoneObservation(
    deviceRef: device,
    windowRef: window,
    source: PhoneObservationSource.accessibility,
    capturedAt: DateTime.utc(2026, 11, 21, 0, 0, second),
    nodes: [
      PhoneObservedNode(
        id: 'node:1',
        bounds: PhoneNodeBounds(0, 0, 1, 1),
        label: label,
      ),
    ],
  );

  test('changed expected state verifies without granting replay', () {
    final receipt = PhoneActionVerifier().verify(
      actionId: 'action:1',
      before: observation(1),
      after: observation(2, label: 'done'),
      expectedAfter: (snapshot) => snapshot.nodes.single.label == 'done',
    );
    expect(receipt.verdict, PhoneActionVerdict.verified);
    expect(receipt.mayAutoReplay, isFalse);
  });

  test('no change does not imply completed action', () {
    final receipt = PhoneActionVerifier().verify(
      actionId: 'a',
      before: observation(1),
      after: observation(2),
      expectedAfter: (_) => true,
    );
    expect(receipt.verdict, PhoneActionVerdict.unchanged);
  });

  test('missing post-observation marks outcome unknown', () {
    final receipt = PhoneActionVerifier().verify(
      actionId: 'a',
      before: observation(1),
      after: null,
      expectedAfter: (_) => true,
    );
    expect(receipt.verdict, PhoneActionVerdict.unknown);
    expect(receipt.mayAutoReplay, isFalse);
  });

  test('changed but unexpected state remains unknown', () {
    final receipt = PhoneActionVerifier().verify(
      actionId: 'a',
      before: observation(1),
      after: observation(2, label: 'error'),
      expectedAfter: (snapshot) => snapshot.nodes.single.label == 'success',
    );
    expect(receipt.verdict, PhoneActionVerdict.unknown);
  });

  test('device, window and chronological mismatch conservatively unknown', () {
    for (final after in [
      observation(2, device: 'device:2'),
      observation(2, window: 'window:2'),
      observation(0),
    ]) {
      final receipt = PhoneActionVerifier().verify(
        actionId: 'a',
        before: observation(1),
        after: after,
        expectedAfter: (_) => true,
      );
      expect(receipt.verdict, PhoneActionVerdict.unknown);
    }
  });

  test('same action id cannot be verified twice', () {
    final verifier = PhoneActionVerifier();
    verifier.verify(
      actionId: 'a',
      before: observation(1),
      after: null,
      expectedAfter: (_) => false,
    );
    expect(
      () => verifier.verify(
        actionId: 'a',
        before: observation(1),
        after: observation(2),
        expectedAfter: (_) => true,
      ),
      throwsStateError,
    );
  });

  test('unsafe action ids are refused', () {
    expect(
      () => PhoneActionVerifier().verify(
        actionId: '../bad',
        before: observation(1),
        after: null,
        expectedAfter: (_) => false,
      ),
      throwsArgumentError,
    );
  });
}
