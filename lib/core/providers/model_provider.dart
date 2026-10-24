import '../services/auth/provider_oauth_service.dart';
export '../models/model_spec.dart';

import 'dart:convert';
import 'dart:io' show HttpException;
import 'settings_provider.dart';
import '../services/network/provider_http_client.dart';
import '../services/api_key_manager.dart';
import '../services/api/provider_request_headers.dart';
import '../services/api/providers/openai/openai_protocol_compat.dart';
import '../services/model_override_payload_parser.dart';
import '../services/custom_request_merger.dart';
import '../services/api/embedding/embedding_api_service.dart';
import '../services/api/google_service_account_auth.dart';
import '../models/model_types.dart';
import '../utils/kimi_model_compat.dart';

class ModelRegistry {
  // Updated model groups to reflect new series
  // Vision-capable models (text + image input).
  // Qwen vision is intentional and precise (see [_isQwenVisionModel]): not
  // every Qwen 3.7 Max id is multimodal.
  // MiMo image input also includes the native multimodal v2.6 family.
  static final RegExp vision = RegExp(
    // GPT family incl. 4o, 4.1, 5 (exclude gpt-5-chat), and OpenAI o* series
    r'(gpt-4o|gpt-4\.1|gpt-5(?!-chat)|gpt-6|o\d|gemini|claude|kimi-k2([-.])(?:5|6|7)|kimi-k3(?:$|[/_:@.-])|muse-spark-1(?:$|[/_:@.-])|doubao.+(?:1([-.])(?:6|8)|seed-2|seed-evolving)|grok-4|step-3|intern-s1|minimax-m3(?:$|[/_:@])|mimo-v2(?:-omni(?:$|[/_:@])|\.5(?:$|[/_:@])|\.6(?:$|[/_:@.-]))|sensenova-6\.7-flash-lite)',
    caseSensitive: false,
  );
  // Tool-using models
  static final RegExp tool = RegExp(
    (r'(gpt-4o|gpt-4\.1|gpt-oss|gpt-5(?!-chat)|gpt-6|o\d|'
            r'gemini|claude|'
            r'qwen-?3|doubao.+(?:1([-.])(?:6|8)|seed-2|seed-evolving)|grok-4|kimi-k2|'
            r'kimi-k3(?:$|[/_:@.-])|muse-spark-1(?:$|[/_:@.-])|'
            r'step-3|intern-s1|glm-4([-.])(?:5|6|7)|glm-5|minimax-(?:m2|m3)|'
            r'deepseek-(?:r1|v3|chat|v3\.1|v3\.2|v4|flash)|'
            r'deepseek-reasoner|'
            r'mimo-v2|'
            r'sensenova-6\.7-flash-lite|'
            r'laguna'
            r')')
        .replaceAll(' ', ''),
    caseSensitive: false,
  );
  static final RegExp reasoning = RegExp(
    (r'(gpt-oss|gpt-5(?!-chat)|gpt-6|o\d|'
            r'gemini-(?:2\.5|3).*|gemini-(?:flash-latest|pro-latest)|'
            r'gemini-3-pro-image-preview|'
            r'gemma[-_]?4|'
            r'claude|'
            r'qwen-?3|doubao.+(?:1([-.])(?:6|8)|seed-2|seed-evolving)|grok-4|kimi-k2|'
            r'kimi-k3(?:$|[/_:@.-])|muse-spark-1(?:$|[/_:@.-])|'
            r'step-3|intern-s1|glm-4([-.])(?:5|6|7)|glm-5|minimax-(?:m2|m3)|'
            r'deepseek-(?:r1|v3\.1|v3\.2|v4|flash)|'
            r'deepseek-reasoner|'
            r'mimo-v2|'
            r'laguna'
            r')')
        .replaceAll(' ', ''),
    caseSensitive: false,
  );

