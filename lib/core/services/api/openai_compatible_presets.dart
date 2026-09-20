class OpenAICompatiblePreset {
  const OpenAICompatiblePreset({
    required this.id,
    required this.label,
    required this.name,
    required this.baseUrl,
    this.chatPath = '/chat/completions',
    this.useResponseApi = false,
    this.suggestedApiKey,
  });

  final String id;
  final String label;
  final String name;
  final String baseUrl;
  final String chatPath;

  /// Provider-wide force switch. Mixed-protocol providers should leave this
  /// false and rely on the per-model protocol resolver.
  final bool useResponseApi;

  /// Non-secret convenience value used by local gateways that expect a bearer
  /// token syntactically but do not validate it by default.
  final String? suggestedApiKey;
}

abstract final class OpenAICompatiblePresets {
  static const openCodeGo = OpenAICompatiblePreset(
    id: 'opencode-go',
    label: 'OpenCode Go',
    name: 'OpenCode Go',
    baseUrl: 'https://opencode.ai/zen/go/v1',
  );

  static const openCodeZen = OpenAICompatiblePreset(
    id: 'opencode-zen',
    label: 'OpenCode Zen',
    name: 'OpenCode Zen',
    baseUrl: 'https://opencode.ai/zen/v1',
  );

  static const kiloFree = OpenAICompatiblePreset(
    id: 'kilo-free',
    label: 'Kilo Free',
    name: 'Kilo Free',
    baseUrl: 'https://api.kilo.ai/api/gateway',
  );

  static const pollinations = OpenAICompatiblePreset(
    id: 'pollinations',
    label: 'Pollinations',
    name: 'Pollinations',
    baseUrl: 'https://gen.pollinations.ai/v1',
  );

  static const openRouterFree = OpenAICompatiblePreset(
    id: 'openrouter-free',
    label: 'OpenRouter Free',
    name: 'OpenRouter Free',
    baseUrl: 'https://openrouter.ai/api/v1',
  );

  static const freeBuffBridge = OpenAICompatiblePreset(
    id: 'freebuff-bridge',
    label: 'FreeBuff Bridge',
    name: 'FreeBuff',
    baseUrl: 'http://127.0.0.1:23333/v1',
    suggestedApiKey: 'dummy',
  );

  static const all = <OpenAICompatiblePreset>[
    kiloFree,
    pollinations,
    openRouterFree,
    openCodeGo,
    openCodeZen,
    freeBuffBridge,
  ];
}
