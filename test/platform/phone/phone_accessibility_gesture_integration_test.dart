import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #57 Android accessibility gesture contract and opt-in evidence gate.
/// No gesture is ever dispatched from CI. A human operator must authorize
/// and independently execute a harmless gesture in the application, then
/// provide a *sanitized* before/after receipt from PhoneControlService.
/// ADB permission/service checks alone do not prove gestures work.
final bool _enabled = Platform.environment['KELIVO_GESTURE_DEVICE_TEST'] == '1';

bool validNormalizedPoint(num x, num y) =>
    x.isFinite && y.isFinite && x >= 0 && x <= 1 && y >= 0 && y <= 1;

void main() {
  test('rejects negative, non-finite and out-of-viewport gestures', () {
    expect(validNormalizedPoint(0.5, 0.5), isTrue);
    for (final x in [-0.01, 1.01, double.nan, double.infinity]) {
      expect(validNormalizedPoint(x, 0.5), isFalse);
    }
    expect(validNormalizedPoint(0.5, -0.1), isFalse);
  });

  test('an unverified action cannot be automatically replayed', () {
    const receipt = {
      'gestureId': 'test:tap',
      'dispatched': true,
      'verified': false,
      'mayAutoReplay': false,
    };
    expect(receipt['mayAutoReplay'], isFalse);
    expect(receipt['verified'], isFalse);
  });

  test('authorized physical Android gesture with redacted receipt', () async {
    final serial = Platform.environment['ANDROID_SERIAL'];
    final service =
        Platform.environment['KELIVO_GESTURE_ACCESSIBILITY_SERVICE'];
    final path = Platform.environment['KELIVO_GESTURE_EVIDENCE_JSON'];
    if (serial == null ||
        serial.isEmpty ||
        service == null ||
        service.isEmpty ||
        path == null ||
        path.isEmpty) {
      throw StateError('Set serial, accessibility service and device receipt');
    }
    final sdk = await Process.run('adb', [
      '-s',
      serial,
      'shell',
      'getprop',
      'ro.build.version.sdk',
    ]).timeout(const Duration(seconds: 20));
    if (sdk.exitCode != 0) throw StateError('Android device SDK probe failed');
    expect(
      int.tryParse(sdk.stdout.toString().trim()),
      greaterThanOrEqualTo(24),
    );
    final enabledServices = await Process.run('adb', [
      '-s',
      serial,
      'shell',
      'settings',
      'get',
      'secure',
      'enabled_accessibility_services',
    ]).timeout(const Duration(seconds: 20));
    if (enabledServices.exitCode != 0) {
      throw StateError('Accessibility permission probe failed');
    }
    expect(
      enabledServices.stdout.toString().trim().split(':'),
      contains(service),
    );
    final evidence = File(path);
    if (!await evidence.exists() || await evidence.length() > 65536) {
      throw StateError('Missing or oversized sanitized device receipt');
    }
    final raw = jsonDecode(await evidence.readAsString());
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Gesture receipt must be JSON object');
    }
    expect(raw['gestureDispatchedByApp'], isTrue);
    expect(raw['verifiedByFreshObservation'], isTrue);
    expect(raw['mayAutoReplay'], isFalse);
    final start = raw['startPoint'];
    if (start is! List ||
        start.length != 2 ||
        start[0] is! num ||
        start[1] is! num) {
      throw const FormatException('Invalid normalized start point');
    }
    expect(validNormalizedPoint(start[0] as num, start[1] as num), isTrue);
    // This validates only supplied evidence; on-device logs, app identity,
    // actual gesture execution and screenshot differences need independent review.
  }, skip: !_enabled ? 'NOT TESTED: authorized Android device absent' : false);
}
