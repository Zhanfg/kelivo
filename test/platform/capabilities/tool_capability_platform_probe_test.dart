import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/capabilities/capability_report.dart';

/// Cross-platform report wire checks, plus opt-in host probe evidence check.
/// No OS permission or tool availability is inferred from runtime platform.
/// A real host probe must export an anonymized report file after live checks.
final bool _live = Platform.environment['KELIVO_CAPABILITY_PROBE_TEST'] == '1';

void main() {
  CapabilityReport fixture(
    String platform,
    CapabilityAvailability availability,
  ) => CapabilityReport(
    platform: platform,
    architecture: 'arm64',
    observedAt: DateTime.utc(2026, 11, 21),
    descriptors: [
      CapabilityDescriptor(id: 'tool.shell', availability: availability),
      CapabilityDescriptor(id: 'camera.capture', availability: availability),
    ],
  );

  test('all six platform reports retain explicit availability state', () {
    for (final platform in [
      'android',
      'ios',
      'linux',
      'windows',
      'macos',
      'web',
    ]) {
      for (final state in CapabilityAvailability.values) {
        final decoded = CapabilityReport.fromJson(
          fixture(platform, state).toJson(),
        );
        expect(decoded.platform, platform);
        expect(decoded['tool.shell']?.availability, state);
        expect(decoded['camera.capture']?.availability, state);
      }
    }
  });

  test('absence cannot be interpreted as available', () {
    final report = fixture(
      'android',
      CapabilityAvailability.permissionRequired,
    );
    expect(report['tool.browser'], isNull);
    expect(
      report['tool.shell']?.availability,
      CapabilityAvailability.permissionRequired,
    );
  });

  test('malformed and duplicated capability evidence is rejected', () {
    final original = fixture(
      'android',
      CapabilityAvailability.unsupported,
    ).toJson();
    final descriptors = original['descriptors'] as List<Map<String, dynamic>>;
    expect(
      () => CapabilityReport.fromJson({
        ...original,
        'descriptors': [...descriptors, descriptors.first],
      }),
      throwsFormatException,
    );
    expect(
      () => CapabilityReport.fromJson({
        ...original,
        'descriptors': [
          {...descriptors.first, 'availability': 'assumed_available'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('opt-in real platform probe report matches declared target', () async {
    final path = Platform.environment['KELIVO_CAPABILITY_PROBE_JSON_PATH'];
    final expected =
        Platform.environment['KELIVO_CAPABILITY_EXPECTED_PLATFORM'];
    if (path == null || path.isEmpty || expected == null || expected.isEmpty) {
      throw StateError('Set explicit sanitized host-probe report and platform');
    }
    final file = File(path);
    if (!file.existsSync() || await file.length() > 256 * 1024) {
      throw StateError('Missing or oversized host probe evidence');
    }
    final data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid report');
    }
    final report = CapabilityReport.fromJson(data);
    expect(report.platform, expected);
    expect(report.descriptors, isNotEmpty);
    expect(report.observedAt.isUtc, isTrue);
    for (final item in report.descriptors) {
      expect(CapabilityAvailability.values, contains(item.availability));
      expect(item.id, isNotEmpty);
    }
    // Host execution logs and the actual tool-to-report mapping still require
    // operator verification; a schema-valid report is not proof of behavior.
  }, skip: !_live ? 'NOT TESTED: no live platform probe supplied' : false);
}
