import 'conversation.dart';

const String conversationKindExtrasKey = 'kelivo_conversation_kind';

enum ConversationKind { chat, story, agent }

ConversationKind conversationKindOf(Conversation conversation) {
  final raw = conversation.extras[conversationKindExtrasKey];
  if (raw is String) {
    for (final kind in ConversationKind.values) {
      if (kind.name == raw) return kind;
    }
  }
  return ConversationKind.chat;
}

Map<String, dynamic> conversationExtrasWithKind(
  Map<String, dynamic> source,
  ConversationKind kind,
) {
  return <String, dynamic>{
    ...source,
    conversationKindExtrasKey: kind.name,
  };
}

bool conversationBelongsToKind(
  Conversation conversation,
  ConversationKind kind,
) => conversationKindOf(conversation) == kind;
