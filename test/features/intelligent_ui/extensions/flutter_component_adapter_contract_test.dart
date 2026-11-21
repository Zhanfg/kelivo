import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/extension_manifest.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/flutter_component_adapter_contract.dart';

void main() {
  UiExtensionManifest manifest({
    String version = '1.2.0',
    UiExtensionRuntime runtime = UiExtensionRuntime.compiledFlutter,
  }) => UiExtensionManifest(
    packageId: 'example.native',
    version: version,
    runtime: runtime,
    components: [
      UiExtensionComponent(
        name: 'Chart',
        properties: {'title': UiExtensionValueType.string},
      ),
    ],
  );

  test('exact compile-time package and version can use declared component', () {
    final registry = FlutterComponentAdapterContract([
      CompiledFlutterAdapter(
        packageId: 'example.native',
        version: '1.2.0',
        componentNames: ['Chart'],
      ),
    ]);
    expect(
      registry.resolve(manifest(), 'Chart'),
      FlutterAdapterDecision.supported,
    );
  });
  test(
    'missing build or version change requires rebuild, never runtime load',
    () {
      final empty = FlutterComponentAdapterContract(const []);
      expect(
        empty.resolve(manifest(), 'Chart'),
        FlutterAdapterDecision.rebuildRequired,
      );
      final registry = FlutterComponentAdapterContract([
        CompiledFlutterAdapter(
          packageId: 'example.native',
          version: '1.2.0',
          componentNames: ['Chart'],
        ),
      ]);
      expect(
        registry.resolve(manifest(version: '1.3.0'), 'Chart'),
        FlutterAdapterDecision.rebuildRequired,
      );
    },
  );
  test('Web extension and undeclared component denied', () {
    final registry = FlutterComponentAdapterContract([
      CompiledFlutterAdapter(
        packageId: 'example.native',
        version: '1.2.0',
        componentNames: ['Chart'],
      ),
    ]);
    expect(
      registry.resolve(
        manifest(runtime: UiExtensionRuntime.sandboxedWeb),
        'Chart',
      ),
      FlutterAdapterDecision.denied,
    );
    expect(
      registry.resolve(manifest(), 'Unknown'),
      FlutterAdapterDecision.denied,
    );
  });
  test('duplicate compiled adapters rejected', () {
    expect(
      () => FlutterComponentAdapterContract([
        CompiledFlutterAdapter(
          packageId: 'example.native',
          version: '1.2.0',
          componentNames: ['Chart'],
        ),
        CompiledFlutterAdapter(
          packageId: 'example.native',
          version: '1.2.0',
          componentNames: ['Chart'],
        ),
      ]),
      throwsArgumentError,
    );
  });
}
