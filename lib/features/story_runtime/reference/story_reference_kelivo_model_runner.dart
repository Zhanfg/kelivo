import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import 'story_reference_analysis_service.dart';

/// Native Kelivo adapter for Reference Library analysis/reduction jobs.
///
/// This intentionally uses the same provider configuration model as the rest of
/// Kelivo. It does not introduce a separate API-key or provider subsystem.
final class StoryReferenceKelivoModelRunner {
  const StoryReferenceKelivoModelRunner({
    required this.settings,
    required this.providerKey,
    required this.modelId,
    this.thinkingBudget,
  });

  final SettingsProvider settings;
  final String providerKey;
  final String modelId;
  final int? thinkingBudget;

  Future<String> call(StoryReferenceModelRequest request) async {
    final normalizedProvider = providerKey.trim();
    final normalizedModel = modelId.trim();
    if (normalizedProvider.isEmpty || normalizedModel.isEmpty) {
      throw const StoryReferenceModelRunnerException('model_not_configured');
    }

    final config = settings.getProviderConfig(normalizedProvider);
    final stageLabel = switch (request.stage) {
      StoryReferenceAnalysisStage.analyzeChunk => 'REFERENCE_ANALYZE',
      StoryReferenceAnalysisStage.reduce => 'REFERENCE_REDUCE',
    };
    final prompt =
        '''
${request.instructions.trim()}

[$stageLabel]
${request.input.trim()}
[/$stageLabel]
''';

    final output = await ChatApiService.generateText(
      config: config,
      modelId: normalizedModel,
      prompt: prompt,
      thinkingBudget: thinkingBudget,
      skipImageParsing: true,
    );
    final normalized = output.trim();
    if (normalized.isEmpty) {
      throw const StoryReferenceModelRunnerException('empty_model_output');
    }
    return normalized;
  }
}

final class StoryReferenceModelRunnerException implements Exception {
  const StoryReferenceModelRunnerException(this.code);

  final String code;

  @override
  String toString() => 'StoryReferenceModelRunnerException($code)';
}