  /// Precise Qwen vision matrix:
  /// - `qwen3.5*` (existing)
  /// - `qwen3.7-plus` / `qwen3.7-flash` (+ snapshots)
  /// - vision Max snapshot `qwen3.7-max-2026-06-08` and later only
  /// - `qwen3.8-max` / `qwen3.8-flash` / `qwen3.8-27b` (+ snapshots)
  /// Open `qwen3.8-2.4t-a95b` and plain / earlier `qwen3.7-max` stay text-only.
  static bool _isQwenVisionModel(String id) {
    final lower = id.toLowerCase();
    if (RegExp(r'qwen-?3([-.])5').hasMatch(lower)) return true;
    if (RegExp(r'qwen-?3([-.])7-(?:plus|flash)').hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'qwen-?3([-.])8-(?:max|flash|27b)').hasMatch(lower)) {
      return true;
    }
    final maxSnap = RegExp(
      r'qwen-?3([-.])7-max-(\d{4}-\d{2}-\d{2})',
    ).firstMatch(lower);
    if (maxSnap == null) return false;
    final date = DateTime.tryParse(maxSnap.group(2)!);
    if (date == null) return false;
    return !date.isBefore(DateTime(2026, 6, 8));
  }

  /// GLM-5.3-Flash is the first native multimodal GLM-5 SKU.
  static bool _isGlmVisionModel(String id) {
    return RegExp(
      r'(^|[/_:@])glm-5\.3-flash(?:$|[-.])',
      caseSensitive: false,
    ).hasMatch(id);
  }

  /// DeepSeek V4.1 Flash (`deepseek-flash`) is native multimodal.
  /// Retired Flash IDs temporarily route to it and inherit image input.
  /// `deepseek-v4-pro` stays text-only until that SKU is retired.
  static bool _isDeepSeekVisionModel(String id) {
    return RegExp(
      r'(^|[/_:@])(?:deepseek-flash|deepseek-v4-flash)(?:$|[/_:@.-])',
      caseSensitive: false,
    ).hasMatch(id);
  }

  static bool isLikelyEmbeddingId(String rawId) {
    final id = rawId.toLowerCase();
    return id.contains('embedding') ||
        RegExp(r'(^|[-_/])embed(?:dings?)?([-.]|$)').hasMatch(id);
  }

  static bool _isGemini35Flash(String id) {
    return RegExp(
      r'(^|[/:_-])gemini-3\.5-flash([._:@/-]|$)',
      caseSensitive: false,
    ).hasMatch(id);
  }

  static ModelInfo infer(ModelInfo base) {
    final id = base.id.toLowerCase();
    final isKimiCode =
        isKimiCodeK3Alias(id) || isKimiForCodingModel(id) || isKimiK28Model(id);
    final inMods = <Modality>[...base.input];
    final outMods = <Modality>[...base.output];
    final ab = <ModelAbility>[...base.abilities];
    final bool inferEmbeddingById = isLikelyEmbeddingId(id);
    if (base.type == ModelType.embedding || inferEmbeddingById) {
      if (!inMods.contains(Modality.text)) inMods.add(Modality.text);
      outMods
        ..clear()
        ..add(Modality.text);
      ab.clear();
      return base.copyWith(
        type: ModelType.embedding,
        input: inMods,
        output: outMods,
        abilities: ab,
      );
    }
    // If model id contains 'image', treat it as an image model:
    // - Input and output both include image
    // - No tool or reasoning abilities
    if (id.contains('image')) {
      if (!inMods.contains(Modality.image)) inMods.add(Modality.image);
      if (!outMods.contains(Modality.image)) outMods.add(Modality.image);
      ab.removeWhere(
        (x) => x == ModelAbility.tool || x == ModelAbility.reasoning,
      );
      return base.copyWith(input: inMods, output: outMods, abilities: ab);
    }
    if (_isGemini35Flash(id)) {
      if (!inMods.contains(Modality.image)) inMods.add(Modality.image);
      outMods
        ..clear()
        ..add(Modality.text);
      if (!ab.contains(ModelAbility.tool)) ab.add(ModelAbility.tool);
      if (!ab.contains(ModelAbility.reasoning)) {
        ab.add(ModelAbility.reasoning);
      }
      return base.copyWith(input: inMods, output: outMods, abilities: ab);
    }
    if (vision.hasMatch(id) ||
        isKimiCode ||
        _isQwenVisionModel(id) ||
        _isGlmVisionModel(id) ||
        _isDeepSeekVisionModel(id)) {
      if (!inMods.contains(Modality.image)) inMods.add(Modality.image);
    }
    if ((tool.hasMatch(id) || isKimiCode) && !ab.contains(ModelAbility.tool)) {
      ab.add(ModelAbility.tool);
    }
    if ((reasoning.hasMatch(id) || isKimiCode) &&
        !ab.contains(ModelAbility.reasoning)) {
      ab.add(ModelAbility.reasoning);
    }
    return base.copyWith(input: inMods, output: outMods, abilities: ab);
  }
}

