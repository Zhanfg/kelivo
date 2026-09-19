import '../../../../providers/settings_provider.dart';

enum OpenAIWireProtocol { chatCompletions, responses }

/// Resolves the OpenAI-compatible wire protocol for one logical model.
///
/// Resolution order:
/// 1. Per-model `openaiProtocol` override.
/// 2. Provider-level "Responses API" force switch.
/// 3. Known mixed-protocol gateways (currently OpenCode Zen / Go).
/// 4. Chat Completions fallback.
///
/// This keeps generic OpenAI-compatible gateways working while allowing one
/// provider to expose both Chat Completions and Responses models.
OpenAIWireProtocol resolveOpenAIWireProtocol(
  ProviderConfig config,
  String modelId, {
  String? upstreamModelId,
}) {
  final override = config.modelOverrides[modelId];
  if (override is Map) {
    final raw = (override['openaiProtocol'] ?? override['openai_protocol'])
        ?.toString()
        .trim()
        .toLowerCase();
    switch (raw) {
      case 'responses':
      case 'response':
      case 'responses_api':
      case 'responses-api':
        return OpenAIWireProtocol.responses;
      case 'chat':
      case 'chat_completions':
      case 'chat-completions':
      case 'chatcompletions':
        return OpenAIWireProtocol.chatCompletions;
    }
  }

  // Preserve the existing provider-level switch as an explicit force option.
  if (config.useResponseApi == true) return OpenAIWireProtocol.responses;

  final uri = Uri.tryParse(config.baseUrl.trim());
  final host = uri?.host.toLowerCase() ?? '';
  final path = (uri?.path ?? '').replaceAll(RegExp(r'/+$'), '').toLowerCase();
  final effectiveModel = (upstreamModelId ?? modelId).trim().toLowerCase();

  // OpenCode Zen / Go are mixed-protocol gateways. Their OpenAI-family models
  // use the Responses endpoint, while open coding models use Chat Completions.
  // The base URL itself ends at /v1, so Kelivo appends the selected endpoint.
  final isOpenCodeGateway =
      host == 'opencode.ai' &&
      (path.endsWith('/zen/v1') || path.endsWith('/zen/go/v1'));
  if (isOpenCodeGateway && _openCodeUsesResponses(effectiveModel)) {
    return OpenAIWireProtocol.responses;
  }

  return OpenAIWireProtocol.chatCompletions;
}

bool _openCodeUsesResponses(String modelId) {
  return RegExp(r'^(?:gpt-|o[1-9](?:-|$)|codex(?:-|$))').hasMatch(modelId);
}

bool shouldUseOpenAIResponsesApi(
  ProviderConfig config,
  String modelId, {
  String? upstreamModelId,
}) =>
    resolveOpenAIWireProtocol(
      config,
      modelId,
      upstreamModelId: upstreamModelId,
    ) ==
    OpenAIWireProtocol.responses;
