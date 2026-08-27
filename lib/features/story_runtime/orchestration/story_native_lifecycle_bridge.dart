import '../../../core/database/business_preferences.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/services/tts/network_tts.dart';
import '../state/story_runtime_store.dart';
import '../voice/story_voice_models.dart';
import '../voice/story_voice_routing.dart';
import '../voice/story_voice_store.dart';
import '../world_tree/story_world_tree_store.dart';
import 'story_runtime_commit_service.dart';

/// Small integration seam between Kelivo's native chat/TTS lifecycle and
/// Story Runtime.
///
/// Native chat remains authoritative for message persistence. Story state is a
/// sidecar transaction committed only after Kelivo reports a successful final
/// assistant revision. Native TTS also remains authoritative: Story may route
/// the already-selected network service through a narrator assignment, but it
/// never creates a parallel playback stack or copies provider credentials.
final class StoryNativeLifecycleBridge {
  StoryNativeLifecycleBridge(BusinessPreferences preferences)
    : _commitService = StoryRuntimeCommitService(preferences),
      _sessionStore = StoryRuntimeStore(preferences),
      _worldTreeStore = StoryWorldTreeStore(preferences),
      _voiceStore = StoryVoiceRoutingStore(preferences);

  final StoryRuntimeCommitService _commitService;
  final StoryRuntimeStore _sessionStore;
  final StoryWorldTreeStore _worldTreeStore;
  final StoryVoiceRoutingStore _voiceStore;
  final StoryVoiceResolver _voiceResolver = const StoryVoiceResolver();

  /// Advances Story sidecar state for one successfully finalized native reply.
  ///
  /// The commit service is idempotent for replayed finalize callbacks, so this
  /// method is safe to call from controller recovery paths as well.
  Future<void> commitFinalizedAssistant(ChatMessage message) {
    return _commitService.commitAssistantMessage(message);
  }

  /// Applies the Story narrator voice to Kelivo's currently selected network
  /// TTS service when the assignment targets that exact service.
  ///
  /// Returning [selectedService] unchanged is intentional. Story Mode must not
  /// silently switch credentials/endpoints when the configured narrator points
  /// at a different service. A future UI may explicitly resolve another native
  /// service by id and pass it here.
  Future<TtsServiceOptions> routeNarrator({
    required ChatMessage message,
    required TtsServiceOptions selectedService,
    StorySpeechIntent intent = const StorySpeechIntent(),
  }) async {
    if (message.role != 'assistant') return selectedService;

    final session = await _sessionStore.readOrDefault(message.conversationId);
    if (!session.enabled) return selectedService;

    final tree = await _worldTreeStore.readForConversation(
      message.conversationId,
    );
    if (tree == null) return selectedService;

    final routing = await _voiceStore.readOrDefault(tree.worldTreeId);
    final narrator = routing.narrator;
    if (narrator == null) return selectedService;

    // A narrator can optionally be scoped to one branch. Never leak a branch
    // voice assignment into a sibling worldline.
    if (narrator.worldlineId != null &&
        narrator.worldlineId != session.worldlineId) {
      return selectedService;
    }

    if (narrator.ttsServiceId != selectedService.id) {
      return selectedService;
    }

    return _voiceResolver
        .resolve(service: selectedService, assignment: narrator, intent: intent)
        .service;
  }
}
