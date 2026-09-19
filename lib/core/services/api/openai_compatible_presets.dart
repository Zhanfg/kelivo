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

  static const freeBuffBridge = OpenAICompatiblePreset(
    id: 'freebuff-bridge',
    label: 'FreeBuff Bridge',
    name: 'FreeBuff',
    baseUrl: 'http://127.0.0.1:8765/v1',
    suggestedApiKey: 'dummy',
  );

  static const all = <OpenAICompatiblePreset>[
    openCodeGo,
    openCodeZen,
    freeBuffBridge,
  ];
}