abstract class BaseProvider {
  Future<List<ModelSpec>> listModels(ProviderConfig cfg);
}

class _Http {
  static Map<String, String> modelListHeaders(
    ProviderConfig cfg,
    Map<String, String> base,
  ) {
    return CustomRequestMerger.mergeHeaders(
      base: base,
      provider: ModelOverridePayloadParser.customHeadersFromRows(
        cfg.customHeaders,
      ),
    );
  }
}

class OpenAIProvider extends BaseProvider {
  @override
  Future<List<ModelSpec>> listModels(ProviderConfig cfg) async {
    final key = ProviderManager._effectiveApiKey(cfg);
    final client = providerHttpClient(cfg);
    try {
      final uri = Uri.parse('${cfg.baseUrl}/models');
      final headers = <String, String>{};
      if (key.isNotEmpty) headers['Authorization'] = 'Bearer $key';
      final res = await client.get(
        uri,
        headers: _Http.modelListHeaders(cfg, headers),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = (jsonDecode(res.body)['data'] as List?) ?? [];
        return [
          for (final e in data)
            if (e is Map && e['id'] is String)
              ModelSpecResolver.instance
                  .resolve(
                    cfg,
                    e['id'] as String,
                    displayName: e['id'] as String,
                  )
                  .spec,
        ];
      }
      return [];
    } finally {
      client.close();
    }
  }
}

class ClaudeProvider extends BaseProvider {
  static const String anthropicVersion = '2023-06-01';
  @override
  Future<List<ModelSpec>> listModels(ProviderConfig cfg) async {
    final key = ProviderManager._effectiveApiKey(cfg);
    final client = providerHttpClient(cfg);
    try {
      final uri = Uri.parse('${cfg.baseUrl}/models');
      final headers = <String, String>{'anthropic-version': anthropicVersion};
      if (key.isNotEmpty) headers['x-api-key'] = key;
      final res = await client.get(
        uri,
        headers: _Http.modelListHeaders(cfg, headers),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final obj = jsonDecode(res.body) as Map<String, dynamic>;
        final data = (obj['data'] as List?) ?? [];
        return [
          for (final e in data)
            if (e is Map && e['id'] is String)
              ModelSpecResolver.instance
                  .resolve(
                    cfg,
                    e['id'] as String,
                    displayName:
                        (e['display_name'] as String?) ?? (e['id'] as String),
                  )
                  .spec,
        ];
      }
      return [];
    } finally {
      client.close();
    }
  }
}

