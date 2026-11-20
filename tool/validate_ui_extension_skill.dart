import 'dart:io';

import 'package:Kelivo/features/intelligent_ui/catalog/ui_catalog.dart';
import 'package:Kelivo/features/intelligent_ui/catalog/ui_guidance.dart';

/// Offline, read-only verification of the generated Visualize skill and
/// catalog-backed example declarations. Exit 1 on drift or malformed examples.
/// Use: dart run tool/validate_ui_extension_skill.dart --check
void main(List<String> args) {
  if (args.length != 1 || args.single != '--check') {
    stderr.writeln(
      'Usage: dart run tool/validate_ui_extension_skill.dart --check',
    );
    exitCode = 64;
    return;
  }
  final failures = <String>[];
  final assets = UiGuidance.generateAssets();
  for (final entry in assets.entries) {
    if (entry.key.startsWith('/') || entry.key.split('/').contains('..')) {
      failures.add('Unsafe generated asset path');
      continue;
    }
    final file = File('assets/skills/visualize/${entry.key}');
    if (file.existsSync() && file.readAsStringSync() != entry.value) {
      failures.add('Generated skill differs: ${entry.key}');
    } else if (!file.existsSync()) {
      failures.add('Missing generated skill: ${entry.key}');
    }
  }
  final declaration = RegExp(
    r'^[_a-zA-Z][_a-zA-Z0-9]*\s*=\s*([a-zA-Z][a-zA-Z0-9]*)\(',
  );
  for (final example in UiGuidance.examples.entries) {
    final lines = example.value.split('\n');
    if (lines.isEmpty || lines.first != UiCatalog.header) {
      failures.add('Example ${example.key}: header drift');
    }
    if (!lines.any((line) => line.startsWith('root = '))) {
      failures.add('Example ${example.key}: missing root');
    }
    var nodeCount = 0;
    for (final line in lines) {
      final match = declaration.firstMatch(line);
      if (match != null) {
        nodeCount++;
        if (!UiCatalog.components.containsKey(match.group(1))) {
          failures.add(
            'Example ${example.key}: unknown node ${match.group(1)}',
          );
        }
      }
    }
    if (nodeCount == 0) failures.add('Example ${example.key}: no nodes');
  }
  if (failures.isNotEmpty) {
    for (final error in failures) {
      stderr.writeln(error);
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Skill validation passed: ${assets.length} assets, '
    '${UiGuidance.examples.length} catalog examples.',
  );
}
