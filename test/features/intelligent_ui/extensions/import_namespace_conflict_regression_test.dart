import 'package:Kelivo/features/intelligent_ui/extensions/extension_manifest.dart';
import 'package:Kelivo/features/intelligent_ui/extensions/extension_registry.dart';
import 'package:Kelivo/features/intelligent_ui/protocol/ui_extension_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late UiExtensionImportParser parser;
  setUp(() {
    final registry = UiExtensionRegistry();
    for (final version in ['1.2.3', '1.2.4']) {
      registry.register(
        UiExtensionManifest(
          packageId: 'example.widgets',
          version: version,
          runtime: UiExtensionRuntime.sandboxedWeb,
          components: [
            UiExtensionComponent(
              name: 'Viewer',
              properties: {'name': UiExtensionValueType.string},
            ),
          ],
        ).toJson(),
      );
    }
    parser = UiExtensionImportParser(registry);
  });

  test(
    'pinned namespace resolves a canonical immutable component identity',
    () {
      parser.parse('use example.widgets@1.2.3 as widgets');
      parser.parse('import widgets.Viewer as Pane');
      expect(parser.resolveComponent('Pane'), 'example.widgets@1.2.3/Viewer');
      expect(() => parser.importedComponents.clear(), throwsUnsupportedError);
    },
  );

  test('aliases cannot be silently rebound to another package version', () {
    parser.parse('use example.widgets@1.2.3 as widgets');
    expect(
      () => parser.parse('use example.widgets@1.2.4 as widgets'),
      throwsFormatException,
    );
    parser.parse('import widgets.Viewer as Pane');
    expect(
      () => parser.parse('import widgets.Viewer as Pane'),
      throwsFormatException,
    );
    expect(parser.resolveComponent('Pane'), 'example.widgets@1.2.3/Viewer');
  });

  test(
    'unregistered versions, unknown namespaces and reserved names fail closed',
    () {
      expect(
        () => parser.parse('use example.widgets@9.9.9 as widgets'),
        throwsFormatException,
      );
      expect(
        () => parser.parse('import missing.Viewer as Pane'),
        throwsFormatException,
      );
      expect(
        () => parser.parse('use example.widgets@1.2.3 as import'),
        throwsFormatException,
      );
      expect(parser.importedComponents, isEmpty);
    },
  );

  test(
    'malformed input and legacy native statements never become import grants',
    () {
      for (final source in [
        'node Card()',
        'state counter = 1',
        'use example.widgets@1.2.3 as widgets; shell',
        'use example.widgets@1.2.3 as x\nimport x.Viewer as P',
        'import widgets.Viewer as ../outside',
      ]) {
        expect(() => parser.parse(source), throwsFormatException);
      }
    },
  );
}
