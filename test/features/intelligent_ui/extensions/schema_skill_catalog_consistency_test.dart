import 'dart:io';

import 'package:Kelivo/features/intelligent_ui/catalog/ui_catalog.dart';
import 'package:Kelivo/features/intelligent_ui/catalog/ui_guidance.dart';
import 'package:flutter_test/flutter_test.dart';

/// #78 read-only existing generated asset and Schema-to-Catalog regression.
/// No generated code or active CI pipeline is modified.
void main() {
  test(
    'each generated Visualize Skill asset exactly matches checked-in copy',
    () {
      final assets = UiGuidance.generateAssets();
      expect(assets, isNotEmpty);
      for (final entry in assets.entries) {
        expect(entry.key.startsWith('/'), isFalse);
        expect(entry.key.split('/').contains('..'), isFalse);
        final file = File('assets/skills/visualize/${entry.key}');
        expect(file.existsSync(), isTrue, reason: entry.key);
        expect(file.readAsStringSync(), entry.value, reason: entry.key);
      }
    },
  );

  test('all examples use registered components and stable native header', () {
    final declaration = RegExp(
      r'^[_a-zA-Z][_a-zA-Z0-9]*\s*=\s*([a-zA-Z][a-zA-Z0-9]*)\(',
    );
    expect(UiGuidance.examples, isNotEmpty);
    for (final example in UiGuidance.examples.entries) {
      final lines = example.value.split('\n');
      expect(lines.first, UiCatalog.header, reason: example.key);
      final components = <String>[];
      for (final line in lines) {
        final match = declaration.firstMatch(line);
        if (match != null) components.add(match.group(1)!);
      }
      expect(components, isNotEmpty, reason: example.key);
      expect(
        components.every(UiCatalog.components.containsKey),
        isTrue,
        reason: example.key,
      );
    }
  });

  test('Catalog validation cannot invent an unavailable runtime adapter', () {
    expect(UiCatalog.components.isNotEmpty, isTrue);
    expect(
      UiGuidance.generateAssets().keys.every((k) => !k.contains('..')),
      isTrue,
    );
  });
}
