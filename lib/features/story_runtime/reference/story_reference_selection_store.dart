import '../../../core/database/business_preferences.dart';
import '../../../core/services/json_blob_store.dart';
import 'story_reference_models.dart';

final class StoryReferenceSelection {
  const StoryReferenceSelection({
    required this.conversationId,
    this.invocations = const <StoryReferenceInvocation>[],
  });

  final String conversationId;
  final List<StoryReferenceInvocation> invocations;
}

abstract interface class StoryReferenceSelectionRepository {
  Future<StoryReferenceSelection> readForConversation(String conversationId);

  Future<void> writeForConversation(
    String conversationId,
    Iterable<StoryReferenceInvocation> invocations,
  );
}

/// Persistent per-conversation Reference Profile selection.
///
/// Turn-scoped invocations are deliberately rejected here: they belong only to
/// the in-flight request and must not become a hidden long-term style setting.
final class StoryReferenceSelectionStore
    extends JsonBlobStore<StoryReferenceSelection>
    implements StoryReferenceSelectionRepository {
  StoryReferenceSelectionStore(BusinessPreferences preferences)
    : super(preferences);

  static const String key = 'story_reference_selections_v1';

  @override
  String get storageKey => key;

  @override
  StoryReferenceSelection decodeItem(Map<String, dynamic> json) {
    final conversationId = _requiredString(json, 'conversation_id');
    final raw = json['invocations'];
    if (raw != null && raw is! List) {
      throw const FormatException('invalid_story_reference_invocations');
    }
    final invocations = <StoryReferenceInvocation>[];
    for (final item in (raw as List? ?? const <Object?>[])) {
      if (item is! Map) {
        throw const FormatException('invalid_story_reference_invocation');
      }
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final strengthRaw = map['strength'] ?? 0.65;
      if (strengthRaw is! num || strengthRaw.isNaN || strengthRaw.isInfinite) {
        throw const FormatException('invalid_story_reference_strength');
      }
      final strength = strengthRaw.toDouble();
      if (strength < 0 || strength > 1) {
        throw const FormatException('story_reference_strength_out_of_range');
      }
      final aspectsRaw = map['aspects'];
      if (aspectsRaw != null && aspectsRaw is! List) {
        throw const FormatException('invalid_story_reference_aspects');
      }
      final aspects = <StoryReferenceAspect>{};
      for (final aspectRaw in (aspectsRaw as List? ?? const <Object?>[])) {
        if (aspectRaw is! String) {
          throw const FormatException('invalid_story_reference_aspect');
        }
        try {
          aspects.add(
            StoryReferenceAspect.values.firstWhere(
              (value) => value.name == aspectRaw,
            ),
          );
        } on StateError {
          throw FormatException('unknown_story_reference_aspect:$aspectRaw');
        }
      }
      invocations.add(
        StoryReferenceInvocation(
          profileId: _requiredString(map, 'profile_id'),
          strength: strength,
          enabledAspects: Set.unmodifiable(aspects),
          turnScoped: false,
        ),
      );
    }
    invocations.sort((a, b) => a.profileId.compareTo(b.profileId));
    return StoryReferenceSelection(
      conversationId: conversationId,
      invocations: List.unmodifiable(invocations),
    );
  }

  @override
  Map<String, dynamic> encodeItem(StoryReferenceSelection item) =>
      <String, dynamic>{
        'conversation_id': item.conversationId,
        'invocations': [
          for (final invocation in item.invocations)
            <String, dynamic>{
              'profile_id': invocation.profileId,
              'strength': invocation.strength,
              'aspects': _sortedAspectNames(invocation.enabledAspects),
            },
        ],
      };

  @override
  Future<StoryReferenceSelection> readForConversation(
    String conversationId,
  ) async {
    final id = _normalizeId(conversationId);
    for (final selection in await readAll()) {
      if (selection.conversationId == id) return selection;
    }
    return StoryReferenceSelection(conversationId: id);
  }

  @override
  Future<void> writeForConversation(
    String conversationId,
    Iterable<StoryReferenceInvocation> invocations,
  ) {
    final id = _normalizeId(conversationId);
    final normalized = invocations.toList(growable: false);
    for (final invocation in normalized) {
      if (invocation.turnScoped) {
        throw ArgumentError.value(
          invocation.profileId,
          'invocations',
          'turn-scoped reference cannot be persisted',
        );
      }
    }
    normalized.sort((a, b) => a.profileId.compareTo(b.profileId));
    final seen = <String>{};
    for (final invocation in normalized) {
      if (!seen.add(invocation.profileId)) {
        throw ArgumentError.value(
          invocation.profileId,
          'invocations',
          'duplicate profile id',
        );
      }
    }

    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryReferenceSelection>[];
      var replaced = false;
      for (final item in items) {
        if (item.conversationId != id) {
          next.add(item);
          continue;
        }
        if (!replaced && normalized.isNotEmpty) {
          next.add(
            StoryReferenceSelection(
              conversationId: id,
              invocations: List.unmodifiable(normalized),
            ),
          );
          replaced = true;
        }
      }
      if (!replaced && normalized.isNotEmpty) {
        next.add(
          StoryReferenceSelection(
            conversationId: id,
            invocations: List.unmodifiable(normalized),
          ),
        );
      }
      next.sort((a, b) => a.conversationId.compareTo(b.conversationId));
      await writeAll(next);
    });
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('invalid_story_reference_$key');
  }
  return value.trim();
}

String _normalizeId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, 'id');
  return normalized;
}

List<String> _sortedAspectNames(Set<StoryReferenceAspect> aspects) {
  final values = aspects.map((aspect) => aspect.name).toList(growable: false)
    ..sort();
  return values;
}