class GoogleProvider extends BaseProvider {
  String _buildUrl(ProviderConfig cfg) {
    if (cfg.vertexAI == true &&
        (cfg.location?.isNotEmpty == true) &&
        (cfg.projectId?.isNotEmpty == true)) {
      final loc = cfg.location!;
      final proj = cfg.projectId!;
      return 'https://aiplatform.googleapis.com/v1/projects/$proj/locations/$loc/publishers/google/models';
    }
    final base = cfg.baseUrl.endsWith('/')
        ? cfg.baseUrl.substring(0, cfg.baseUrl.length - 1)
        : cfg.baseUrl;
    return '$base/models';
  }

  @override
  Future<List<ModelSpec>> listModels(ProviderConfig cfg) async {
    final client = providerHttpClient(cfg);
    try {
      final url = _buildUrl(cfg);
      final headers = <String, String>{};
      if (cfg.vertexAI == true) {
        final jsonStr = (cfg.serviceAccountJson ?? '').trim();
        if (jsonStr.isNotEmpty) {
          try {
            final token = await GoogleServiceAccountAuth.getAccessTokenFromJson(
              jsonStr,
            );
            headers['Authorization'] = 'Bearer $token';
            final proj = (cfg.projectId ?? '').trim();
            if (proj.isNotEmpty) headers['X-Goog-User-Project'] = proj;
          } catch (_) {}
        } else {
          final key = ProviderManager._effectiveApiKey(cfg);
          if (key.isNotEmpty) {
            // Fallback: treat apiKey as a bearer token if user pasted one
            headers['Authorization'] = 'Bearer $key';
          }
        }
      } else {
        final key = ProviderManager._effectiveApiKey(cfg);
        if (key.isNotEmpty) {
          headers['x-goog-api-key'] = key;
        }
      }
      final out = <ModelSpec>[];
      try {
        final res = await client.get(
          Uri.parse(url),
          headers: _Http.modelListHeaders(cfg, headers),
        );
        if (res.statusCode >= 200 && res.statusCode < 300) {
          final obj = jsonDecode(res.body) as Map<String, dynamic>;
          final arr = (obj['models'] as List?) ?? [];
          for (final e in arr) {
            if (e is Map) {
              final name = (e['name'] as String?) ?? '';
              final id = name.startsWith('models/')
                  ? name.substring('models/'.length)
                  : name;
              final displayName = (e['displayName'] as String?) ?? id;
              final methods =
                  (e['supportedGenerationMethods'] as List?)
                      ?.map((m) => m.toString())
                      .toSet() ??
                  {};
              if (!(methods.contains('generateContent') ||
                  methods.contains('embedContent'))) {
                continue;
              }
              out.add(
                ModelSpecResolver.instance
                    .resolve(cfg, id, displayName: displayName)
                    .spec,
              );
            }
          }
        }
      } catch (_) {}

      // Vertex listModels only returns Gemini under publishers/google.
      // Merge Anthropic ids from the models.dev Vertex Anthropic catalog.
      if (cfg.vertexAI == true) {
        final catalog = ModelCatalogService.instance;
        await catalog.ensureLoaded();
        for (final model in catalog.modelsOfProvider(
          'google-vertex-anthropic',
        )) {
          if (!out.any((m) => m.id == model.id)) {
            out.add(
              ModelSpecResolver.instance
                  .resolve(
                    cfg,
                    model.id,
                    displayName: model.name.isEmpty ? null : model.name,
                  )
                  .spec,
            );
          }
        }
      }
      return out;
    } finally {
      client.close();
    }
  }
}

class ProviderManager {
  static String _effectiveApiKey(ProviderConfig cfg) {
    return ApiKeyManager().effectiveKeyForProvider(cfg);
  }

  // Per-model override helpers (duplicated logic from ChatApiService)
  static Map<String, dynamic> _modelOverride(
    ProviderConfig cfg,
    String modelId,
  ) {
    return ModelOverridePayloadParser.modelOverride(
      cfg.modelOverrides,
      modelId,
    );
  }

