import 'dart:convert';

import '../../../core/database/business_preferences.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/services/tts/network_tts.dart';
import 'story_voice_models.dart';
import 'story_voice_routing.dart';

/// Adapter from Story semantic voice routing to Kelivo's existing TtsProvider.
///
/// It never owns network credentials, HTTP, audio queues or playback. Those all
/// remain in the native TTS subsystem. The adapter resolves a configured service
/// by id, derives a per-line voice/instruction view and hands it back to
/// TtsProvider.speakWithNetworkService().
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
  }) async {
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
    );
  }

  Future<StoryResolvedVoiceRequest> speak({
    required StoryVoiceAssignment assignment,
    required String text,
    StorySpeechIntent intent = const StorySpeechIntent(),
    bool flush = true,
  }) async {
    final request = await resolve(assignment: assignment, intent: intent);
    await ttsProvider.speakWithNetworkService(
      request.service,
      text,
      flush: flush,
    );
    return request;
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
