import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/models/assistant.dart';
import '../../../core/models/token_usage.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';
import '../../../core/services/api/stream/stream_chunk.dart';

typedef AgentModelStreamFactory =
    Stream<StreamChunk> Function(AgentModelRequest request);

class AgentModelRequest {
  const AgentModelRequest({
    required this.config,
    required this.modelId,
    required this.messages,
    required this.tools,
    required this.requestId,
    required this.conversationId,
    this.thinkingBudget,
    this.temperature,
    this.topP,
    this.maxTokens,
  });

  final ProviderConfig config;
  final String modelId;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> tools;
  final String requestId;
  final String? conversationId;
  final int? thinkingBudget;
  final double? temperature;
  final double? topP;
  final int? maxTokens;
}

class AgentModelBridgeEndpoint {
  const AgentModelBridgeEndpoint({
    required this.baseUrl,
    required this.token,
  });

  final String baseUrl;
  final String token;
}

/// Loopback-only OpenAI-compatible facade over KELIVO's existing provider
/// stack. Pi never receives the upstream provider credential.
class AgentModelBridge {
  AgentModelBridge({
    required this.config,
    required this.modelId,
    required this.assistant,
    required this.conversationId,
    AgentModelStreamFactory? streamFactory,
  }) : _streamFactory = streamFactory ?? _defaultStream;

  final ProviderConfig config;
  final String modelId;
  final Assistant? assistant;
  final String? conversationId;
  final AgentModelStreamFactory _streamFactory;

  HttpServer? _server;
  String? _token;

  bool get isRunning => _server != null;

