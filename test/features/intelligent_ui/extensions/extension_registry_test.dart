import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/extension_registry.dart';

Map<String, Object?> manifest(String version) => {
  'schemaVersion': 1,
  'packageId': 'demo.widgets',
  'version': version,
  'runtime': 'sandboxed_web',
  'components': [
    {
      'name': 'Counter',
      'properties': {'value': 'number'},
      'required': ['value'],
    },
  ],
  'requestedCapabilities': <String>[],
};

void main() {
  test('strict manifest parsing and duplicate registration', () {
    final registry = UiExtensionRegistry();
    registry.register(manifest('1.0.0'));
    expect(registry.list(), hasLength(1));
    expect(() => registry.register(manifest('1.0.0')), throwsStateError);
    expect(
      () => registry.register({...manifest('1.1.0'), 'evil': true}),
      throwsFormatException,
    );
  });

  test('pin, resolve and uninstall guard', () {
    final registry = UiExtensionRegistry();
    registry.register(manifest('1.0.0'));
    registry.register(manifest('1.1.0'));
    expect(registry.resolve('demo.widgets'), isNull);
    registry.pin('demo.widgets', '1.0.0');
    expect(registry.resolve('demo.widgets')!.version, '1.0.0');
    expect(() => registry.uninstall('demo.widgets', '1.0.0'), throwsStateError);
    registry.unpin('demo.widgets');
    registry.uninstall('demo.widgets', '1.0.0');
    expect(registry.list(packageId: 'demo.widgets'), hasLength(1));
    expect(() => registry.pin('demo.widgets', '9.0.0'), throwsStateError);
  });

  test('compiled native plugin cannot be registered dynamically', () {
    final registry = UiExtensionRegistry();
    expect(
      () => registry.register({
        ...manifest('1.0.0'),
        'runtime': 'compiled_flutter',
      }),
      throwsStateError,
    );
  });
}
