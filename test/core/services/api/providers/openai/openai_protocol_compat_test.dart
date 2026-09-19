import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/openai_compatible_presets.dart';
import 'package:Kelivo/core/services/api/providers/openai/openai_protocol_compat.dart';

ProviderConfig _cfg({
  required String baseUrl,
  bool useResponseApi = false,
  Map<String, dynamic> modelOverrides = const {},
}) {
  return ProviderConfig(
    id: 'test',
    enabled: true,
    name: 'test',
    apiKey: 'k',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
    useResponseApi: useResponseApi,
    modelOverrides: modelOverrides,
  );
}

void main() {
  group('OpenAI mixed protocol compatibility', () {
    test('OpenCode Go routes GPT models to Responses', () {
      final cfg = _cfg(baseUrl: 'https://opencode.ai/zen/go/v1');
      expect(
        resolveOpenAIWireProtocol(cfg, 'gpt-5.6-luna'),
        OpenAIWireProtocol.responses,
      );
    });

    test('OpenCode Go keeps open coding models on Chat Completions', () {
      final cfg = _cfg(baseUrl: 'https://opencode.ai/zen/go/v1');
      for (final id in <String>[
        'glm-5.2',
        'kimi-k3',
        'deepseek-v4-flash',
        'minimax-m3',
      ]) {
        expect(
          resolveOpenAIWireProtocol(cfg, id),
          OpenAIWireProtocol.chatCompletions,
          reason: id,
        );
      }
    });

    test('OpenCode Zen routes GPT family to Responses', () {
      final cfg = _cfg(baseUrl: 'https://opencode.ai/zen/v1');
      expect(
        resolveOpenAIWireProtocol(cfg, 'gpt-5.6-sol'),
        OpenAIWireProtocol.responses,
      );
      expect(
        resolveOpenAIWireProtocol(cfg, 'gpt-5.4-mini'),
        OpenAIWireProtocol.responses,
      );
    });

    test('per-model override wins over automatic routing', () {
      final cfg = _cfg(
        baseUrl: 'https://opencode.ai/zen/go/v1',
        modelOverrides: {
          'gpt-5.6-luna': {'openaiProtocol': 'chat_completions'},
          'kimi-k3': {'openaiProtocol': 'responses'},
        },
      );
      expect(
        resolveOpenAIWireProtocol(cfg, 'gpt-5.6-luna'),
        OpenAIWireProtocol.chatCompletions,
      );
      expect(
        resolveOpenAIWireProtocol(cfg, 'kimi-k3'),
        OpenAIWireProtocol.responses,
      );
    });

    test('provider Responses switch still force-enables Responses', () {
      final cfg = _cfg(
        baseUrl: 'https://example.com/v1',
        useResponseApi: true,
      );
      expect(
        resolveOpenAIWireProtocol(cfg, 'custom-model'),
        OpenAIWireProtocol.responses,
      );
    });

    test('generic and FreeBuff-compatible gateways default to chat', () {
      expect(
        resolveOpenAIWireProtocol(
          _cfg(baseUrl: 'http://127.0.0.1:47821/v1'),
          'z-ai/glm-5.3-flash',
        ),
        OpenAIWireProtocol.chatCompletions,
      );
      expect(
        resolveOpenAIWireProtocol(
          _cfg(baseUrl: 'https://example.com/v1'),
          'free-model',
        ),
        OpenAIWireProtocol.chatCompletions,
      );
    });
  });

  group('provider presets', () {
    test('OpenCode Go preset targets mixed-protocol base', () {
      expect(
        OpenAICompatiblePresets.openCodeGo.baseUrl,
        'https://opencode.ai/zen/go/v1',
      );
      expect(OpenAICompatiblePresets.openCodeGo.useResponseApi, isFalse);
    });

    test('FreeBuff bridge preset is OpenAI-compatible local gateway', () {
      expect(
        OpenAICompatiblePresets.freeBuffBridge.baseUrl,
        'http://127.0.0.1:47821/v1',
      );
      expect(
        OpenAICompatiblePresets.freeBuffBridge.chatPath,
        '/chat/completions',
      );
      expect(OpenAICompatiblePresets.freeBuffBridge.suggestedApiKey, 'sk-local');
    });
  });
}
