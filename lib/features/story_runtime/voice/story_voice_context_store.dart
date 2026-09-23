import '../../../core/services/json_blob_store.dart';
import 'story_voice_context.dart';

final class StoryVoiceContextEntry {
  const StoryVoiceContextEntry({
    required this.messageId,
    required this.text,
    required this.updatedAt,
  });

  final String messageId;
  final String text;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'messageId': messageId,
    'text': text,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory StoryVoiceContextEntry.fromJson(Map<String, dynamic> json) =>
      StoryVoiceContextEntry(
        messageId: (json['messageId'] as String).trim(),
        text: (json['text'] as String).trim(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

final class StoryVoiceContextHistory {
  const StoryVoiceContextHistory({
    required this.conversationId,
    this.entries = const <StoryVoiceContextEntry>[],
  });

  final String conversationId;
  final List<StoryVoiceContextEntry> entries;

  StoryVoiceContextWindow? windowFor(
    String messageId, {
    String? currentFallback,
    String? sceneHint,
  }) {
    final id = messageId.trim();
    if (id.isEmpty) return null;
    final index = entries.indexWhere((entry) => entry.messageId == id);
    if (index < 0) {
      final current = currentFallback?.trim() ?? '';
      if (current.isEmpty) return null;
      return StoryVoiceContextWindow(current: current, sceneHint: sceneHint);
    }
    return StoryVoiceContextWindow(
      previous: index > 0 ? entries[index - 1].text : null,
      current: entries[index].text,
      next: index + 1 < entries.length ? entries[index + 1].text : null,
      sceneHint: sceneHint,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'conversationId': conversationId,
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
  };

  factory StoryVoiceContextHistory.fromJson(Map<String, dynamic> json) =>
      StoryVoiceContextHistory(
        conversationId: (json['conversationId'] as String).trim(),
        entries: ((json['entries'] as List?) ?? const <Object?>[])
            .map(
              (item) => StoryVoiceContextEntry.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
}

final class StoryVoiceContextHistoryStore
    extends JsonBlobStore<StoryVoiceContextHistory> {
  StoryVoiceContextHistoryStore(super.preferences);

  static const String key = 'story_voice_context_history_v1';
  static const int maxEntriesPerConversation = 96;

  @override
  String get storageKey => key;

  @override
  StoryVoiceContextHistory decodeItem(Map<String, dynamic> json) =>
      StoryVoiceContextHistory.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryVoiceContextHistory item) =>
      item.toJson();

  Future<StoryVoiceContextHistory> readForConversation(
    String conversationId,
  ) async {
    final id = _required(conversationId);
    for (final item in await readAll()) {
      if (item.conversationId == id) return item;
    }
    return StoryVoiceContextHistory(conversationId: id);
  }

  Future<void> record({
    required String conversationId,
    required String messageId,
    required String text,
  }) {
    return runExclusive(() async {
      final cid = _required(conversationId);
      final mid = _required(messageId);
      final clean = text.trim();
      if (clean.isEmpty) return;
      final all = await readAll();
      final next = <StoryVoiceContextHistory>[];
      var replacedHistory = false;
      for (final history in all) {
        if (history.conversationId != cid) {
          next.add(history);
          continue;
        }
        if (replacedHistory) continue;
        final entries = <StoryVoiceContextEntry>[
          for (final entry in history.entries)
            if (entry.messageId != mid) entry,
          StoryVoiceContextEntry(
            messageId: mid,
            text: clean,
            updatedAt: DateTime.now().toUtc(),
          ),
        ];
        final bounded = entries.length <= maxEntriesPerConversation
            ? entries
            : entries.sublist(entries.length - maxEntriesPerConversation);
        next.add(
          StoryVoiceContextHistory(
            conversationId: cid,
            entries: List.unmodifiable(bounded),
          ),
        );
        replacedHistory = true;
      }
      if (!replacedHistory) {
        next.add(
          StoryVoiceContextHistory(
            conversationId: cid,
            entries: <StoryVoiceContextEntry>[
              StoryVoiceContextEntry(
                messageId: mid,
                text: clean,
                updatedAt: DateTime.now().toUtc(),
              ),
            ],
          ),
        );
      }
      next.sort((a, b) => a.conversationId.compareTo(b.conversationId));
      await writeAll(next);
    });
  }
}

String _required(String value) {
  final text = value.trim();
  if (text.isEmpty) throw ArgumentError.value(value, 'value');
  return text;
}
