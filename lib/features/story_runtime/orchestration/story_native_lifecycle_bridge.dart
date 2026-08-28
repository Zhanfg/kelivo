import '../../../core/database/business_preferences.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/tts/network_tts.dart';
import '../state/story_runtime_store.dart';
import '../state/story_scene_runtime_state.dart';
import '../voice/story_voice_context_store.dart';
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
/// assistant revision. Native TTS also remains authoritative: Story only
/// resolves semantic voice assignments and lets Kelivo's existing TTS provider
/// perform local, system or network playback.
final class StoryNativeLifecycleBridge {
  StoryNativeLifecycleBridge(BusinessPreferences preferences)
    : _commitService = StoryRuntimeCommitService(preferences),
      _sessionStore = StoryRuntimeStore(preferences),
      _sceneStore = StorySceneRuntimeStore(preferences),
      _worldTreeStore = StoryWorldTreeStore(preferences),
      _voiceStore = StoryVoiceRoutingStore(preferences),
      _voiceContextStore = StoryVoiceContextHistoryStore(preferences);

  final StoryRuntimeCommitService _commitService;
  final StoryRuntimeStore _sessionStore;
  final StorySceneRuntimeStore _sceneStore;
  final StoryWorldTreeStore _worldTreeStore;
  final StoryVoiceRoutingStore _voiceStore;
  final StoryVoiceContextHistoryStore _voiceContextStore;
  final StoryVoiceResolver _voiceResolver = const StoryVoiceResolver();

  /// Advances Story sidecar state for one successfully finalized native reply.
  ///
  /// When a structured event trailer is present, Story commits it first and
  /// then asks Kelivo's own ChatService to persist only the reader-visible
  /// Markdown. The sidecar is therefore optional for history readability.
  Future<StoryFinalizedCommitResult?> commitFinalizedAssistant(
    ChatMessage message, {
    ChatService? chatService,
  }) async {
    final result = await _commitService.commitAssistantMessage(message);
    final visible = result?.visibleText;
    if (visible != null && visible != message.content && chatService != null) {
      await chatService.updateMessage(message.id, content: visible);
    }
    return result;
  }

  /// Returns the active narrator assignment for a Story assistant message.
  ///
  /// Unlike [routeNarrator], this is backend-agnostic and can therefore return
  /// native local/system assignments as well as network assignments. Worldline
  /// scoping is enforced here so all playback entry points share one rule.
  Future<StoryVoiceAssignment?> resolveNarratorAssignment(
    ChatMessage message,
  ) async {
    if (message.role != 'assistant') return null;

    final session = await _sessionStore.readOrDefault(message.conversationId);
    if (!session.enabled) return null;

    final tree = await _worldTreeStore.readForConversation(
      message.conversationId,
    );
    if (tree == null) return null;

    final routing = await _voiceStore.readOrDefault(tree.worldTreeId);
    final narrator = routing.narrator;
    if (narrator == null) return null;
    if (narrator.worldlineId != null &&
        narrator.worldlineId != session.worldlineId) {
      return null;
    }
    return narrator;
  }

  /// Applies Story narrator semantics to Kelivo's currently selected network
  /// TTS service. Playback remains a single native TtsProvider request, so the
  /// provider's chunking, prefetch, seek and replay cache continue to work.
  ///
  /// Native local/system assignments deliberately return [selectedService]
  /// unchanged here; callers that support all backends should first use
  /// [resolveNarratorAssignment] and StoryVoicePlaybackService.speakAssignment.
  Future<TtsServiceOptions> routeNarrator({
    required ChatMessage message,
    required TtsServiceOptions selectedService,
    StorySpeechIntent intent = const StorySpeechIntent(),
  }) async {
    final narrator = await resolveNarratorAssignment(message);
    if (narrator == null || narrator.ttsServiceId != selectedService.id) {
      return selectedService;
    }

    final history = await _voiceContextStore.readForConversation(
      message.conversationId,
    );
    final scene = await _sceneStore.readOrDefault(message.conversationId);
    final context = history.windowFor(
      message.id,
      currentFallback: _stripHiddenComments(message.content),
      sceneHint: _sceneHint(scene),
    );

    return _voiceResolver
        .resolve(
          service: selectedService,
          assignment: narrator,
          intent: intent,
          context: context,
        )
        .service;
  }
}

String _stripHiddenComments(String input) =>
    input.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '').trim();

String? _sceneHint(StorySceneRuntimeState scene) {
  final parts = <String>[];
  if (scene.location?.trim().isNotEmpty == true) {
    parts.add('location=${scene.location!.trim()}');
  }
  if (scene.timeLabel?.trim().isNotEmpty == true) {
    parts.add('time=${scene.timeLabel!.trim()}');
  }
  if (scene.openLoops.isNotEmpty) {
    parts.add('open=${scene.openLoops.take(3).join(' | ')}');
  }
  return parts.isEmpty ? null : parts.join('; ');
}
