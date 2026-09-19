import '../../../../providers/settings_provider.dart';

enum OpenAIWireProtocol {
  chatCompletions,
  responses,
  anthropicMessages,
  googleGenerativeLanguage,
}

/// Resolve the wire protocol for one model exposed through an OpenAI-style
/// provider entry.
///
/// OpenCode Zen / Go are gateways whose single model catalog fans out to
/// multiple upstream wire protocols. Generic OpenAI-compatible providers keep
/// the Chat Completions default unless explicitly overridden.
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
      case 'anthropic':
      case 'messages':
      case 'anthropic_messages':
      case 'anthropic-messages':
        return OpenAIWireProtocol.anthropicMessages;
      case 'google':
      case 'gemini':
      case 'google_gemini':
      case 'google-generative-language':
        return OpenAIWireProtocol.googleGenerativeLanguage;
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
  final effectiveModel = _normalizeOpenCodeModelId(
    (upstreamModelId ?? modelId).trim().toLowerCase(),
  );

  if (host != 'opencode.ai') return OpenAIWireProtocol.chatCompletions;

  if (path.endsWith('/zen/go/v1')) {
    return _openCodeGoProtocol(effectiveModel);
  }
  if (path.endsWith('/zen/v1')) {
    return _openCodeZenProtocol(effectiveModel);
  }

  return OpenAIWireProtocol.chatCompletions;
}

String _normalizeOpenCodeModelId(String modelId) {
  return modelId.replaceFirst(
    RegExp(r'^(?:opencode-go|opencode-zen|opencode|zen)/'),
    '',
  );
}

OpenAIWireProtocol _openCodeGoProtocol(String modelId) {
  // Current Go Responses models.
  if (modelId.startsWith('gpt-') ||
      modelId == 'grok-4.6' ||
      modelId.startsWith('muse-spark-1.2') ||
      modelId.startsWith('muse-spark-1.3')) {
    return OpenAIWireProtocol.responses;
  }

  // Current Go Anthropic Messages models.
  if (RegExp(r'^minimax-m(?:2\.[57]|3)(?:$|[-.])').hasMatch(modelId) ||
      RegExp(r'^qwen3\.(?:6|7|8)(?:$|[-.])').hasMatch(modelId)) {
    return OpenAIWireProtocol.anthropicMessages;
  }

  return OpenAIWireProtocol.chatCompletions;
}

OpenAIWireProtocol _openCodeZenProtocol(String modelId) {
  if (modelId.startsWith('gpt-') ||
      modelId.startsWith('grok-') ||
      modelId.startsWith('muse-spark-')) {
    return OpenAIWireProtocol.responses;
  }
  if (modelId.startsWith('claude-') ||
      RegExp(r'^qwen3\.(?:5|6|7|8)(?:$|[-.])').hasMatch(modelId)) {
    return OpenAIWireProtocol.anthropicMessages;
  }
  if (modelId.startsWith('gemini-')) {
    return OpenAIWireProtocol.googleGenerativeLanguage;
  }
  return OpenAIWireProtocol.chatCompletions;
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
