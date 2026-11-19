import 'package:Kelivo/core/services/capabilities/capability_report.dart';
import 'package:Kelivo/core/services/security/capability_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final snapshot = CapabilityReport(
    platform: 'android',
    architecture: 'arm64',
    observedAt: DateTime.utc(2026),
    descriptors: [
      CapabilityDescriptor(
        id: 'camera.capture',
        availability: CapabilityAvailability.available,
      ),
      CapabilityDescriptor(
        id: 'shell.exec',
        availability: CapabilityAvailability.permissionRequired,
      ),
    ],
  );

  test('fail closed on missing grants and inaccessible device capability', () {
    final policy = CapabilityPolicy(
      taskId: 'main-1',
      allowed: ['camera.capture', 'shell.exec'],
    );
    expect(policy.permits('camera.capture', snapshot), isTrue);
    expect(policy.permits('shell.exec', snapshot), isFalse);
    expect(policy.permits('root.exec', snapshot), isFalse);
  });

  test('revocation remains effective in descendants', () {
    final parent = CapabilityPolicy(
      taskId: 'main',
      allowed: ['camera.capture', 'shell.exec'],
    ).revoke('camera.capture');
    expect(parent.permits('camera.capture', snapshot), isFalse);
    final child = parent.deriveChild('child-1', [
      'camera.capture',
      'shell.exec',
      'root.exec',
    ]);
    expect(child.allowed, {'shell.exec'});
    expect(child.permits('camera.capture', snapshot), isFalse);
    expect(child.permits('shell.exec', snapshot), isFalse);
  });

  test('allowed set is immutable, invalid ids rejected', () {
    final policy = CapabilityPolicy(
      taskId: 'main',
      allowed: ['camera.capture'],
    );
    expect(() => policy.allowed.add('root.exec'), throwsUnsupportedError);
    expect(
      () => CapabilityPolicy(taskId: '../bad', allowed: []),
      throwsFormatException,
    );
    expect(() => policy.revoke('TOKEN'), throwsFormatException);
  });

  test('audit summary exposes only counts and safe task ID', () {
    final policy = CapabilityPolicy(
      taskId: 'main',
      allowed: ['camera.capture'],
    );
    expect(policy.auditSummary(), {
      'taskId': 'main',
      'allowedCount': 1,
      'revokedCount': 0,
    });
  });
}
