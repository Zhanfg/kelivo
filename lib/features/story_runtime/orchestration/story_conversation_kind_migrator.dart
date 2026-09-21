import '../../../core/database/business_preferences.dart';
import '../../../core/models/conversation_kind.dart';
import '../../../core/services/chat/chat_service.dart';
import '../state/story_runtime_store.dart';
import '../state/story_scene_runtime_state.dart';
import '../world_tree/story_world_tree_store.dart';

/// One-way compatibility migration for Story conversations created before
/// ConversationKind existed.
///
/// Any conversation that owns Story sidecar state is Story forever, including
/// legacy sessions whose old enabled flag was switched off.
final class StoryConversationKindMigrator {
  // ignore: prefer_initializing_formals
  StoryConversationKindMigrator({
    required BusinessPreferences preferences,
    required ChatService chatService,
  }) : _store = StoryRuntimeStore(preferences),
       _sceneStore = StorySceneRuntimeStore(preferences),
       _worldTreeStore = StoryWorldTreeStore(preferences),
       _chatService = chatService;

  final StoryRuntimeStore _store;
  final StorySceneRuntimeStore _sceneStore;
  final StoryWorldTreeStore _worldTreeStore;
  final ChatService _chatService;

  Future<int> migrate() async {
    await _chatService.init();
    final ids = <String>{
      for (final session in await _store.readAll()) session.conversationId,
      for (final scene in await _sceneStore.readAll()) scene.conversationId,
      for (final tree in await _worldTreeStore.readAll())
        for (final worldline in tree.worldlines) worldline.conversationId,
    };

    var changed = 0;
    for (final id in ids) {
      final conversation = _chatService.getConversation(id);
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
