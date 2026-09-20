import '../../models/provider_oauth.dart';
import 'package:uuid/uuid.dart';

import '../../providers/settings_provider.dart';

const String _openRouterAppReferer = 'https://github.com/Chevey339/kelivo';
const String _openRouterAppTitle = 'Kelivo';
const String _openRouterAppCategories = 'general-chat';

// OpenCode's own request layer currently identifies inference traffic as
// `opencode/<installation-version>`. Community compatibility proxies use the
// same identity because some Zen/Go routes gate or classify traffic by UA.
//
// Keep this in one place so it can be bumped independently when OpenCode
// changes its client contract. Custom headers are merged afterwards and may
// override any of these defaults.
const String _openCodeCompatUserAgent = 'opencode/1.18.31';

/// Resolve once per generation, before retries and tool follow-up rounds.
Map<String, String>? providerSessionHeaders(
  ProviderConfig config, {
  String? conversationId,
  Map<String, String>? extraHeaders,
}) {
  final host = Uri.tryParse(config.baseUrl)?.host.toLowerCase();
  if (config.isOAuth) {
    final id = conversationId?.trim() ?? '';
    final session = id.isEmpty ? const Uuid().v4() : id;
    return {
      if (config.oauthProvider == OAuthProvider.chatgpt) ...{
        'session_id': session,
        'conversation_id': session,
        'x-client-request-id': session,
      },
      if (config.oauthProvider == OAuthProvider.grok) 'x-grok-conv-id': session,
      if (config.oauthProvider == OAuthProvider.claude)
        'X-Claude-Code-Session-Id': session,
      ...?extraHeaders,
    };
  }
  if (host != 'opencode.ai') return extraHeaders;

  final id = conversationId?.trim() ?? '';
  final session = id.isEmpty ? const Uuid().v4() : id;
  final request = 'msg_${const Uuid().v4()}';

  return {
    'User-Agent': _openCodeCompatUserAgent,
    'x-opencode-session': session,
    'x-opencode-request': request,
    'x-opencode-client': 'cli',
    // Mirrors the established community Go proxy default. OpenCode's native
    // client only includes a project header when it has a project id.
    'x-opencode-project': 'global',
    ...?extraHeaders,
  };
}

bool isOpenRouterProvider(ProviderConfig config) {
  final host = Uri.tryParse(config.baseUrl)?.host.toLowerCase() ?? '';
  return host.contains('openrouter.ai');
}

Map<String, String> providerDefaultHeaders(ProviderConfig config) {
  if (!isOpenRouterProvider(config)) return const <String, String>{};
  return const <String, String>{
    'HTTP-Referer': _openRouterAppReferer,
    'X-OpenRouter-Title': _openRouterAppTitle,
    'X-OpenRouter-Categories': _openRouterAppCategories,
  };
}
