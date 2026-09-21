import '../../../core/database/business_preferences.dart';
import '../../../core/models/conversation_kind.dart';
import '../../../core/services/chat/chat_service.dart';
import '../state/story_runtime_store.dart';

/// One-way compatibility migration for Story conversations created before
/// ConversationKind existed.
///
/// Any conversation that owns Story sidecar state is Story forever, including
/// legacy sessions whose old enabled flag was switched off.
final class StoryConversationKindMigrator {
  StoryConversationKindMigrator({
    required BusinessPreferences preferences,
    required ChatService chatService,
  }) : _store = StoryRuntimeStore(preferences),
       _chatService = chatService;

  final StoryRuntimeStore _store;
  final ChatService _chatService;

  Future<int> migrate() async {
    await _chatService.init();
    final sessions = await _store.readAll();
    var changed = 0;
    for (final session in sessions) {
      final conversation = _chatService.getConversation(session.conversationId);
      if (conversation == null ||
          conversationKindOf(conversation) == ConversationKind.story) {
        continue;
      }
      await _chatService.updateConversationExtras(
        conversation.id,
        (extras) => conversationExtrasWithKind(
          extras,
          ConversationKind.story,
        ),
      );
      changed++;
    }
    return changed;
  }
}
