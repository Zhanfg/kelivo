part of 'provider_oauth_adapter.dart';

class FreeBuffOAuthAdapter extends ProviderOAuthAdapter {
  FreeBuffOAuthAdapter({Future<String> Function()? fingerprintProvider})
    : this._fingerprintProvider = fingerprintProvider;

  static const _authBase = 'https://open.freebuff.app';
  final Future<String> Function()? _fingerprintProvider;

  @override
  OAuthProvider get provider => OAuthProvider.freebuff;

  @override
  Duration get tokenRequestTimeout => const Duration(seconds: 30);

  @override
  Future<ProviderOAuthCredentials> login(
    OAuthWire wire,
    OAuthCancellation cancellation,
    OAuthPromptHandler onPrompt, {
    bool deviceCode = true,
    OAuthUrlLauncher? launcher,
  }) async {
    cancellation.check();

    final fingerprint = await _fingerprint();
    final start = await wire.request(
      '$_authBase/api/auth/start',
      json: {'fingerprintId': fingerprint},
      timeout: tokenRequestTimeout,
    );
    if (!start.ok) {
      throw _requestFailure(start, null, secrets: [fingerprint]);
    }

    final loginUrl = oauthString(start.data['loginUrl']);
    final expiresAt = oauthNumber(start.data['expiresAt']);
    final cookie = _loginCookie(start.headers['set-cookie']);
    final uri = Uri.tryParse(loginUrl ?? '');
    if (loginUrl == null ||
        expiresAt == null ||
        cookie == null ||
        uri == null ||
        uri.scheme != 'https' ||
        !_isAllowedLoginHost(uri.host)) {
      throw ProviderOAuthException(
        ProviderOAuthFailure.invalidResponse,
        statusCode: start.status,
      );
    }

    cancellation.check();
    await onPrompt(OAuthLoginPrompt(url: uri));

    final upstreamDeadline = DateTime.fromMillisecondsSinceEpoch(
      expiresAt.toInt(),
    );
    final tenMinutes = DateTime.now().add(const Duration(minutes: 10));
    final deadline = upstreamDeadline.isBefore(tenMinutes)
        ? upstreamDeadline
        : tenMinutes;

    String? transactionId;
    while (DateTime.now().isBefore(deadline)) {
      await cancellation.wait(const Duration(seconds: 3));
      cancellation.check();
      final status = await wire.request(
        '$_authBase/api/auth/status',
        headers: {'Cookie': cookie},
        timeout: const Duration(seconds: 15),
      );
      cancellation.check();
      if (!status.ok) {
        if (status.status >= 500) continue;
        throw _requestFailure(status, null, secrets: [fingerprint]);
      }
      if (status.data['pending'] == true) continue;
      transactionId = oauthString(status.data['transactionId']);
      if (transactionId == null) {
        throw ProviderOAuthException(
          ProviderOAuthFailure.invalidResponse,
          statusCode: status.status,
        );
      }
      break;
    }

    if (transactionId == null) {
      throw const ProviderOAuthException(ProviderOAuthFailure.timeout);
    }

    cancellation.check();
    final register = await wire.request(
      '$_authBase/api/auth/register',
      headers: {'Cookie': cookie},
      json: {'transactionId': transactionId},
      timeout: tokenRequestTimeout,
    );
    if (!register.ok) {
      throw _requestFailure(
        register,
        null,
        secrets: [fingerprint, transactionId],
      );
    }

    final apiKey = oauthString(register.data['apiKey']);
    final user = oauthMap(register.data['user']);
    if (apiKey == null || !apiKey.startsWith('sk-fb-')) {
      throw ProviderOAuthException(
        ProviderOAuthFailure.invalidResponse,
        statusCode: register.status,
      );
    }

    return ProviderOAuthCredentials(
      accessToken: apiKey,
      refreshToken: apiKey,
      expiresAt: DateTime.now().add(const Duration(days: 3650)),
      sessionId: const Uuid().v4(),
      accountId: oauthString(user['id']),
      email: oauthString(user['email']),
      plan: 'FreeBuff',
      deviceId: fingerprint,
    );
  }

  @override
  Future<ProviderOAuthCredentials> refresh(
    OAuthWire wire,
    ProviderOAuthCredentials stored,
  ) async {
    final response = await wire.request(
      '${provider.baseUrl}/models',
      headers: headers(stored),
      timeout: tokenRequestTimeout,
    );
    if (!response.ok) {
      final failure = _requestFailure(response, stored);
      if (response.status == 401 || response.status == 403) {
        throw ProviderOAuthException(
          ProviderOAuthFailure.loginRequired,
          statusCode: response.status,
          code: failure.code,
          message: failure.message,
        );
      }
      throw failure;
    }
    return stored.copyWith(
      expiresAt: DateTime.now().add(const Duration(days: 3650)),
      requiresLogin: false,
    );
  }

  @override
  Future<ProviderUsageSnapshot> usage(
    OAuthWire wire,
    ProviderOAuthCredentials credentials,
  ) async {
    await get(wire, '${provider.baseUrl}/models', credentials);
    return ProviderUsageSnapshot(
      windows: const [],
      fetchedAt: DateTime.now(),
      plan: 'FreeBuff',
      allowed: true,
      limitReached: false,
    );
  }

  @override
  Future<void> logout(
    OAuthWire wire,
    ProviderOAuthCredentials credentials,
  ) async {
    try {
      await wire.request(
        '$_authBase/api/auth/revoke',
        json: {'apiKey': credentials.accessToken},
        timeout: tokenRequestTimeout,
      );
    } catch (_) {
      // Local logout must still succeed if remote revocation is unavailable.
    }
  }

  Future<String> _fingerprint() async {
    final persisted = await _fingerprintProvider?.call();
    if (persisted != null && persisted.startsWith('codebuff-cli-')) {
      return persisted;
    }
    return 'codebuff-cli-${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
  }

  bool _isAllowedLoginHost(String host) {
    final value = host.trim().toLowerCase();
    return value == 'freebuff.com' ||
        value.endsWith('.freebuff.com') ||
        value == 'codebuff.com' ||
        value.endsWith('.codebuff.com');
  }

  String? _loginCookie(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(
      r'(?:^|,\s*)(freebuff_login=[^;,\s]+)',
    ).firstMatch(raw);
    return match?.group(1);
  }
}
