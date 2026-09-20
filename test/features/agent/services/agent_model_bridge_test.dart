import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/assistant.dart';
import 'package:Kelivo/core/models/token_usage.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/stream/stream_chunk.dart';
import 'package:Kelivo/features/agent/services/agent_model_bridge.dart';

void main() {
  test('model bridge requires its task-local bearer token', () async {
    final bridge = AgentModelBridge(
      config: ProviderConfig.defaultsFor('OpenAI'),
      modelId: 'upstream-model',
      assistant: null,
      conversationId: 'conversation-1',
      streamFactory: (_) => const Stream<StreamChunk>.empty(),
    );
    final endpoint = await bridge.start();
    final client = HttpClient();

    try {
      final request = await client.getUrl(Uri.parse('${endpoint.baseUrl}/models'));
      final response = await request.close();
      expect(response.statusCode, HttpStatus.unauthorized);
    } finally {
      client.close(force: true);
      await bridge.close();
    }
  });

  test('non-stream completion stays on the KELIVO provider bridge', () async {
    AgentModelRequest? captured;
    final bridge = AgentModelBridge(
      config: ProviderConfig.defaultsFor('OpenAI'),
      modelId: 'upstream-model',
      assistant: const Assistant(
        id: 'assistant-1',
        name: 'Agent',
        temperature: 0.25,
      ),
      conversationId: 'conversation-1',
      streamFactory: (request) async* {
        captured = request;
        yield const TextDelta(id: 'text-1', text: 'hello ');
        yield const TextDelta(id: 'text-1', text: 'world');
        yield const Usage(
          TokenUsage(
            promptTokens: 10,
            completionTokens: 2,
            totalTokens: 12,
          ),
        );
        yield const Finish(finishReason: 'stop');
      },
    );
    final endpoint = await bridge.start();
    final client = HttpClient();

    try {
      final response = await _post(
        client,
        '${endpoint.baseUrl}/chat/completions',
        endpoint.token,
        <String, dynamic>{
          'model': 'current',
          'stream': false,
          'temperature': 1.5,
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{'role': 'user', 'content': 'hi'},
          ],
        },
      );
      expect(response.status, HttpStatus.ok);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List;
      final first = (choices.first as Map).cast<String, dynamic>();
      final message = (first['message'] as Map).cast<String, dynamic>();

      expect(message['content'], 'hello world');
      expect(captured?.modelId, 'upstream-model');
      expect(captured?.conversationId, 'conversation-1');
      expect(captured?.temperature, 0.25);
      expect((body['usage'] as Map)['total_tokens'], 12);
    } finally {
      client.close(force: true);
      await bridge.close();
    }
  });

  test('stream completion exposes tool calls as OpenAI SSE', () async {
    final bridge = AgentModelBridge(
      config: ProviderConfig.defaultsFor('OpenAI'),
      modelId: 'upstream-model',
      assistant: null,
      conversationId: null,
      streamFactory: (_) async* {
        yield const ToolCallStart(id: 'call-1', toolName: 'read_file');
        yield const ToolCallDelta(
          id: 'call-1',
          inputDelta: '{"path":"README.md"}',
        );
        yield const ToolCallEnd('call-1');
        yield const Finish(finishReason: 'tool_calls');
      },
    );
    final endpoint = await bridge.start();
    final client = HttpClient();

    try {
      final response = await _post(
        client,
        '${endpoint.baseUrl}/chat/completions',
        endpoint.token,
        <String, dynamic>{
          'model': 'current',
          'stream': true,
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{'role': 'user', 'content': 'read it'},
          ],
          'tools': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'function',
              'function': <String, dynamic>{
                'name': 'read_file',
                'parameters': <String, dynamic>{'type': 'object'},
              },
            },
          ],
        },
      );

      expect(response.status, HttpStatus.ok);
      expect(response.body, contains('"tool_calls"'));
      expect(response.body, contains('"read_file"'));
      expect(response.body, contains('README.md'));
      expect(response.body, contains('"finish_reason":"tool_calls"'));
      expect(response.body, contains('data: [DONE]'));
    } finally {
      client.close(force: true);
      await bridge.close();
    }
  });
}

Future<({int status, String body})> _post(
  HttpClient client,
  String url,
  String token,
  Map<String, dynamic> body,
) async {
  final request = await client.postUrl(Uri.parse(url));
  request.headers
    ..contentType = ContentType.json
    ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
  request.write(jsonEncode(body));
  final response = await request.close();
  return (
    status: response.statusCode,
    body: await utf8.decoder.bind(response).join(),
  );
}
