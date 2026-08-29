import '../../../core/services/json_blob_store.dart';

/// Persisted scene/runtime state for one Story conversation.
///
/// This is separate from the lightweight StoryRuntimeSessionState so mode
/// toggling remains cheap while continuity-heavy scene data can evolve without
/// changing Kelivo's Conversation schema.
final class StorySceneRuntimeState {
  const StorySceneRuntimeState({
    required this.conversationId,
    this.worldTreeId,
    this.worldlineId,
    this.sceneId,
    this.location,
    this.timeLabel,
    this.participantCharacterIds = const <String>[],
    this.pov = 'self',
    this.activeSkillIds = const <String>[],
    this.openLoops = const <String>[],
    this.continuityState = const <String, Object?>{},
    this.serialState = const <String, Object?>{},
    this.revision = 0,
  }) : assert(conversationId != ''),
       assert(revision >= 0);

  final String conversationId;
  final String? worldTreeId;
  final String? worldlineId;
  final String? sceneId;
  final String? location;
  final String? timeLabel;
  final List<String> participantCharacterIds;
  final String pov;
  final List<String> activeSkillIds;
  final List<String> openLoops;
  final Map<String, Object?> continuityState;
  final Map<String, Object?> serialState;
  final int revision;

  StorySceneRuntimeState copyWith({
    String? worldTreeId,
    String? worldlineId,
    String? sceneId,
    String? location,
    String? timeLabel,
    List<String>? participantCharacterIds,
    String? pov,
    List<String>? activeSkillIds,
    List<String>? openLoops,
    Map<String, Object?>? continuityState,
    Map<String, Object?>? serialState,
    int? revision,
    bool clearWorldTreeId = false,
    bool clearWorldlineId = false,
    bool clearSceneId = false,
    bool clearLocation = false,
    bool clearTimeLabel = false,
  }) => StorySceneRuntimeState(
    conversationId: conversationId,
    worldTreeId: clearWorldTreeId ? null : (worldTreeId ?? this.worldTreeId),
    worldlineId: clearWorldlineId ? null : (worldlineId ?? this.worldlineId),
    sceneId: clearSceneId ? null : (sceneId ?? this.sceneId),
    location: clearLocation ? null : (location ?? this.location),
    timeLabel: clearTimeLabel ? null : (timeLabel ?? this.timeLabel),
    participantCharacterIds:
        participantCharacterIds ?? this.participantCharacterIds,
    pov: pov ?? this.pov,
    activeSkillIds: activeSkillIds ?? this.activeSkillIds,
    openLoops: openLoops ?? this.openLoops,
    continuityState: continuityState ?? this.continuityState,
    serialState: serialState ?? this.serialState,
    revision: revision ?? this.revision,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'conversationId': conversationId,
    if (worldTreeId != null) 'worldTreeId': worldTreeId,
    if (worldlineId != null) 'worldlineId': worldlineId,
    if (sceneId != null) 'sceneId': sceneId,
    if (location != null) 'location': location,
    if (timeLabel != null) 'timeLabel': timeLabel,
    'participantCharacterIds': participantCharacterIds,
    'pov': pov,
    'activeSkillIds': activeSkillIds,
    'openLoops': openLoops,
    'continuityState': continuityState,
    'serialState': serialState,
    'revision': revision,
  };

  factory StorySceneRuntimeState.fromJson(Map<String, dynamic> json) =>
      StorySceneRuntimeState(
        conversationId: (json['conversationId'] as String).trim(),
        worldTreeId: _optional(json['worldTreeId']),
        worldlineId: _optional(json['worldlineId']),
        sceneId: _optional(json['sceneId']),
        location: _optional(json['location']),
        timeLabel: _optional(json['timeLabel']),
        participantCharacterIds:
            ((json['participantCharacterIds'] as List?) ?? const <Object?>[])
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false),
        pov: _optional(json['pov']) ?? 'self',
        activeSkillIds: ((json['activeSkillIds'] as List?) ?? const <Object?>[])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        openLoops: ((json['openLoops'] as List?) ?? const <Object?>[])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        continuityState: Map<String, Object?>.from(
          (json['continuityState'] as Map?) ?? const <String, Object?>{},
        ),
        serialState: Map<String, Object?>.from(
          (json['serialState'] as Map?) ?? const <String, Object?>{},
        ),
        revision: (json['revision'] as num?)?.toInt() ?? 0,
      );
}

abstract interface class StorySceneRuntimeRepository {
  Future<StorySceneRuntimeState> readOrDefault(String conversationId);
  Future<void> upsert(StorySceneRuntimeState state);
}

final class StorySceneRuntimeStore extends JsonBlobStore<StorySceneRuntimeState>
    implements StorySceneRuntimeRepository {
  StorySceneRuntimeStore(super.preferences);

  static const String key = 'story_scene_runtime_v1';

  @override
  String get storageKey => key;

  @override
  StorySceneRuntimeState decodeItem(Map<String, dynamic> json) =>
      StorySceneRuntimeState.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StorySceneRuntimeState item) => item.toJson();

  @override
  Future<StorySceneRuntimeState> readOrDefault(String conversationId) async {
    final id = _required(conversationId);
    for (final item in await readAll()) {
      if (item.conversationId == id) return item;
    }
    return StorySceneRuntimeState(conversationId: id);
  }

  @override
  Future<void> upsert(StorySceneRuntimeState state) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StorySceneRuntimeState>[];
      var replaced = false;
      for (final item in items) {
        if (item.conversationId != state.conversationId) {
          next.add(item);
        } else if (!replaced) {
          next.add(state);
          replaced = true;
        }
      }
      if (!replaced) next.add(state);
      next.sort((a, b) => a.conversationId.compareTo(b.conversationId));
      await writeAll(next);
    });
  }
}

String _required(String value) {
  final id = value.trim();
  if (id.isEmpty) throw ArgumentError.value(value, 'conversationId');
  return id;
}

String? _optional(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
