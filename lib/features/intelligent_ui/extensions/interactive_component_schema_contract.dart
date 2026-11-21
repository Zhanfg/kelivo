/// #70 declarative schema prototype for UI extensions.
/// No Flutter widget tree, interpreter, or platform view is created here.
enum ExtensionInteractiveKind { tabs, tree, date }

final class InteractiveComponentSchema {
  InteractiveComponentSchema({
    required this.kind,
    required this.componentId,
    required List<String> itemIds,
    this.selectedId,
    this.minDateUtc,
    this.maxDateUtc,
  }) : itemIds = List.unmodifiable(itemIds) {
    final safe = RegExp(r'^[A-Za-z][A-Za-z0-9_:-]{0,63}$');
    if (!safe.hasMatch(componentId) ||
        this.itemIds.isEmpty ||
        this.itemIds.length > 128 ||
        this.itemIds.toSet().length != this.itemIds.length ||
        this.itemIds.any((id) => !safe.hasMatch(id)) ||
        (selectedId != null && !this.itemIds.contains(selectedId))) {
      throw ArgumentError('Invalid interactive component definition');
    }
    if (kind == ExtensionInteractiveKind.date) {
      if (minDateUtc == null ||
          maxDateUtc == null ||
          !minDateUtc!.isUtc ||
          !maxDateUtc!.isUtc ||
          maxDateUtc!.isBefore(minDateUtc!)) {
        throw ArgumentError('Invalid date constraints');
      }
    } else if (minDateUtc != null || maxDateUtc != null) {
      throw ArgumentError('Date bounds on non-date component');
    }
  }

  final ExtensionInteractiveKind kind;
  final String componentId;
  final List<String> itemIds;
  final String? selectedId;
  final DateTime? minDateUtc;
  final DateTime? maxDateUtc;

  /// Checks a proposed selection only; does not change UI or run code.
  bool accepts(String candidate) => itemIds.contains(candidate);
}