  static Map<String, String> _customHeaders(
    ProviderConfig cfg,
    String modelId,
  ) {
    final ov = _modelOverride(cfg, modelId);
    return CustomRequestMerger.mergeHeaders(
      providerAutomatic: providerDefaultHeaders(cfg),
      provider: ModelOverridePayloadParser.customHeadersFromRows(
        cfg.customHeaders,
      ),
      model: ModelOverridePayloadParser.customHeaders(ov),
    );
  }

  static Map<String, dynamic> _customBody(ProviderConfig cfg, String modelId) {
    final ov = _modelOverride(cfg, modelId);
    return CustomRequestMerger.mergeBody(
      providerRows: cfg.customBody,
      model: ModelOverridePayloadParser.customBody(ov),
    );
  }

  static BaseProvider forConfig(ProviderConfig cfg) {
    final kind = ProviderConfig.classify(
      cfg.id,
      explicitType: cfg.providerType,
    );
    switch (kind) {
      case ProviderKind.google:
        return GoogleProvider();
      case ProviderKind.claude:
        return ClaudeProvider();
      case ProviderKind.openai:
        return OpenAIProvider();
    }
  }

  static Future<List<ModelSpec>> listModels(ProviderConfig cfg) {
    if (cfg.isOAuth) return ProviderOAuthService.instance.models(cfg);
    return forConfig(cfg).listModels(cfg);
  }

