import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/phone/phone_observation_adapter.dart';

/// W23/#125 follow-up: opt-in Android platform evidence harness.
///
/// DEFAULT CI: only contract fixtures execute; all device cases are skipped.
/// This does NOT grant accessibility/screenshot permissions or modify device
/// settings, rotate a device, install an APK or expose raw UI text to logs.
///
/// Device operator procedure (one phase at a time):
///   1. Connect an authorized Android test device; install the authorized app.
///   2. Set KELIVO_PHONE_DEVICE_TEST=1, ANDROID_SERIAL=`DEVICE_SERIAL`,
///      KELIVO_PHONE_ACCESSIBILITY_SERVICE=`PACKAGE/SERVICE_COMPONENT`.
///   3. Run `flutter test test/platform/phone/phone_observation_android_integration_test.dart`
///      with KELIVO_PHONE_DEVICE_PHASE=baseline while portrait and enabled.
///   4. Manually rotate into landscape, set PHASE=rotated; rerun.
///   5. Manually revoke the app's accessibility permission, set PHASE=revoked;
///      supply sanitized in-app PhoneObservation JSON via
///      KELIVO_PHONE_OBSERVATION_JSON_PATH and rerun.
///   6. Restore original test-device settings manually. Archive only redacted
///      pass/fail, SDK, phase, screen geometry and timestamp metadata.
///
/// ADB `uiautomator dump` and `screencap` test the Android OS capture path,
/// not the app's implementation. In-app capture must be evaluated separately;
/// no physical acceptance claim is made until all 3 phases are run with real
/// app capture evidence and reviewed by the supervisor.

final _deviceTest = Platform.environment['KELIVO_PHONE_DEVICE_TEST'] == '1';
final _phase = Platform.environment['KELIVO_PHONE_DEVICE_PHASE'] ?? '';

Future<ProcessResult> _adb(
  List<String> arguments, {
  bool binary = false,
}) async {
  final serial = Platform.environment['ANDROID_SERIAL'];
  if (serial == null || serial.trim().isEmpty) {
    throw StateError('Specify ANDROID_SERIAL for an explicit device');
  }
  final result = await Process.run(
    'adb',
    ['-s', serial, ...arguments],
    stdoutEncoding: binary ? null : utf8,
    stderrEncoding: utf8,
  ).timeout(const Duration(seconds: 25));
  if (result.exitCode != 0) {
    // Do not include raw ADB output; it can contain sensitive UI data.
    throw StateError('Android capture command failed');
  }
  return result;
}

PhoneObservation _sanitizedObservation({
  required String deviceRef,
  required DateTime capturedAt,
  required PhoneObservationSource source,
  required List<PhoneNodeBounds> bounds,
  String? screenshotRef,
}) => PhoneObservation(
  deviceRef: deviceRef,
  windowRef: 'window:test',
  source: source,
  capturedAt: capturedAt,
  screenshotRef: screenshotRef,
  nodes: [
    for (var i = 0; i < bounds.length; i++)
      PhoneObservedNode(id: 'node:$i', bounds: bounds[i]),
  ],
);

