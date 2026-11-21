import 'package:Kelivo/features/intelligent_ui/extensions/interactive_component_schema_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  InteractiveComponentSchema schema(
    ExtensionInteractiveKind kind, {
    List<String> ids = const ['first', 'second'],
    String? selected,
    DateTime? min,
    DateTime? max,
  }) => InteractiveComponentSchema(
    kind: kind,
    componentId: 'Panel',
    itemIds: ids,
    selectedId: selected,
    minDateUtc: min,
    maxDateUtc: max,
  );

  test('Tabs and Tree schemas accept bounded declarative selections', () {
    for (final kind in [
      ExtensionInteractiveKind.tabs,
      ExtensionInteractiveKind.tree,
    ]) {
      final source = <String>['first', 'second'];
      final item = schema(kind, ids: source, selected: 'first');
      source.clear();
      expect(item.itemIds, ['first', 'second']);
      expect(item.accepts('second'), isTrue);
      expect(item.accepts('unknown'), isFalse);
      expect(() => item.itemIds.add('third'), throwsUnsupportedError);
    }
  });

  test('Date schemas require ordered explicit UTC bounds', () {
    final min = DateTime.utc(2026, 1, 1);
    final max = DateTime.utc(2027, 1, 1);
    final date = schema(ExtensionInteractiveKind.date, min: min, max: max);
    expect(date.minDateUtc, min);
    expect(date.maxDateUtc, max);
    expect(() => schema(ExtensionInteractiveKind.date), throwsArgumentError);
    expect(
      () => schema(ExtensionInteractiveKind.date, min: max, max: min),
      throwsArgumentError,
    );
  });

  test('duplicate, unsafe, oversized or unknown selection is refused', () {
    expect(
      () => schema(ExtensionInteractiveKind.tabs, ids: ['first', 'first']),
      throwsArgumentError,
    );
    expect(
      () => schema(ExtensionInteractiveKind.tree, ids: ['../secret']),
      throwsArgumentError,
    );
    expect(
      () => schema(
        ExtensionInteractiveKind.tabs,
        ids: ['first'],
        selected: 'second',
      ),
      throwsArgumentError,
    );
    expect(
      () => schema(
        ExtensionInteractiveKind.tabs,
        ids: List.generate(129, (i) => 'item$i'),
      ),
      throwsArgumentError,
    );
  });

  test('non-date components reject date-specific constraints', () {
    expect(
      () => schema(
        ExtensionInteractiveKind.tabs,
        min: DateTime.utc(2026),
        max: DateTime.utc(2027),
      ),
      throwsArgumentError,
    );
  });
}
