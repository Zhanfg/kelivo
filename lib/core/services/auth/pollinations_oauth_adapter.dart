part of 'provider_oauth_adapter.dart';

class PollinationsOAuthAdapter extends ProviderOAuthAdapter {
  static const _authBase = 'https://enter.pollinations.ai';

  @override
  OAuthProvider get provider => OAuthProvider.pollinations;

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

    // Pollinations' official SDK supports device authorization without an
    // embedded app key. This keeps Kelivo free of a shared secret or bundled
    // user credential while still returning a user-scoped sk_ key.
    final init = await wire.request(
      '$_authBase/api/device/code',
      json: const <String, dynamic>{},
      timeout: tokenRequestTimeout,
    );
    if (!init.ok) throw _requestFailure(init, null);

    final device = oauthString(init.data['device_code']);
    final userCode = oauthString(init.data['user_code']);
    final verificationRaw =
        oauthString(init.data['verification_uri_complete']) ??
        oauthString(init.data['verification_uri']);
    if (device == null || userCode == null || verificationRaw == null) {
      throw ProviderOAuthException(
        ProviderOAuthFailure.invalidResponse,
        statusCode: init.status,
      );
    }

    final parsed = Uri.tryParse(verificationRaw);
    final verification = parsed == null
        ? null
        : parsed.hasScheme
        ? parsed
        : Uri.parse(_authBase).resolveUri(parsed);
    if (verification == null || verification.scheme != 'https') {
      throw ProviderOAuthException(
        ProviderOAuthFailure.invalidResponse,
        statusCode: init.status,
      );
    }

    var interval = Duration(
      seconds: (oauthNumber(init.data['interval']) ?? 5).clamp(1, 60).toInt(),
    );
    final expiresIn =
        (oauthNumber(init.data['expires_in']) ?? 600).clamp(60, 3600).toInt();
    final deadline = DateTime.now().add(Duration(seconds: expiresIn));

    await onPrompt(
      OAuthLoginPrompt(url: verification, userCode: userCode),
    );

    while (DateTime.now().isBefore(deadline)) {
      await cancellation.wait(interval);
      cancellation.check();

      final token = await wire.request(
        '$_authBase/api/device/token',
        json: {'device_code': device},
        timeout: tokenRequestTimeout,
      );
      cancellation.check();

      final accessToken = oauthString(token.data['access_token']);
      if (token.ok && accessToken != null) {
        if (!accessToken.startsWith('sk_')) {
          throw ProviderOAuthException(
            ProviderOAuthFailure.invalidResponse,
            statusCode: token.status,
          );
        }

        Map<String, dynamic> user = const {};
        try {
          final info = await wire.request(
            '$_authBase/api/device/userinfo',
            headers: {'Authorization': 'Bearer $accessToken'},
            timeout: tokenRequestTimeout,
          );
          if (info.ok) user = info.data;
        } catch (_) {
          // Identity metadata is optional; a valid issued key is sufficient.
        }

        final lifetimeSeconds =
            (oauthNumber(token.data['expires_in']) ?? 604800)
                .clamp(60, 2592000)
                .toInt();

        return ProviderOAuthCredentials(
          accessToken: accessToken,
          refreshToken: '',
          expiresAt: DateTime.now().add(
            Duration(seconds: lifetimeSeconds),
          ),
          sessionId: const Uuid().v4(),
          accountId:
              oauthString(user['sub']) ?? oauthString(user['id']),
          email: oauthString(user['email']),
          plan: 'Pollinations',
        );
      }

      final error =
          oauthString(token.data['error']) ??
          oauthString(oauthMap(token.data['error'])['code']);
      if (error == 'authorization_pending') continue;
      if (error == 'slow_down') {
        interval += const Duration(seconds: 5);
        continue;
      }
      if (error == 'access_denied') {
        throw ProviderOAuthException(
          ProviderOAuthFailure.denied,
          statusCode: token.status,
          code: error,
        );
      }
      if (error == 'expired_token') {
        throw ProviderOAuthException(
          ProviderOAuthFailure.timeout,
          statusCode: token.status,
          code: error,
        );
      }
      throw _requestFailure(token, null, secrets: [device]);
    }

    throw const ProviderOAuthException(ProviderOAuthFailure.timeout);
  }

  @override
  Future<ProviderOAuthCredentials> refresh(
    OAuthWire wire,
    ProviderOAuthCredentials stored,
  ) async {
    // Pollinations user-authorized device keys intentionally have no refresh
    // token. Once their declared lifetime ends (or the server returns 401),
    // re-run the consent flow instead of silently minting another credential.
    throw ProviderOAuthException(
      ProviderOAuthFailure.loginRequired,
      providerId: provider.name,
    );
  }

  @override
  Future<ProviderUsageSnapshot> usage(
    OAuthWire wire,
    ProviderOAuthCredentials credentials,
  ) async {
    await get(
      wire,
      '$_authBase/api/device/userinfo',
      credentials,
    );
    return ProviderUsageSnapshot(
      windows: const [],
      fetchedAt: DateTime.now(),
      plan: 'Pollinations',
      allowed: true,
      limitReached: false,
    );
  }
}
