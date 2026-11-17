import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/extension_manifest.dart';

void main() {
  UiExtensionComponent component({
    String name = 'ModelViewer',
    Map<String, UiExtensionValueType>? properties,
  }) => UiExtensionComponent(
    name: name,
    properties:
        properties ??
        {
          'source': UiExtensionValueType.string,
          'interactive': UiExtensionValueType.boolean,
        },
    requiredProperties: {'source'},
  );

  UiExtensionManifest manifest({
    String packageId = 'example.model3d',
    String version = '1.2.3',
    UiExtensionRuntime runtime = UiExtensionRuntime.sandboxedWeb,
    Set<String> capabilities = const {'artifact.read'},
    List<UiExtensionComponent>? components,
  }) => UiExtensionManifest(
    packageId: packageId,
    version: version,
    runtime: runtime,
    components: components ?? [component()],
    requestedCapabilities: capabilities,
  );

  test('schema v1 roundtrip and namespaced reference', () {
    final model = manifest();
    final json = model.toJson();
    expect(json['schemaVersion'], 1);
    expect(UiExtensionManifest.fromJson(json).toJson(), json);
    expect(
      model.componentReference('ModelViewer'),
      'example.model3d@1.2.3/ModelViewer',
    );
    expect(() => model.componentReference('Missing'), throwsArgumentError);
  });

  test('runtime declarations distinguish sandbox from compiled Flutter', () {
    expect(
      UiExtensionRuntime.parse('sandboxed_web'),
      UiExtensionRuntime.sandboxedWeb,
    );
    expect(
      UiExtensionRuntime.parse('compiled_flutter'),
      UiExtensionRuntime.compiledFlutter,
    );
    expect(
      () => UiExtensionRuntime.parse('load_dart_source'),
      throwsFormatException,
    );
  });

  test('cannot request host execution, root or ambient MCP access', () {
    for (final capability in [
      'shell',
      'root',
      'device.lsposed',
      'file.all',
      'mcp.unrestricted',
    ]) {
      expect(() => manifest(capabilities: {capability}), throwsArgumentError);
    }
    expect(manifest().requestedCapabilities, {'artifact.read'});
  });

  test('rejects invalid package IDs and semver', () {
    expect(() => manifest(packageId: '../bad'), throwsArgumentError);
    expect(() => manifest(packageId: 'Example.Plugin'), throwsArgumentError);
    expect(() => manifest(version: '1.2'), throwsArgumentError);
    expect(() => manifest(version: '01.0.0'), throwsArgumentError);
  });

  test('component properties and required set are immutable', () {
    final props = {'source': UiExtensionValueType.string};
    final item = UiExtensionComponent(
      name: 'Preview',
      properties: props,
      requiredProperties: {'source'},
    );
    props.clear();
    expect(item.properties, hasLength(1));
    expect(() => item.properties.clear(), throwsUnsupportedError);
    expect(() => item.requiredProperties.add('other'), throwsUnsupportedError);
  });

  test('duplicate component names and unknown properties rejected', () {
    expect(
      () => manifest(components: [component(), component()]),
      throwsArgumentError,
    );
    expect(
      () => UiExtensionComponent(
        name: 'Bad',
        properties: {'foo': UiExtensionValueType.number},
        requiredProperties: {'unknown'},
      ),
      throwsArgumentError,
    );
  });

  test('unknown schema, invalid component and extra keys fail closed', () {
    final json = manifest().toJson();
    expect(
      () => UiExtensionManifest.fromJson({...json, 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => UiExtensionManifest.fromJson({
        ...json,
        'javascriptSource': 'alert(1)',
      }),
      throwsFormatException,
    );
    expect(
      () => UiExtensionManifest.fromJson({
        ...json,
        'requestedCapabilities': ['artifact.read', 'artifact.read'],
      }),
      throwsFormatException,
    );
    final item = Map<String, Object?>.from(
      (json['components'] as List).first as Map,
    );
    item['properties'] = {'source': 'executable'};
    expect(
      () => UiExtensionManifest.fromJson({
        ...json,
        'components': [item],
      }),
      throwsFormatException,
    );
  });

  test('model is detached from caller component collections', () {
    final list = [component()];
    final model = manifest(components: list);
    list.clear();
    expect(model.components, hasLength(1));
    expect(() => model.components.clear(), throwsUnsupportedError);
  });
}
