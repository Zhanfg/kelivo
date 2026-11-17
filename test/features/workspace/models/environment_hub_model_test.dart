import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/workspace/models/environment_hub_model.dart';

void main() {
  final date = DateTime.utc(2026, 11, 17, 14);

  EnvironmentInstanceSnapshot instance({
    String id = 'android-primary',
    EnvironmentBackend backend = EnvironmentBackend.androidProot,
    EnvironmentLifecycle state = EnvironmentLifecycle.running,
    int? used = 30,
    int? capacity = 100,
    List<EnvironmentPortSnapshot>? ports,
  }) => EnvironmentInstanceSnapshot(
    id: id,
    label: 'Ubuntu Workstation',
    backend: backend,
    lifecycle: state,
    distribution: 'ubuntu',
    version: '24.04.4',
    usedBytes: used,
    capacityBytes: capacity,
    ports:
        ports ??
        [
          EnvironmentPortSnapshot(
            port: 8080,
            protocol: EnvironmentPortProtocol.tcp,
            loopbackOnly: true,
          ),
        ],
  );

  EnvironmentHubSnapshot hub({
    List<EnvironmentInstanceSnapshot>? instances,
    String? selected = 'android-primary',
  }) => EnvironmentHubSnapshot(
    observedAt: date,
    selectedId: selected,
    instances: instances ?? [instance()],
  );

  test('model roundtrips through versioned JSON without device action', () {
    final data = hub().toJson();
    expect(data['schemaVersion'], 1);
    expect(EnvironmentHubSnapshot.fromJson(data).toJson(), data);
    expect(data.toString(), isNot(contains('password')));
    expect(data.toString(), isNot(contains('shellCommand')));
    expect(data.toString(), isNot(contains('privateKey')));
  });

  test('backend, lifecycle and port enum values are strict', () {
    for (final backend in EnvironmentBackend.values) {
      expect(EnvironmentBackend.parse(backend.wireName), backend);
    }
    for (final state in EnvironmentLifecycle.values) {
      expect(EnvironmentLifecycle.parse(state.wireName), state);
    }
    expect(
      () => EnvironmentBackend.parse('virtual_machine'),
      throwsFormatException,
    );
    expect(() => EnvironmentLifecycle.parse('unknown'), throwsFormatException);
    expect(() => EnvironmentPortProtocol.parse('quic'), throwsFormatException);
  });

  test('rejects invalid ports and duplicate observed endpoints', () {
    expect(
      () => EnvironmentPortSnapshot(
        port: 65536,
        protocol: EnvironmentPortProtocol.tcp,
        loopbackOnly: true,
      ),
      throwsArgumentError,
    );
    final observed = EnvironmentPortSnapshot(
      port: 8080,
      protocol: EnvironmentPortProtocol.tcp,
      loopbackOnly: true,
    );
    expect(() => instance(ports: [observed, observed]), throwsArgumentError);
  });

  test('enforces immutable data and consistent disk usage', () {
    final ports = <EnvironmentPortSnapshot>[];
    final env = instance(ports: ports);
    ports.add(
      EnvironmentPortSnapshot(
        port: 9000,
        protocol: EnvironmentPortProtocol.udp,
        loopbackOnly: true,
      ),
    );
    expect(env.ports, isEmpty);
    expect(() => env.ports.add(ports.first), throwsUnsupportedError);
    expect(() => instance(used: -1), throwsArgumentError);
    expect(() => instance(used: 110, capacity: 100), throwsArgumentError);
  });

  test('selected environment must exist and identifiers must be unique', () {
    expect(() => hub(selected: 'missing'), throwsArgumentError);
    expect(() => hub(instances: [instance(), instance()]), throwsArgumentError);
    expect(() => instance(id: '../../traverse'), throwsArgumentError);
  });

  test('rejects malformed or incompatible snapshot JSON', () {
    final json = hub().toJson();
    expect(
      () => EnvironmentHubSnapshot.fromJson({...json, 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => EnvironmentHubSnapshot.fromJson({
        ...json,
        'observedAt': '2026-11-17',
      }),
      throwsFormatException,
    );
    expect(
      () => EnvironmentHubSnapshot.fromJson({...json, 'instances': 'invalid'}),
      throwsFormatException,
    );
    expect(
      () =>
          EnvironmentHubSnapshot.fromJson({...json, 'credential': 'redacted'}),
      throwsFormatException,
    );
    final item = Map<String, Object?>.from(
      (json['instances'] as List).first as Map,
    );
    item['lifecycle'] = 'running_and_root';
    expect(
      () => EnvironmentHubSnapshot.fromJson({
        ...json,
        'instances': [item],
      }),
      throwsFormatException,
    );
  });

  test('copies the environment list and avoids shared mutation', () {
    final collection = [instance()];
    final source = hub(instances: collection);
    collection.clear();
    expect(source.instances.length, 1);
    expect(() => source.instances.clear(), throwsUnsupportedError);
  });
}
