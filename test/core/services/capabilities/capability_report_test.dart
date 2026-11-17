import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/capabilities/capability_report.dart';

void main() {
  final observed = DateTime.utc(2026, 11, 17, 14, 0);

  CapabilityReport sample({List<CapabilityDescriptor>? descriptors}) =>
      CapabilityReport(
        platform: 'android',
        architecture: 'arm64',
        observedAt: observed,
        descriptors:
            descriptors ??
            [
              CapabilityDescriptor(
                id: 'device.camera',
                availability: CapabilityAvailability.permissionRequired,
                reason: 'User approval required',
                metadata: {'backend': 'camera2'},
              ),
              CapabilityDescriptor(
                id: 'workspace.shell',
                availability: CapabilityAvailability.available,
              ),
            ],
      );

  group('CapabilityReport contract', () {
    test('roundtrip preserves statuses and timestamp', () {
      final report = sample();
      final payload = report.toJson();
      expect(payload['schemaVersion'], 1);
      expect(payload['observedAt'], endsWith('Z'));
      final restored = CapabilityReport.fromJson(payload);
      expect(restored, report);
      expect(
        restored['device.camera']?.availability,
        CapabilityAvailability.permissionRequired,
      );
      expect(
        restored['workspace.shell']?.availability,
        CapabilityAvailability.available,
      );
      expect(restored['missing'], isNull);
    });

    test('all availability values use stable wire names', () {
      expect(CapabilityAvailability.available.wireName, 'available');
      expect(CapabilityAvailability.disabled.wireName, 'disabled');
      expect(
        CapabilityAvailability.permissionRequired.wireName,
        'permission_required',
      );
      expect(CapabilityAvailability.unsupported.wireName, 'unsupported');
      expect(
        () => CapabilityAvailability.fromJson('unknown'),
        throwsFormatException,
      );
    });

    test('duplicates and invalid IDs are rejected', () {
      final first = CapabilityDescriptor(
        id: 'device.camera',
        availability: CapabilityAvailability.available,
      );
      expect(() => sample(descriptors: [first, first]), throwsFormatException);
      expect(
        () => CapabilityDescriptor(
          id: '../private',
          availability: CapabilityAvailability.available,
        ),
        throwsFormatException,
      );
      expect(
        () => CapabilityDescriptor(
          id: 'Device.Camera',
          availability: CapabilityAvailability.available,
        ),
        throwsFormatException,
      );
    });

    test('metadata is immutable and credential-shaped keys fail closed', () {
      final input = {'backend': 'camera2'};
      final descriptor = CapabilityDescriptor(
        id: 'device.camera',
        availability: CapabilityAvailability.available,
        metadata: input,
      );
      input['backend'] = 'changed';
      expect(descriptor.metadata['backend'], 'camera2');
      expect(
        () => descriptor.metadata['backend'] = 'other',
        throwsUnsupportedError,
      );
      for (final key in ['api_key', 'auth-token', 'password', 'cookie']) {
        expect(
          () => CapabilityDescriptor(
            id: 'device.camera',
            availability: CapabilityAvailability.available,
            metadata: {key: 'sensitive'},
          ),
          throwsFormatException,
        );
      }
    });

    test('descriptor collection is immutable and detached', () {
      final descriptors = <CapabilityDescriptor>[
        CapabilityDescriptor(
          id: 'device.camera',
          availability: CapabilityAvailability.available,
        ),
      ];
      final report = sample(descriptors: descriptors);
      descriptors.clear();
      expect(report.descriptors, hasLength(1));
      expect(() => report.descriptors.clear(), throwsUnsupportedError);
    });

    test('invalid JSON schema and field types are rejected', () {
      final map = sample().toJson();
      expect(
        () => CapabilityReport.fromJson({...map, 'schemaVersion': 2}),
        throwsFormatException,
      );
      expect(
        () => CapabilityReport.fromJson({...map, 'architecture': 42}),
        throwsFormatException,
      );
      expect(
        () => CapabilityReport.fromJson({...map, 'descriptors': 'bad'}),
        throwsFormatException,
      );
      expect(
        () => CapabilityReport.fromJson({
          ...map,
          'descriptors': [
            {'id': 'device.camera', 'availability': 'unknown'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('non-UTC observation and missing timezone are rejected', () {
      expect(
        () => CapabilityReport(
          platform: 'android',
          architecture: 'arm64',
          observedAt: DateTime(2026, 11, 17, 14),
        ),
        throwsArgumentError,
      );
      expect(
        () => CapabilityReport.fromJson({
          ...sample().toJson(),
          'observedAt': '2026-11-17T14:00:00',
        }),
        throwsFormatException,
      );
    });
  });
}
