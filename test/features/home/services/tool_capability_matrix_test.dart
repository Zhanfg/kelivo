import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/capabilities/capability_report.dart';

/// Contract fixtures, not evidence of actual operating system permissions.
/// Host probes and tool dispatch integration remain separate platform work.
void main() {
  final observed = DateTime.utc(2026, 11, 21);
  const platforms = <String, String>{
    'android': 'arm64',
    'ios': 'arm64',
    'linux': 'x64',
    'windows': 'x64',
    'macos': 'arm64',
    'web': 'wasm32',
  };
  const tools = <String>[
    'tool.browser',
    'tool.clipboard',
    'tool.device-control',
    'tool.file-access',
    'tool.location',
    'tool.shell',
  ];

  CapabilityReport fixture(
    String platform,
    String architecture,
    CapabilityAvailability state,
  ) => CapabilityReport(
    platform: platform,
    architecture: architecture,
    observedAt: observed,
    descriptors: [
      for (final tool in tools)
        CapabilityDescriptor(id: tool, availability: state),
    ],
  );

  test('cross-platform capability matrix retains all tool identifiers', () {
    for (final entry in platforms.entries) {
      final report = fixture(
        entry.key,
        entry.value,
        CapabilityAvailability.unsupported,
      );
      final decoded = CapabilityReport.fromJson(report.toJson());
      expect(decoded.platform, entry.key);
      expect(decoded.architecture, entry.value);
      expect(
        decoded.descriptors.map((d) => d.id).toList(),
        tools,
        reason: 'Matrix fixture for ${entry.key}',
      );
    }
  });

  test('availability states survive platform-by-tool matrix serialization', () {
    for (final entry in platforms.entries) {
      for (final state in CapabilityAvailability.values) {
        final report = fixture(entry.key, entry.value, state);
        final restored = CapabilityReport.fromJson(report.toJson());
        for (final tool in tools) {
          expect(restored[tool]?.availability, state);
        }
      }
    }
  });

  test('unknown capability must not be assumed available', () {
    final report = fixture(
      'android',
      'arm64',
      CapabilityAvailability.permissionRequired,
    );
    expect(report['tool.not-probed'], isNull);
    expect(
      report['tool.device-control']?.availability,
      CapabilityAvailability.permissionRequired,
    );
  });

  test('invalid wire availability fails closed on all platforms', () {
    for (final entry in platforms.entries) {
      final payload = fixture(
        entry.key,
        entry.value,
        CapabilityAvailability.available,
      ).toJson();
      final descriptors = payload['descriptors'] as List<Map<String, dynamic>>;
      descriptors.first['availability'] = 'assume_available';
      expect(() => CapabilityReport.fromJson(payload), throwsFormatException);
    }
  });

  test('duplicate tool capability identifiers are rejected', () {
    expect(
      () => CapabilityReport(
        platform: 'android',
        architecture: 'arm64',
        observedAt: observed,
        descriptors: [
          CapabilityDescriptor(
            id: tools.first,
            availability: CapabilityAvailability.available,
          ),
          CapabilityDescriptor(
            id: tools.first,
            availability: CapabilityAvailability.disabled,
          ),
        ],
      ),
      throwsFormatException,
    );
  });

  test('permission and disabled states are distinct from unavailable', () {
    final report = CapabilityReport(
      platform: 'android',
      architecture: 'arm64',
      observedAt: observed,
      descriptors: [
        CapabilityDescriptor(
          id: 'tool.location',
          availability: CapabilityAvailability.permissionRequired,
          reason: 'Awaiting explicit user permission',
        ),
        CapabilityDescriptor(
          id: 'tool.shell',
          availability: CapabilityAvailability.disabled,
          reason: 'Host setting disabled',
        ),
        CapabilityDescriptor(
          id: 'tool.browser',
          availability: CapabilityAvailability.unsupported,
        ),
      ],
    );
    expect(
      report['tool.location']!.availability,
      CapabilityAvailability.permissionRequired,
    );
    expect(report['tool.shell']!.availability, CapabilityAvailability.disabled);
    expect(
      report['tool.browser']!.availability,
      CapabilityAvailability.unsupported,
    );
  });
}
