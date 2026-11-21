import 'package:Kelivo/core/services/capabilities/capability_report.dart';
import 'package:flutter_test/flutter_test.dart';

/// #99 contract-level gating of hypothetical tool IDs against host reports.
/// It does not modify LocalToolNames or discover capabilities on real devices.
bool declaredAvailable(CapabilityReport report, String toolId) =>
    report['tool.$toolId']?.availability == CapabilityAvailability.available;

void main() {
  CapabilityReport report(
    String platform,
    Map<String, CapabilityAvailability> support,
  ) => CapabilityReport(
    platform: platform,
    architecture: platform == 'android' ? 'arm64' : 'x64',
    observedAt: DateTime.utc(2026, 11, 21),
    descriptors: [
      for (final entry in support.entries)
        CapabilityDescriptor(
          id: 'tool.${entry.key}',
          availability: entry.value,
        ),
    ],
  );

  test('missing tools and disabled tools are not advertised as usable', () {
    final android = report('android', {
      'camera': CapabilityAvailability.permissionRequired,
      'shell': CapabilityAvailability.available,
      'screentime': CapabilityAvailability.unsupported,
    });
    expect(declaredAvailable(android, 'shell'), isTrue);
    expect(declaredAvailable(android, 'camera'), isFalse);
    expect(declaredAvailable(android, 'screentime'), isFalse);
    expect(declaredAvailable(android, 'missing'), isFalse);
  });

  test('identical IDs can have distinct supported-platform matrices', () {
    final ios = report('ios', {'shell': CapabilityAvailability.unsupported});
    final desktop = report('linux', {
      'shell': CapabilityAvailability.available,
    });
    expect(declaredAvailable(ios, 'shell'), isFalse);
    expect(declaredAvailable(desktop, 'shell'), isTrue);
  });

  test(
    'unsupported report format or duplicate tool declarations fail closed',
    () {
      expect(
        report('linux', {
          'shell': CapabilityAvailability.available,
          'shell.command': CapabilityAvailability.available,
        }).toJson()['schemaVersion'],
        1,
      );
      final descriptor = CapabilityDescriptor(
        id: 'tool.shell',
        availability: CapabilityAvailability.available,
      );
      expect(
        () => CapabilityReport(
          platform: 'linux',
          architecture: 'x64',
          observedAt: DateTime.utc(2026),
          descriptors: [descriptor, descriptor],
        ),
        throwsFormatException,
      );
    },
  );
}
