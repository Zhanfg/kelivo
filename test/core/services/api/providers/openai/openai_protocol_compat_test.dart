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
  group('OpenCode Go protocol compatibility', () {
    final cfg = _cfg(baseUrl: 'https://opencode.ai/zen/go/v1');

    test('routes Responses models', () {
      for (final id in <String>[
        'gpt-5.6-luna',
        'grok-4.6',
        'muse-spark-1.3-contributor',
        'muse-spark-1.2-contributor',
      ]) {
        expect(
          resolveOpenAIWireProtocol(cfg, id),
          OpenAIWireProtocol.responses,
          reason: id,
        );
      }
    });

    test('routes Anthropic Messages models', () {
      for (final id in <String>[
        'minimax-m3',
        'minimax-m2.7',
        'minimax-m2.5',
        'qwen3.8-max',
        'qwen3.8-flash',
        'qwen3.7-max',
        'qwen3.7-plus',
        'qwen3.6-plus',
      ]) {
        expect(
          resolveOpenAIWireProtocol(cfg, id),
          OpenAIWireProtocol.anthropicMessages,
          reason: id,
        );
      }
    });

    test('keeps OpenAI-compatible models on Chat Completions', () {
      for (final id in <String>[
        'glm-5.3-flash',
        'glm-5.3',
        'glm-5.2',
        'kimi-k3',
        'kimi-k2.7-code',
        'deepseek-v4.1-flash',
        'deepseek-v4-pro',
        'deepseek-v4-flash',
        'mimo-v2.5',
        'hy4-preview',
        'hy3',
        'grok-4.5',
      ]) {
        expect(
          resolveOpenAIWireProtocol(cfg, id),
          OpenAIWireProtocol.chatCompletions,
          reason: id,
        );
      }
    });
  });

  group('OpenCode Zen protocol compatibility', () {
    final cfg = _cfg(baseUrl: 'https://opencode.ai/zen/v1');

    test('routes GPT, Grok and Muse through Responses', () {
      for (final id in <String>[
        'gpt-5.6-sol',
        'gpt-5.4-mini',
        'grok-4.6',
        'grok-build-0.1',
        'muse-spark-1.3',
      ]) {
        expect(
          resolveOpenAIWireProtocol(cfg, id),
          OpenAIWireProtocol.responses,
          reason: id,
        );
      }
    });

    test('routes Claude and current Qwen through Anthropic Messages', () {
      for (final id in <String>[
        'claude-opus-4-8',
        'claude-sonnet-5',
        'qwen3.8-flash',
        'qwen3.7-plus',
        'qwen3.5-plus',
      ]) {
        expect(
          resolveOpenAIWireProtocol(cfg, id),
          OpenAIWireProtocol.anthropicMessages,
          reason: id,
        );
      }
    });

    test('routes Gemini through the Google Generative Language surface', () {
      for (final id in <String>[
        'gemini-3.8-flash',
        'gemini-3.5-flash-lite',
        'gemini-3.1-pro',
      ]) {
        expect(
          resolveOpenAIWireProtocol(cfg, id),
          OpenAIWireProtocol.googleGenerativeLanguage,
          reason: id,
        );
      }
    });

    test('keeps compatible open models on Chat Completions', () {
      for (final id in <String>[
        'deepseek-v4.1-flash',
        'minimax-m3',
        'glm-5.3',
        'kimi-k2.6',
      ]) {
        expect(
          resolveOpenAIWireProtocol(cfg, id),
          OpenAIWireProtocol.chatCompletions,
          reason: id,
        );
      }
    });
  });

  test('per-model override wins over automatic routing', () {
    final cfg = _cfg(
      baseUrl: 'https://opencode.ai/zen/go/v1',
      modelOverrides: {
        'gpt-5.6-luna': {'openaiProtocol': 'chat_completions'},
        'kimi-k3': {'openaiProtocol': 'responses'},
        'glm-5.3': {'openaiProtocol': 'anthropic_messages'},
        'hy3': {'openaiProtocol': 'google_gemini'},
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
    expect(
      resolveOpenAIWireProtocol(cfg, 'glm-5.3'),
      OpenAIWireProtocol.anthropicMessages,
    );
    expect(
      resolveOpenAIWireProtocol(cfg, 'hy3'),
      OpenAIWireProtocol.googleGenerativeLanguage,
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
        _cfg(baseUrl: 'http://127.0.0.1:8765/v1'),
        'freebuff-bridge',
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

  group('provider presets', () {
    test('OpenCode Go preset targets mixed-protocol base', () {
      expect(
        OpenAICompatiblePresets.openCodeGo.baseUrl,
        'https://opencode.ai/zen/go/v1',
      );
      expect(OpenAICompatiblePresets.openCodeGo.useResponseApi, isFalse);
    });

    test('FreeBuff bridge preset matches the local bridge default', () {
      expect(
        OpenAICompatiblePresets.freeBuffBridge.baseUrl,
        'http://127.0.0.1:8765/v1',
      );
      expect(
        OpenAICompatiblePresets.freeBuffBridge.chatPath,
        '/chat/completions',
      );
      expect(OpenAICompatiblePresets.freeBuffBridge.suggestedApiKey, 'dummy');
    });
  });
}
