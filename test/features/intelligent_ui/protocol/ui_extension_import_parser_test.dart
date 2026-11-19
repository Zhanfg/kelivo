import 'package:Kelivo/features/intelligent_ui/extensions/extension_manifest.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/extension_registry.dart';
import 'package:Kelivo/features/intelligent_ui/protocol/ui_extension_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UiExtensionRegistry registry;
  late UiExtensionImportParser parser;

  setUp(() {
    registry = UiExtensionRegistry();
    registry.register(
      UiExtensionManifest(
        packageId: 'example.model3d',
        version: '1.2.3',
        runtime: UiExtensionRuntime.sandboxedWeb,
        components: [
          UiExtensionComponent(
            name: 'Viewer',
            properties: {'source': UiExtensionValueType.string},
          ),
        ],
      ).toJson(),
    );
    parser = UiExtensionImportParser(registry);
  });

  test('version pinned use/import yields canonical component identity', () {
    parser.parse('use example.model3d@1.2.3 as model');
    parser.parse('import model.Viewer as Viewer3D');
    expect(parser.resolveComponent('Viewer3D'), 'example.model3d@1.2.3/Viewer');
    expect(parser.importedComponents, hasLength(1));
    expect(
      () => parser.importedComponents['other'] = 'unsafe',
      throwsUnsupportedError,
    );
  });

  test('unregistered and unpinned versions fail closed', () {
    expect(
      () => parser.parse('use example.model3d@1.2.4 as model'),
      throwsFormatException,
    );
    expect(
      () => parser.parse('use example.model3d as model'),
      throwsFormatException,
    );
  });

  test('missing namespace or component never resolves', () {
    expect(
      () => parser.parse('import model.Viewer as Item'),
      throwsFormatException,
    );
    parser.parse('use example.model3d@1.2.3 as model');
    expect(
      () => parser.parse('import model.Missing as Item'),
      throwsFormatException,
    );
    expect(parser.resolveComponent('Item'), isNull);
  });

  test('duplicate and reserved aliases are rejected', () {
    parser.parse('use example.model3d@1.2.3 as model');
    expect(
      () => parser.parse('use example.model3d@1.2.3 as model'),
      throwsFormatException,
    );
    expect(
      () => parser.parse('import model.Viewer as import'),
      throwsFormatException,
    );
    parser.parse('import model.Viewer as Viewer3D');
    expect(
      () => parser.parse('import model.Viewer as Viewer3D'),
      throwsFormatException,
    );
  });

  test('extra syntax, injection strings and line breaks fail closed', () {
    for (final source in [
      'use example.model3d@1.2.3 as model;',
      'use example.model3d@1.2.3 as model\nnode unsafe',
      'import model.Viewer as X()',
      'import model.Viewer as ../outside',
      'use example.model3d@1.2.3 as $root',
    ]) {
      expect(() => parser.parse(source), throwsFormatException);
    }
  });

  test('v1 parser input is not interpreted as an extension directive', () {
    for (final source in ['node Card()', 'state counter = 1']) {
      expect(() => parser.parse(source), throwsFormatException);
    }
  });
}