  static Future<void> testConnection(
    ProviderConfig cfg,
    String modelId, {
    bool useStream = false,
  }) async {
    if (ModelSpecResolver.instance.spec(cfg, modelId).isEmbedding) {
      await EmbeddingApiService.embed(
        config: cfg,
        modelId: modelId,
        inputs: const ['hello'],
      );
      return;
    }
    cfg = await ProviderOAuthService.instance.resolve(cfg);
    if (cfg.oauthProvider == OAuthProvider.chatgpt) useStream = true;
    if (cfg.oauthProvider == OAuthProvider.kimi &&
        (cfg.modelOverrides[modelId] as Map?)?['oauthProtocol'] ==
            'anthropic') {
      cfg = cfg.copyWith(providerType: ProviderKind.claude);
    }
    var kind = ProviderConfig.classify(cfg.id, explicitType: cfg.providerType);
    if (kind == ProviderKind.openai) {
      final ov = _modelOverride(cfg, modelId);
      var upstreamId = modelId;
      try {
        final raw = (ov['apiModelId'] ?? ov['api_model_id'])?.toString().trim();
        if (raw != null && raw.isNotEmpty) upstreamId = raw;
      } catch (_) {}
      final protocol = resolveOpenAIWireProtocol(
        cfg,
        modelId,
        upstreamModelId: upstreamId,
      );
      switch (protocol) {
        case OpenAIWireProtocol.responses:
          cfg = cfg.copyWith(
            providerType: ProviderKind.openai,
            useResponseApi: true,
          );
          kind = ProviderKind.openai;
          break;
        case OpenAIWireProtocol.chatCompletions:
          cfg = cfg.copyWith(
            providerType: ProviderKind.openai,
            useResponseApi: false,
          );
          kind = ProviderKind.openai;
          break;
        case OpenAIWireProtocol.anthropicMessages:
          cfg = cfg.copyWith(
            providerType: ProviderKind.claude,
            useResponseApi: false,
          );
          kind = ProviderKind.claude;
          break;
        case OpenAIWireProtocol.googleGenerativeLanguage:
          cfg = cfg.copyWith(
            providerType: ProviderKind.google,
            useResponseApi: false,
            vertexAI: false,
          );
          kind = ProviderKind.google;
          break;
      }
    }
    final sessionHeaders = providerSessionHeaders(cfg);
    final client = ProviderOAuthService.instance.authenticatedClient(
      providerHttpClient(cfg),
      cfg,
    );
    try {
      if (kind == ProviderKind.openai) {
        final base = cfg.baseUrl.endsWith('/')
            ? cfg.baseUrl.substring(0, cfg.baseUrl.length - 1)
            : cfg.baseUrl;
        final ov = _modelOverride(cfg, modelId);
        String upstreamId = modelId;
        try {
          final raw = (ov['apiModelId'] ?? ov['api_model_id'])
              ?.toString()
              .trim();
          if (raw != null && raw.isNotEmpty) upstreamId = raw;
        } catch (_) {}
        final useResponsesApi = shouldUseOpenAIResponsesApi(
          cfg,
          modelId,
          upstreamModelId: upstreamId,
        );
        final path = useResponsesApi
            ? '/responses'
            : (cfg.chatPath ?? '/chat/completions');
        final url = Uri.parse('$base$path');
        final Map<String, dynamic> body = useResponsesApi
            ? <String, dynamic>{
                'model': upstreamId,
                'input': [
                  {'role': 'user', 'content': 'hello'},
                ],
                if (useStream) 'stream': true,
              }
            : <String, dynamic>{
                'model': upstreamId,
                'messages': [
                  {'role': 'user', 'content': 'hello'},
                ],
                if (useStream) 'stream': true,
              };
        // Merge custom body overrides
        final extra = _customBody(cfg, modelId);
        CustomRequestMerger.applyBody(body, extra);
        // Merge custom headers overrides
        final apiKey = _effectiveApiKey(cfg);
        final headers = <String, String>{
          if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          ...?sessionHeaders,
        };
        headers.addAll(_customHeaders(cfg, modelId));
        final res = await client.post(
          url,
          headers: headers,
          body: jsonEncode(body),
        );
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException('HTTP ${res.statusCode}: ${res.body}');
        }
        // For streaming, verify the response contains SSE data
        if (useStream) {
          final contentType = res.headers['content-type'] ?? '';
          if (!contentType.contains('text/event-stream') && res.body.isEmpty) {
            throw HttpException('Stream response expected but not received');
          }
        }
        return;
      } else if (kind == ProviderKind.claude) {
        final base = cfg.baseUrl.endsWith('/')
            ? cfg.baseUrl.substring(0, cfg.baseUrl.length - 1)
            : cfg.baseUrl;
        final url = Uri.parse('$base/messages');
        final ov = _modelOverride(cfg, modelId);
        String upstreamId = modelId;
        try {
          final raw = (ov['apiModelId'] ?? ov['api_model_id'])
              ?.toString()
              .trim();
          if (raw != null && raw.isNotEmpty) upstreamId = raw;
        } catch (_) {}
        final body = <String, dynamic>{
          'model': upstreamId,
          'max_tokens': 8,
          'messages': [
            {'role': 'user', 'content': 'hello'},
          ],
          if (useStream) 'stream': true,
        };
        final extra = _customBody(cfg, modelId);
        if (extra.isNotEmpty) body.addAll(extra);
        final apiKey = _effectiveApiKey(cfg);
        final isOpenCodeGateway =
            Uri.tryParse(cfg.baseUrl)?.host.toLowerCase() == 'opencode.ai';
        final headers = <String, String>{
          'x-api-key': apiKey,
          if (isOpenCodeGateway) 'Authorization': 'Bearer $apiKey',
          'anthropic-version': ClaudeProvider.anthropicVersion,
          'Content-Type': 'application/json',
          ...?sessionHeaders,
        };
        headers.addAll(_customHeaders(cfg, modelId));
        final res = await client.post(
          url,
          headers: headers,
          body: jsonEncode(body),
        );
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException('HTTP ${res.statusCode}: ${res.body}');
        }
        // For streaming, verify the response contains SSE data
        if (useStream) {
          final contentType = res.headers['content-type'] ?? '';
          if (!contentType.contains('text/event-stream') && res.body.isEmpty) {
            throw HttpException('Stream response expected but not received');
          }
        }
        return;
      } else if (kind == ProviderKind.google) {
        // Generative Language API (default) or Vertex AI when vertexAI == true
        final ov = _modelOverride(cfg, modelId);
        // Resolve upstream/api model id for this logical key when present.
        String upstreamId = modelId;
        try {
          final raw = (ov['apiModelId'] ?? ov['api_model_id'])
              ?.toString()
              .trim();
          if (raw != null && raw.isNotEmpty) upstreamId = raw;
        } catch (_) {}

        String url;
        final endpoint = useStream
            ? 'streamGenerateContent'
            : 'generateContent';
        final bool isVertex =
            cfg.vertexAI == true &&
            (cfg.location?.isNotEmpty == true) &&
            (cfg.projectId?.isNotEmpty == true);
        final bool isVertexClaude =
            isVertex && upstreamId.toLowerCase().startsWith('claude-');
        if (isVertex) {
          final loc = cfg.location!;
          final proj = cfg.projectId!;
          if (isVertexClaude) {
            final ep = useStream ? 'streamRawPredict' : 'rawPredict';
            url =
                'https://aiplatform.googleapis.com/v1/projects/$proj/locations/$loc/publishers/anthropic/models/$upstreamId:$ep';
          } else {
            url =
                'https://aiplatform.googleapis.com/v1/projects/$proj/locations/$loc/publishers/google/models/$upstreamId:$endpoint';
          }
        } else {
          final base = cfg.baseUrl.endsWith('/')
              ? cfg.baseUrl.substring(0, cfg.baseUrl.length - 1)
              : cfg.baseUrl;
          url = '$base/models/$upstreamId:$endpoint';
        }
        final wantsImageOutput = ModelSpecResolver.instance
            .spec(cfg, modelId)
            .output
            .contains(Modality.image);
        final Map<String, dynamic> body = isVertexClaude
            ? <String, dynamic>{
                'anthropic_version': 'vertex-2023-10-16',
                'messages': [
                  {'role': 'user', 'content': 'hello'},
                ],
                'max_tokens': 32,
                if (useStream) 'stream': true,
              }
            : <String, dynamic>{
                'contents': [
                  {
                    'role': 'user',
                    'parts': [
                      {'text': 'hello'},
                    ],
                  },
                ],
                if (wantsImageOutput)
                  'generationConfig': {
                    'responseModalities': ['TEXT', 'IMAGE'],
                  },
              };
        final headers = <String, String>{
          'Content-Type': 'application/json',
          ...?sessionHeaders,
        };
        final effectiveKey = _effectiveApiKey(cfg);
        if (cfg.vertexAI == true) {
          final jsonStr = (cfg.serviceAccountJson ?? '').trim();
          if (jsonStr.isNotEmpty) {
            try {
              final token =
                  await GoogleServiceAccountAuth.getAccessTokenFromJson(
                    jsonStr,
                  );
              headers['Authorization'] = 'Bearer $token';
            } catch (_) {}
          } else if (effectiveKey.isNotEmpty) {
            headers['Authorization'] = 'Bearer $effectiveKey';
          }
        } else {
          if (effectiveKey.isNotEmpty) {
            headers['x-goog-api-key'] = effectiveKey;
            if (Uri.tryParse(cfg.baseUrl)?.host.toLowerCase() ==
                'opencode.ai') {
              headers['Authorization'] = 'Bearer $effectiveKey';
            }
          }
        }
        headers.addAll(_customHeaders(cfg, modelId));
        final extra = _customBody(cfg, modelId);
        CustomRequestMerger.applyBody(body, extra);
        final res = await client.post(
          Uri.parse(url),
          headers: headers,
          body: jsonEncode(body),
        );
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException('HTTP ${res.statusCode}: ${res.body}');
        }
        // For streaming, verify the response is not empty
        if (useStream && res.body.isEmpty) {
          throw HttpException('Stream response expected but not received');
        }
        return;
      }
    } finally {
      client.close();
    }
  }
}