  Future<AgentModelBridgeEndpoint> start() async {
    final existing = _server;
    if (existing != null && _token != null) {
      return AgentModelBridgeEndpoint(
        baseUrl: 'http://127.0.0.1:${existing.port}/v1',
        token: _token!,
      );
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final token = const Uuid().v4().replaceAll('-', '');
    _server = server;
    _token = token;
    unawaited(_serve(server, token));

    return AgentModelBridgeEndpoint(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      token: token,
    );
  }

  Future<void> writePiConfig({
    required Directory taskDirectory,
    required AgentModelBridgeEndpoint endpoint,
  }) async {
    final configDir = Directory(p.join(taskDirectory.path, 'pi-config'));
    await configDir.create(recursive: true);
    final modelsFile = File(p.join(configDir.path, 'models.json'));
    await modelsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        <String, dynamic>{
          'providers': <String, dynamic>{
            'kelivo': <String, dynamic>{
              'baseUrl': endpoint.baseUrl,
              'api': 'openai-completions',
              'apiKey': endpoint.token,
              'authHeader': true,
              'models': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'current',
                  'name': 'KELIVO Current Model',
                },
              ],
            },
          },
        },
      ),
      flush: true,
    );
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    _token = null;
    await server?.close(force: true);
  }

  Future<void> _serve(HttpServer server, String token) async {
    try {
      await for (final request in server) {
        unawaited(_handle(request, token));
      }
    } on Object {
      // The task runner owns bridge lifetime and closes the server forcefully.
    }
  }

  Future<void> _handle(HttpRequest request, String token) async {
    try {
      if (!_authorized(request, token)) {
        await _json(
          request.response,
          HttpStatus.unauthorized,
          <String, dynamic>{
            'error': <String, dynamic>{
              'message': 'Unauthorized',
              'type': 'authentication_error',
            },
          },
        );
        return;
      }

      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/models') {
        await _json(
          request.response,
          HttpStatus.ok,
          <String, dynamic>{
            'object': 'list',
            'data': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'current',
                'object': 'model',
                'owned_by': 'kelivo',
              },
            ],
          },
        );
        return;
      }

      if (request.method != 'POST' || path != '/v1/chat/completions') {
        await _json(
          request.response,
          HttpStatus.notFound,
          <String, dynamic>{
            'error': <String, dynamic>{
              'message': 'Not found',
              'type': 'invalid_request_error',
            },
          },
        );
        return;
      }

      final raw = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Request body must be an object');
      }
      final body = decoded.cast<String, dynamic>();
      final messages = _maps(body['messages']);
      final tools = _maps(body['tools']);
      final requestId = 'agent-model-${const Uuid().v4()}';
      final modelRequest = AgentModelRequest(
        config: config,
        modelId: modelId,
        messages: messages,
        tools: tools,
        requestId: requestId,
        conversationId: conversationId,
        thinkingBudget: assistant?.thinkingBudget,
        temperature:
            assistant?.temperature ?? _double(body['temperature']),
        topP: assistant?.topP ?? _double(body['top_p']),
        maxTokens:
            assistant?.maxTokens ??
            _int(body['max_completion_tokens']) ??
            _int(body['max_tokens']),
      );

      if (body['stream'] == true) {
        await _streamCompletion(request.response, modelRequest);
      } else {
        await _complete(request.response, modelRequest);
      }
    } catch (error) {
      if (request.response.headersSent) {
        try {
          request.response.write(
            'data: ' +
                jsonEncode(<String, dynamic>{
                  'error': <String, dynamic>{
                    'message': error.toString(),
                    'type': 'api_error',
                  },
                }) +
                '\n\n',
          );
          request.response.write('data: [DONE]\n\n');
          await request.response.close();
        } catch (_) {}
        return;
      }
      await _json(
        request.response,
        HttpStatus.internalServerError,
        <String, dynamic>{
          'error': <String, dynamic>{
            'message': error.toString(),
            'type': 'api_error',
          },
        },
      );
    }
  }

  Future<void> _streamCompletion(
    HttpResponse response,
    AgentModelRequest request,
  ) async {
    response.statusCode = HttpStatus.ok;
    response.headers
      ..contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.connectionHeader, 'keep-alive');

    final id = 'chatcmpl-${const Uuid().v4().replaceAll('-', '')}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final toolIndices = <String, int>{};
    final toolNames = <String, String>{};
    TokenUsage? usage;
    String? finishReason;
    var roleSent = false;

    Future<void> emit(Map<String, dynamic> data) async {
      response.write('data: ${jsonEncode(data)}\n\n');
      await response.flush();
    }

    await for (final chunk in _streamFactory(request)) {
      switch (chunk) {
        case TextDelta():
          await emit(
            _chunk(
              id: id,
              created: created,
              delta: <String, dynamic>{
                if (!roleSent) 'role': 'assistant',
                'content': chunk.text,
              },
            ),
          );
          roleSent = true;
        case ReasoningDelta():
          if (chunk.text.isNotEmpty) {
            await emit(
              _chunk(
                id: id,
                created: created,
                delta: <String, dynamic>{
                  if (!roleSent) 'role': 'assistant',
                  'reasoning_content': chunk.text,
                },
              ),
            );
            roleSent = true;
          }
        case ToolCallStart():
          final index = toolIndices.length;
          toolIndices[chunk.id] = index;
          toolNames[chunk.id] = chunk.toolName;
          await emit(
            _chunk(
              id: id,
              created: created,
              delta: <String, dynamic>{
                if (!roleSent) 'role': 'assistant',
                'tool_calls': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'index': index,
                    'id': chunk.id,
                    'type': 'function',
                    'function': <String, dynamic>{
                      'name': chunk.toolName,
                      'arguments': '',
                    },
                  },
                ],
              },
            ),
          );
          roleSent = true;
        case ToolCallDelta():
          final index = toolIndices.putIfAbsent(
            chunk.id,
            () => toolIndices.length,
          );
          await emit(
            _chunk(
              id: id,
              created: created,
              delta: <String, dynamic>{
                'tool_calls': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'index': index,
                    if (!toolNames.containsKey(chunk.id) &&
                        chunk.toolNameDelta.isNotEmpty)
                      'type': 'function',
                    'function': <String, dynamic>{
                      if (chunk.toolNameDelta.isNotEmpty)
                        'name': chunk.toolNameDelta,
                      if (chunk.inputDelta.isNotEmpty)
                        'arguments': chunk.inputDelta,
                    },
                  },
                ],
              },
            ),
          );
        case Usage():
          usage = usage == null ? chunk.usage : usage!.merge(chunk.usage);
        case Finish():
          finishReason = _finishReason(
            chunk.finishReason,
            hasToolCalls: toolIndices.isNotEmpty,
          );
        default:
          break;
      }
    }

    await emit(
      _chunk(
        id: id,
        created: created,
        delta: const <String, dynamic>{},
        finishReason:
            finishReason ??
            _finishReason(null, hasToolCalls: toolIndices.isNotEmpty),
        usage: usage,
      ),
    );
    response.write('data: [DONE]\n\n');
    await response.close();
  }

  Future<void> _complete(
    HttpResponse response,
    AgentModelRequest request,
  ) async {
    final text = StringBuffer();
    final toolCalls = <String, _ToolAccumulator>{};
    TokenUsage? usage;
    String? finishReason;

    await for (final chunk in _streamFactory(request)) {
      switch (chunk) {
        case TextDelta():
          text.write(chunk.text);
        case ToolCallStart():
          toolCalls[chunk.id] = _ToolAccumulator(
            id: chunk.id,
            name: chunk.toolName,
          );
        case ToolCallDelta():
          final tool = toolCalls.putIfAbsent(
            chunk.id,
            () => _ToolAccumulator(id: chunk.id),
          );
          if (chunk.toolNameDelta.isNotEmpty) {
            tool.name += chunk.toolNameDelta;
          }
          tool.arguments.write(chunk.inputDelta);
        case Usage():
          usage = usage == null ? chunk.usage : usage!.merge(chunk.usage);
        case Finish():
          finishReason = _finishReason(
            chunk.finishReason,
            hasToolCalls: toolCalls.isNotEmpty,
          );
        default:
          break;
      }
    }

    final message = <String, dynamic>{
      'role': 'assistant',
      'content': text.isEmpty ? null : text.toString(),
      if (toolCalls.isNotEmpty)
        'tool_calls': <Map<String, dynamic>>[
          for (final tool in toolCalls.values)
            <String, dynamic>{
              'id': tool.id,
              'type': 'function',
              'function': <String, dynamic>{
                'name': tool.name,
                'arguments': tool.arguments.toString(),
              },
            },
        ],
    };

    await _json(
      response,
      HttpStatus.ok,
      <String, dynamic>{
        'id': 'chatcmpl-${const Uuid().v4().replaceAll('-', '')}',
        'object': 'chat.completion',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': 'current',
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'index': 0,
            'message': message,
            'finish_reason':
                finishReason ??
                _finishReason(null, hasToolCalls: toolCalls.isNotEmpty),
          },
        ],
        if (usage != null) 'usage': _usage(usage!),
      },
    );
  }

  static Stream<StreamChunk> _defaultStream(AgentModelRequest request) {
    return ChatApiService.sendMessageStream(
      config: request.config,
      modelId: request.modelId,
      messages: request.messages,
      thinkingBudget: request.thinkingBudget,
      temperature: request.temperature,
      topP: request.topP,
      maxTokens: request.maxTokens,
      tools: request.tools.isEmpty ? null : request.tools,
      requestId: request.requestId,
      conversationId: request.conversationId,
      stream: true,
      allowImagesApiRouting: false,
      parseMarkdownImageLinks: false,
    );
  }

  static Map<String, dynamic> _chunk({
    required String id,
    required int created,
    required Map<String, dynamic> delta,
    String? finishReason,
    TokenUsage? usage,
  }) {
    return <String, dynamic>{
      'id': id,
      'object': 'chat.completion.chunk',
      'created': created,
      'model': 'current',
      'choices': <Map<String, dynamic>>[
        <String, dynamic>{
          'index': 0,
          'delta': delta,
          'finish_reason': finishReason,
        },
      ],
      if (usage != null) 'usage': _usage(usage),
    };
  }

  static Map<String, dynamic> _usage(TokenUsage usage) {
    return <String, dynamic>{
      'prompt_tokens': usage.promptTokens,
      'completion_tokens': usage.completionTokens,
      'total_tokens': usage.totalTokens > 0
          ? usage.totalTokens
          : usage.promptTokens + usage.completionTokens,
      if (usage.cachedTokens > 0)
        'prompt_tokens_details': <String, dynamic>{
          'cached_tokens': usage.cachedTokens,
        },
    };
  }

  static String _finishReason(
    String? value, {
    required bool hasToolCalls,
  }) {
    if (hasToolCalls) return 'tool_calls';
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'length' || 'max_tokens' || 'max_output_tokens' => 'length',
      'content_filter' || 'safety' => 'content_filter',
      'tool_calls' || 'function_call' => 'tool_calls',
      _ => 'stop',
    };
  }

  static bool _authorized(HttpRequest request, String token) {
    final authorization = request.headers.value(HttpHeaders.authorizationHeader);
    return authorization == 'Bearer $token';
  }

  static List<Map<String, dynamic>> _maps(Object? raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return <Map<String, dynamic>>[
      for (final item in raw)
        if (item is Map) item.cast<String, dynamic>(),
    ];
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int? _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, dynamic> body,
  ) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await response.close();
  }
}

class _ToolAccumulator {
  _ToolAccumulator({required this.id, this.name = ''});

  final String id;
  String name;
  final StringBuffer arguments = StringBuffer();
}
