/// Cache-aware prompt assembly primitives for Story Mode.
///
/// Modules do not append directly to the system prompt. They contribute typed
/// sections here so volatile data cannot accidentally invalidate an otherwise
/// reusable provider prefix.
library;

enum StoryPromptStability {
  frozen,
  epochStable,
  appendOnly,
  volatile,
  localOnly,
}

final class StoryPromptContribution {
  const StoryPromptContribution({
    required this.id,
    required this.stability,
    required this.content,
    this.order = 0,
  }) : assert(id != '');

  final String id;
  final StoryPromptStability stability;
  final String content;

  /// Deterministic ordering inside one stability class. Ties are resolved by
  /// [id], so Set/Map iteration order cannot perturb the provider prefix.
  final int order;
}

final class StoryPromptCacheDiagnostics {
  const StoryPromptCacheDiagnostics({
    required this.frozenChars,
    required this.epochStableChars,
    required this.appendOnlyChars,
    required this.volatileChars,
    required this.localOnlyChars,
  });

  final int frozenChars;
  final int epochStableChars;
  final int appendOnlyChars;
  final int volatileChars;
  final int localOnlyChars;

  int get providerVisibleChars =>
      frozenChars + epochStableChars + appendOnlyChars + volatileChars;

  int get stablePrefixChars => frozenChars + epochStableChars;

  double get stablePrefixRatio {
    final total = providerVisibleChars;
    return total == 0 ? 1 : stablePrefixChars / total;
  }
}

final class StoryPromptCachePlan {
  StoryPromptCachePlan._(this._sections);

  factory StoryPromptCachePlan.compile(
    Iterable<StoryPromptContribution> contributions,
  ) {
    final byId = <String, StoryPromptContribution>{};
    for (final contribution in contributions) {
      if (byId.containsKey(contribution.id)) {
        throw ArgumentError.value(
          contribution.id,
          'contributions',
          'duplicate story prompt contribution id',
        );
      }
      byId[contribution.id] = contribution;
    }

    final sections = byId.values.toList(growable: false)
      ..sort((a, b) {
        final stabilityOrder =
            _stabilityOrder(a.stability).compareTo(_stabilityOrder(b.stability));
        if (stabilityOrder != 0) return stabilityOrder;
        final explicitOrder = a.order.compareTo(b.order);
        if (explicitOrder != 0) return explicitOrder;
        return a.id.compareTo(b.id);
      });

    return StoryPromptCachePlan._(List.unmodifiable(sections));
  }

  final List<StoryPromptContribution> _sections;

  List<StoryPromptContribution> get sections => _sections;

  List<StoryPromptContribution> get providerSections => List.unmodifiable(
    _sections.where(
      (section) => section.stability != StoryPromptStability.localOnly,
    ),
  );

  List<StoryPromptContribution> get localOnlySections => List.unmodifiable(
    _sections.where(
      (section) => section.stability == StoryPromptStability.localOnly,
    ),
  );

  /// Provider-visible sections in canonical cache order:
  /// frozen -> epoch-stable -> append-only -> volatile.
  String buildProviderText({String separator = '\n\n'}) {
    return providerSections
        .where((section) => section.content.isNotEmpty)
        .map((section) => section.content)
        .join(separator);
  }

  bool hasSameStablePrefixAs(StoryPromptCachePlan other) {
    final mine = _stablePrefixSections();
    final theirs = other._stablePrefixSections();
    if (mine.length != theirs.length) return false;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i].id != theirs[i].id ||
          mine[i].content != theirs[i].content ||
          mine[i].order != theirs[i].order ||
          mine[i].stability != theirs[i].stability) {
        return false;
      }
    }
    return true;
  }

  StoryPromptCacheDiagnostics get diagnostics {
    int chars(StoryPromptStability stability) => _sections
        .where((section) => section.stability == stability)
        .fold(0, (sum, section) => sum + section.content.length);

    return StoryPromptCacheDiagnostics(
      frozenChars: chars(StoryPromptStability.frozen),
      epochStableChars: chars(StoryPromptStability.epochStable),
      appendOnlyChars: chars(StoryPromptStability.appendOnly),
      volatileChars: chars(StoryPromptStability.volatile),
      localOnlyChars: chars(StoryPromptStability.localOnly),
    );
  }

  List<StoryPromptContribution> _stablePrefixSections() => _sections
      .where(
        (section) =>
            section.stability == StoryPromptStability.frozen ||
            section.stability == StoryPromptStability.epochStable,
      )
      .toList(growable: false);
}

int _stabilityOrder(StoryPromptStability stability) => switch (stability) {
  StoryPromptStability.frozen => 0,
  StoryPromptStability.epochStable => 1,
  StoryPromptStability.appendOnly => 2,
  StoryPromptStability.volatile => 3,
  StoryPromptStability.localOnly => 4,
};