void main() {
  test('sanitized accessibility model never retains screen text', () {
    final observation = _sanitizedObservation(
      deviceRef: 'device:fixture',
      capturedAt: DateTime.utc(2026, 11, 21),
      source: PhoneObservationSource.accessibility,
      bounds: [PhoneNodeBounds(0.1, 0.2, 0.7, 0.8)],
    );
    final decoded = PhoneObservation.fromJson(observation.toJson());
    expect(decoded.nodes.single.label, isNull);
    expect(decoded.nodes.single.bounds.toJson(), [0.1, 0.2, 0.7, 0.8]);
    expect(decoded.screenshotRef, isNull);
  });

  test('invalid rotation geometry is rejected before capture receipt', () {
    expect(() => PhoneNodeBounds(0.8, 0.2, 0.2, 0.8), throwsArgumentError);
    expect(() => PhoneNodeBounds(-0.1, 0, 1, 1), throwsArgumentError);
  });

  test('real device accessibility tree and screenshot smoke', () async {
    final service = Platform.environment['KELIVO_PHONE_ACCESSIBILITY_SERVICE'];
    if (service == null || service.isEmpty) {
      throw StateError('Specify the authorized app accessibility service');
    }
    if (_phase != 'baseline' && _phase != 'rotated') {
      throw StateError('Choose baseline or rotated device phase');
    }
    final sdkRaw = (await _adb([
      'shell',
      'getprop',
      'ro.build.version.sdk',
    ])).stdout.toString().trim();
    final sdk = int.parse(sdkRaw);
    expect(sdk, greaterThanOrEqualTo(24));

    final enabledServices = (await _adb([
      'shell',
      'settings',
      'get',
      'secure',
      'enabled_accessibility_services',
    ])).stdout.toString().trim();
    expect(
      enabledServices.split(':'),
      contains(service),
      reason: 'Explicitly enable the target accessibility service first',
    );

    final sizeRaw = (await _adb(['shell', 'wm', 'size'])).stdout.toString();
    final match = RegExp(
      r'(?:Physical|Override) size:\s*(\d+)x(\d+)',
    ).allMatches(sizeRaw).lastOrNull;
    if (match == null) throw StateError('Unable to inspect Android display');
    final width = int.parse(match.group(1)!);
    final height = int.parse(match.group(2)!);
    expect(width, greaterThan(0));
    expect(height, greaterThan(0));

    // Raw XML and PNG bytes remain in memory only, never printed or persisted.
    final xml = (await _adb([
      'shell',
      'uiautomator',
      'dump',
      '/dev/tty',
    ])).stdout.toString();
    final rects = <PhoneNodeBounds>[];
    for (final match in RegExp(
      r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',
    ).allMatches(xml)) {
      final numbers = [for (var i = 1; i <= 4; i++) int.parse(match.group(i)!)];
      // Window coordinates outside the visible display are ignored.
      if (numbers[0] < 0 ||
          numbers[1] < 0 ||
          numbers[2] > width ||
          numbers[3] > height) {
        continue;
      }
      rects.add(
        PhoneNodeBounds(
          numbers[0] / width,
          numbers[1] / height,
          numbers[2] / width,
          numbers[3] / height,
        ),
      );
      if (rects.length == 2000) break;
    }
    expect(
      rects,
      isNotEmpty,
      reason: 'No Android accessibility bounds captured',
    );
    final png =
        (await _adb(['exec-out', 'screencap', '-p'], binary: true)).stdout
            as List<int>;
    expect(png.length, greaterThan(24));
    expect(png.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
    final receipt = _sanitizedObservation(
      deviceRef: 'device:android-sdk$sdk',
      capturedAt: DateTime.now().toUtc(),
      source: PhoneObservationSource.combined,
      bounds: rects,
      screenshotRef: 'artifact:screenshot-test',
    );
    final decoded = PhoneObservation.fromJson(receipt.toJson());
    expect(decoded.nodes.length, rects.length);
    expect(decoded.nodes.every((n) => n.label == null), isTrue);
    expect(decoded.screenshotRef, 'artifact:screenshot-test');

    // Rotation is operator-controlled; require an independently supplied
    // expected display aspect rather than silently asserting a rotation.
    final aspect = Platform.environment['KELIVO_PHONE_EXPECTED_ASPECT'];
    if (aspect != 'portrait' && aspect != 'landscape') {
      throw StateError('Set KELIVO_PHONE_EXPECTED_ASPECT explicitly');
    }
    if (aspect == 'portrait') expect(height, greaterThan(width));
    if (aspect == 'landscape') expect(width, greaterThan(height));
  }, skip: !_deviceTest || (_phase != 'baseline' && _phase != 'rotated'));

  test('revoked accessibility: check permission and app receipt', () async {
    final service = Platform.environment['KELIVO_PHONE_ACCESSIBILITY_SERVICE'];
    if (service == null || service.isEmpty) {
      throw StateError('Specify the authorized app accessibility service');
    }
    final services = (await _adb([
      'shell',
      'settings',
      'get',
      'secure',
      'enabled_accessibility_services',
    ])).stdout.toString().trim();
    expect(services.split(':'), isNot(contains(service)));

    final evidencePath =
        Platform.environment['KELIVO_PHONE_OBSERVATION_JSON_PATH'];
    if (evidencePath == null || evidencePath.isEmpty) {
      throw StateError('Missing sanitized in-app observation evidence path');
    }
    final evidenceFile = File(evidencePath);
    if (!evidenceFile.existsSync() || evidenceFile.lengthSync() > 256 * 1024) {
      throw StateError('Missing or oversized app observation evidence');
    }
    final parsed = jsonDecode(await evidenceFile.readAsString());
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Expected sanitized PhoneObservation JSON');
    }
    final observation = PhoneObservation.fromJson(parsed);
    expect(
      observation.nodes,
      isEmpty,
      reason: 'App must not emit accessibility nodes after permission loss',
    );
    expect(observation.source, PhoneObservationSource.accessibility);
    expect(observation.screenshotRef, isNull);
  }, skip: !_deviceTest || _phase != 'revoked');
}
