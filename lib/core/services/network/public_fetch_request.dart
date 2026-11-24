import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../providers/settings_provider.dart';
import '../logging/log_redactor.dart';
import 'public_fetch_connection.dart';
import 'request_logger.dart';

/// Owns one fetch, including its redirect chain and response body.
class PublicFetchRequest {
  PublicFetchRequest({required this.timeout, this.logRequests = false});

  final Duration timeout;
  final bool logRequests;

  // A fixture can supply a transport for its synthetic origin. Normal app
  // HTTP overrides (including proxies) never authorize a private destination.
  @visibleForTesting
  static HttpClient? Function(Uri)? fixtureClient;

  final _stopped = Completer<void>();
  HttpClient? _socketClient;

  void cancel() {
    if (_stopped.isCompleted) return;
    _stopped.complete();
    _socketClient?.close(force: true);
  }

  Future<http.Response> send(
    Uri url, {
    required String userAgent,
    String method = 'GET',
    Map<String, String> headers = const {},
    List<int>? body,
    http.Client? client,
  }) async {
    try {
      return await Future.any([
        _follow(url, method, userAgent, headers, body, client),
        _stopped.future.then<http.Response>(
          (_) => throw const HttpException('Fetch cancelled'),
        ),
      ]).timeout(timeout);
    } finally {
      cancel();
    }
  }

  Future<http.Response> _follow(
    Uri url,
    String method,
    String userAgent,
    Map<String, String> headers,
    List<int>? body,
    http.Client? injected,
  ) async {
    final requestHeaders = <String, String>{...headers};
    for (var redirects = 0; ; redirects++) {
      _checkActive();
      validatePublicFetchUrl(url);
      final request = http.Request(method, url)
        ..followRedirects = false
        ..headers['User-Agent'] = userAgent
        ..headers.addAll(requestHeaders);
      if (body != null) request.bodyBytes = body;

      final client = injected ?? _openClient(url);
      final logId = logRequests && RequestLogger.enabled
          ? RequestLogger.nextRequestId()
          : null;
      if (logId != null) {
        RequestLogger.logLine(
          '[REQ $logId] $method ${LogRedactor.redactUrl(url.toString())}',
        );
        RequestLogger.logLine(
          '[REQ $logId] headers=${RequestLogger.encodeObject(LogRedactor.redactHeaders(request.headers))}',
        );
      }
      try {
        final response = await client.send(request);
        if (logId != null) {
          RequestLogger.logLine('[RES $logId] status=${response.statusCode}');
          RequestLogger.logLine(
            '[RES $logId] headers=${RequestLogger.encodeObject(LogRedactor.redactHeaders(response.headers))}',
          );
        }
        final status = response.statusCode;
        final location = response.headers['location'];
        if (location == null ||
            !const {301, 302, 303, 307, 308}.contains(status) ||
            (method == 'POST' && status != 303)) {
          final result = await http.Response.fromStream(response);
          if (logId != null && (RequestLogger.saveOutput || status >= 400)) {
            // Redact the complete text: a credential can span socket chunks.
            final text = RequestLogger.elidePayloads(
              RequestLogger.safeDecodeUtf8(result.bodyBytes),
            );
            final safe = LogRedactor.redactBody(
              LogRedactor.redactUrlsInText(text),
            );
            RequestLogger.logLine(
              '[RES $logId] body=${RequestLogger.escape(safe)}',
            );
          }
          return result;
        }
        await response.stream.listen(null).cancel();
        if (redirects >= request.maxRedirects) {
          throw const HttpException('Too many fetch redirects');
        }
        var next = url.resolve(location);
        validatePublicFetchUrl(next);
        if (next.origin != url.origin) {
          requestHeaders.clear();
          // dart:io synthesizes Basic authorization from URI user info.
          next = next.replace(userInfo: '');
        }
        if (method == 'POST') {
          method = 'GET';
          body = null;
          requestHeaders.removeWhere(
            (k, _) =>
                k.toLowerCase().startsWith('content-') ||
                k.toLowerCase() == 'transfer-encoding',
          );
        }
        url = next;
      } catch (e) {
        if (logId != null) {
          RequestLogger.logLine(
            '[RES $logId] error=${RequestLogger.escape(LogRedactor.redactText(e.toString()))}',
          );
        }
        rethrow;
      } finally {
        if (logId != null) RequestLogger.logLine('[RES $logId] done');
        if (injected == null) {
          _socketClient?.close(force: true);
          _socketClient = null;
          client.close();
        }
      }
    }
  }

  http.Client _openClient(Uri url) {
    final fixture = kDebugMode ? fixtureClient?.call(url) : null;
    final io = fixture ?? HttpClient();
    _socketClient = io;
    if (fixture == null) {
      io.connectionFactory = (uri, proxyHost, _) async {
        if (proxyHost != null ||
            SettingsProvider.routesThroughGlobalProxy(uri)) {
          throw const SocketException(
            'Fetch requires a direct public connection',
          );
        }
        final task = await connectPublicFetch(uri, _checkActive);
        // close(force: true) can run before dart:io registers this task.
        unawaited(_stopped.future.then((_) => task.cancel()));
        return task;
      };
    }
    return IOClient(io);
  }

  void _checkActive() {
    if (_stopped.isCompleted) throw const HttpException('Fetch cancelled');
  }
}
