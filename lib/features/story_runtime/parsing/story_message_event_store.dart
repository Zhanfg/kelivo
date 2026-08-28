import '../../../core/services/json_blob_store.dart';
import '../models/story_runtime_models.dart';

/// Structured Story rendering data keyed by Kelivo's native assistant message.
///
/// The native ChatMessage remains the durable readable fallback. This sidecar
/// can therefore disappear, fail migration, or be disabled without making chat
/// history unreadable.
final class StoryMessageEventRecord {
  const StoryMessageEventRecord({
    required this.conversationId,
    required this.messageId,
    required this.turn,
    required this.updatedAt,
  });

  final String conversationId;
  final String messageId;
  final StoryTurn turn;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'conversationId': conversationId,
    'messageId': messageId,
    'turn': _turnToJson(turn),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory StoryMessageEventRecord.fromJson(Map<String, dynamic> json) =>
      StoryMessageEventRecord(
        conversationId: (json['conversationId'] as String).trim(),
        messageId: (json['messageId'] as String).trim(),
        turn: _turnFromJson(Map<String, dynamic>.from(json['turn'] as Map)),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

final class StoryMessageEventStore
    extends JsonBlobStore<StoryMessageEventRecord> {
  StoryMessageEventStore(super.preferences);

  static const String key = 'story_message_events_v1';

  @override
  String get storageKey => key;

  @override
  StoryMessageEventRecord decodeItem(Map<String, dynamic> json) =>
      StoryMessageEventRecord.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryMessageEventRecord item) =>
      item.toJson();

  Future<StoryMessageEventRecord?> readForMessage(String messageId) async {
    final id = messageId.trim();
    if (id.isEmpty) return null;
    for (final item in await readAll()) {
      if (item.messageId == id) return item;
    }
    return null;
  }

  Future<void> upsertRecord(StoryMessageEventRecord record) {
    return runExclusive(() async {
      final items = await readAll();
      final next = <StoryMessageEventRecord>[];
      var replaced = false;
      for (final item in items) {
        if (item.messageId != record.messageId) {
          next.add(item);
        } else if (!replaced) {
          next.add(record);
          replaced = true;
        }
      }
      if (!replaced) next.add(record);
      next.sort((a, b) => a.messageId.compareTo(b.messageId));
      await writeAll(next);
    });
  }

  Future<void> removeForMessage(String messageId) {
    return runExclusive(() async {
      final id = messageId.trim();
      if (id.isEmpty) return;
      final items = await readAll();
      final next = items.where((item) => item.messageId != id).toList();
      if (next.length != items.length) await writeAll(next);
    });
  }
}

Map<String, dynamic> _turnToJson(StoryTurn turn) => <String, dynamic>{
  'id': turn.id,
  'events': turn.events.map(_eventToJson).toList(growable: false),
};

StoryTurn _turnFromJson(Map<String, dynamic> json) => StoryTurn(
  id: json['id'] as String,
  events: ((json['events'] as List?) ?? const <Object?>[])
      .map((item) => _eventFromJson(Map<String, dynamic>.from(item as Map)))
      .toList(growable: false),
);

Map<String, dynamic> _eventToJson(StoryEvent event) => <String, dynamic>{
  'id': event.id,
  'type': event.type.name,
  'actor': <String, dynamic>{
    'type': event.actor.type.name,
    if (event.actor.characterId != null) 'characterId': event.actor.characterId,
  },
  'text': event.text
      .map(
        (span) => <String, dynamic>{
          'text': span.text,
          'effect': span.effect.name,
          'decoration': span.decoration.name,
          'motion': span.motion.name,
        },
      )
      .toList(growable: false),
  'choices': event.choices
      .map(
        (choice) => <String, dynamic>{
          'id': choice.id,
          'label': choice.label,
          if (choice.submitText != null) 'submitText': choice.submitText,
          'metadata': choice.metadata,
        },
      )
      .toList(growable: false),
  if (event.timeout != null) 'timeoutMs': event.timeout!.inMilliseconds,
  if (event.timeoutActionId != null) 'timeoutActionId': event.timeoutActionId,
  'metadata': event.metadata,
};

StoryEvent _eventFromJson(Map<String, dynamic> json) {
  final actorJson = Map<String, dynamic>.from(json['actor'] as Map);
  final actorType = StoryActorType.values.firstWhere(
    (item) => item.name == actorJson['type'],
  );
  final actor = switch (actorType) {
    StoryActorType.self => const StoryActorRef.self(),
    StoryActorType.world => const StoryActorRef.world(),
    StoryActorType.character => StoryActorRef.character(
      actorJson['characterId'] as String,
    ),
  };
  return StoryEvent(
    id: json['id'] as String,
    type: StoryEventType.values.firstWhere((item) => item.name == json['type']),
    actor: actor,
    text: ((json['text'] as List?) ?? const <Object?>[])
        .map((item) {
          final span = Map<String, dynamic>.from(item as Map);
          return StoryTextSpan(
            span['text'] as String,
            effect: StoryTextEffect.values.firstWhere(
              (value) => value.name == span['effect'],
            ),
            decoration: StoryTextDecoration.values.firstWhere(
              (value) => value.name == span['decoration'],
            ),
            motion: StoryTextMotion.values.firstWhere(
              (value) => value.name == span['motion'],
            ),
          );
        })
        .toList(growable: false),
    choices: ((json['choices'] as List?) ?? const <Object?>[])
        .map((item) {
          final choice = Map<String, dynamic>.from(item as Map);
          return StoryChoice(
            id: choice['id'] as String,
            label: choice['label'] as String,
            submitText: choice['submitText'] as String?,
            metadata: Map<String, Object?>.from(
              (choice['metadata'] as Map?) ?? const <String, Object?>{},
            ),
          );
        })
        .toList(growable: false),
    timeout: json['timeoutMs'] == null
        ? null
        : Duration(milliseconds: (json['timeoutMs'] as num).toInt()),
    timeoutActionId: json['timeoutActionId'] as String?,
    metadata: Map<String, Object?>.from(
      (json['metadata'] as Map?) ?? const <String, Object?>{},
    ),
  );
}
