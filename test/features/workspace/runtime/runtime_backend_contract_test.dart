import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/workspace/runtime/runtime_backend_contract.dart';

void main() {
  RuntimeRequest req(String id, RuntimeCapability operation) => RuntimeRequest(
    id: id,
    environmentId: 'env:one',
    operation: operation,
    arguments: {'command': 'mock'},
  );
  test(
    'unsupported runtime fails closed without recording execution',
    () async {
      final backend = MockRuntimeBackend(backendId: 'test', capabilities: {});
      final result = await backend.run(req('r1', RuntimeCapability.exec));
      expect(result.status, RuntimeResultStatus.unsupported);
      expect(result.succeeded, isFalse);
      expect(backend.recordedRequests, isEmpty);
    },
  );
  test('mock capability remains a deterministic no-op', () async {
    final backend = MockRuntimeBackend(
      backendId: 'mock',
      capabilities: {RuntimeCapability.exec, RuntimeCapability.files},
    );
    final result = await backend.run(req('r2', RuntimeCapability.exec));
    expect(result.value, 'mock:exec');
    expect(backend.recordedRequests, ['r2']);
    expect(backend.capabilities, isNot(contains(RuntimeCapability.pty)));
  });
  test('input identifiers and oversized arguments rejected', () {
    expect(() => req('../bad', RuntimeCapability.exec), throwsArgumentError);
    expect(
      () => RuntimeRequest(
        id: 'safe',
        environmentId: 'env:one',
        operation: RuntimeCapability.exec,
        arguments: {'x': 'a' * 257},
      ),
      throwsArgumentError,
    );
  });
  test('capability snapshot is immutable', () {
    final provided = <RuntimeCapability>{RuntimeCapability.exec};
    final backend = MockRuntimeBackend(
      backendId: 'mock',
      capabilities: provided,
    );
    provided.add(RuntimeCapability.pty);
    expect(backend.capabilities, {RuntimeCapability.exec});
    expect(
      () => backend.capabilities.add(RuntimeCapability.files),
      throwsUnsupportedError,
    );
  });
}
