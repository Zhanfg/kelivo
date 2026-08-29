import 'dart:convert';

import '../../../core/database/business_preferences.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/services/tts/local_tts.dart';
import '../../../core/services/tts/network_tts.dart';
import 'story_voice_context.dart';
import 'story_voice_models.dart';
import 'story_voice_routing.dart';

/// Stable pseudo service ids used by Story voice assignments for Kelivo's
/// native, non-network TTS backends.
const String storyLocalMossTtsServiceId = '__story_local_moss__';
const String storySystemTtsServiceId = '__story_system_tts__';

bool isStoryNativeTtsServiceId(String value) =>
    value == storyLocalMossTtsServiceId || value == storySystemTtsServiceId;

/// Adapter from Story semantic voice routing to Kelivo's existing TtsProvider.
///
/// It never owns network credentials, HTTP, audio queues or playback. Network,
/// Android-local MOSS and system TTS are all played through Kelivo's native TTS
/// provider so seek/pause/replay behavior stays in one stack.
final class StoryVoicePlaybackService {
  const StoryVoicePlaybackService({
    required this.preferences,
    required this.ttsProvider,
    this.resolver = const StoryVoiceResolver(),
  });

  final BusinessPreferences preferences;
  final TtsProvider ttsProvider;
  final StoryVoiceResolver resolver;

  Future<StoryResolvedVoiceRequest> resolve({
    required StoryVoiceAssignment assignment,
    StorySpeechIntent intent = const StorySpeechIntent(),
    StoryVoiceContextWindow? context,
  }) async {
    if (isStoryNativeTtsServiceId(assignment.ttsServiceId)) {
      throw StateError('story_voice_native_backend_has_no_network_request');
    }
    final service = await _readServiceById(assignment.ttsServiceId);
    if (service == null) {
      throw StateError(
        'story_voice_tts_service_not_found:${assignment.ttsServiceId}',
      );
    }
    if (!service.enabled) {
      throw StateError(
        'story_voice_tts_service_disabled:${assignment.ttsServiceId}',
      );
    }
    return resolver.resolve(
      service: service,
      assignment: assignment,
      intent: intent,
      context: context,
    );
  }

  Future<StoryResolvedVoiceRequest> speak({
    required StoryVoiceAssignment assignment,
    required String text,
    StorySpeechIntent intent = const StorySpeechIntent(),
    StoryVoiceContextWindow? context,
    bool flush = true,
  }) async {
    final request = await resolve(
      assignment: assignment,
      intent: intent,
      context: context,
    );
    await ttsProvider.speakWithNetworkService(
      request.service,
      text,
      flush: flush,
    );
    return request;
  }

  /// Plays any Story assignment, including native local/system backends.
  ///
  /// [speak] remains network-only for compatibility with existing callers that
  /// need the resolved network request. New Story playback paths should use
  /// this method so a per-story source can differ from Kelivo's global TTS
  /// selection while still sharing the native playback stack.
  Future<void> speakAssignment({
    required StoryVoiceAssignment assignment,
    required String text,
    StorySpeechIntent intent = const StorySpeechIntent(),
    StoryVoiceContextWindow? context,
    bool flush = true,
  }) async {
    switch (assignment.ttsServiceId) {
      case storyLocalMossTtsServiceId:
        if (!await ttsProvider.isLocalTtsReady()) {
          throw StateError('story_voice_local_moss_not_ready');
        }
        final previous = ttsProvider.backendMode;
        try {
          if (previous != TtsBackendMode.localOnly) {
            await ttsProvider.setBackendMode(TtsBackendMode.localOnly);
          }
          await ttsProvider.speak(text, flush: flush);
        } finally {
          if (ttsProvider.backendMode != previous) {
            await ttsProvider.setBackendMode(previous);
          }
        }
        return;
      case storySystemTtsServiceId:
        await ttsProvider.speakSystem(text, flush: flush);
        return;
      default:
        await speak(
          assignment: assignment,
          text: text,
          intent: intent,
          context: context,
          flush: flush,
        );
    }
  }

  Future<TtsServiceOptions?> _readServiceById(String serviceId) async {
    final id = serviceId.trim();
    if (id.isEmpty) return null;
    await preferences.load();
    final raw = preferences.getString('tts_services_v1') ?? '';
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    for (final item in decoded) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);
      if ((json['id'] ?? '').toString().trim() != id) continue;
      return TtsServiceOptions.fromJson(json);
    }
    return null;
  }
}
