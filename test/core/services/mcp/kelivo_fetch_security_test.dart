import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart';
import 'package:Kelivo/core/services/network/request_logger.dart';
import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:Kelivo/core/services/search/web_fetch_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _fixtureWait = Duration(seconds: 5);
const _deadline = Duration(seconds: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final privateHosts = {
    'IPv4 loopback': '127.0.0.1',
    'IPv6 loopback': '::1',
    'IPv4 link-local': '169.254.1.1',
    'IPv6 link-local': 'fe80::1',
    '10/8 private range': '10.1.1.1',
    '172.16/12 private range': '172.16.1.1',
    '192.168/16 private range': '192.168.1.1',
    'IPv6 unique local': 'fd00::1',
  };
  for (final (name, fetchFails) in [
    ('@kelivo/fetch', _mcpFetchFails),
    ('local fetch_url', _localFetchFails),
  ]) {
    group('$name network boundaries', () {
      for (final entry in privateHosts.entries) {
        test('blocks ${entry.key} before connecting', () async {
          final network = _FixtureNetwork();
          final url = Uri(scheme: 'http', host: entry.value, path: '/fixture');

          final failed = await network.run(() => fetchFails(url));

          expect(network.attempts, isEmpty);
          expect(failed, isTrue);
        });
      }

      for (final (label, host) in [
        ('loopback', '127.0.0.1'),
        ('private range', '10.1.1.1'),
      ]) {
        test('blocks a redirect from a public fixture to $label', () async {
          final target = Uri(scheme: 'http', host: host, path: '/fixture');
          final source = await _serve('public.test', (request) {
            request.response
              ..statusCode = HttpStatus.found
              ..headers.set(HttpHeaders.locationHeader, target.toString());
          });
          final network = _FixtureNetwork([source]);

          final failed = await network.run(() => fetchFails(source));

          expect(network.attempts, [source]);
          expect(failed, isTrue);
        });
      }
    });
  }

  group('@kelivo/fetch redirects', () {
    for (final (label, targetHost, headers) in [
      (
        'an unrelated origin',
        'other.test',
        {
          'Authorization': 'Bearer fixture-auth',
          'Cookie': 'sid=fixture-cookie',
        },
      ),
      (
        'a subdomain origin',
        'child.source.test',
        {
          'Authorization': 'Bearer fixture-auth',
          'Cookie': 'sid=fixture-cookie',
        },
      ),
      (
        'an unrelated origin with an API key',
        'other.test',
        {'X-Api-Key': 'fixture-key'},
      ),
    ]) {
      test('strips credentials on a redirect to $label', () async {
        final sourceHeaders = <String, String?>{};
        final targetHeaders = <String, String?>{};
        late Uri target;
        final source = await _serve('source.test', (request) {
          final received = request.uri.path == '/target'
              ? targetHeaders
              : sourceHeaders;
          for (final name in headers.keys) {
            received[name] = request.headers.value(name);
          }
          if (request.uri.path == '/target') {
            request.response.write('fixture response');
          } else {
            request.response
              ..statusCode = HttpStatus.found
              ..headers.set(HttpHeaders.locationHeader, target.toString());
          }
        });
        target = source.replace(host: targetHost, path: '/target');
        final network = _FixtureNetwork([source, target]);

        final result = await network.run(
          () => _callMcp(source, {'headers': headers}),
        );

        expect(result.isError, isFalse);
        expect(result.text, 'fixture response');
        expect(sourceHeaders, headers);
        expect(targetHeaders, {for (final name in headers.keys) name: null});
      });
    }

    for (final status in [
      HttpStatus.movedPermanently,
      HttpStatus.found,
      HttpStatus.seeOther,
      HttpStatus.temporaryRedirect,
      HttpStatus.permanentRedirect,
    ]) {
      test('does not replay a POST body after HTTP $status', () async {
        final original = <(String, String)>[];
        final redirected = <(String, String)>[];
        const body = '{"fixture": true}';
        final source = await _serve('source.test', (request) async {
          final received = (
            request.method,
            await utf8.decoder.bind(request).join(),
          );
          if (request.uri.path == '/target') {
            redirected.add(received);
            request.response.write('fixture response');
          } else {
            original.add(received);
            request.response
              ..statusCode = status
              ..headers.set(HttpHeaders.locationHeader, '/target');
          }
        });
        final network = _FixtureNetwork([source]);

        final result = await network.run(
          () => _callMcp(source, {'method': 'POST', 'body': body}),
        );

        expect(original, [('POST', body)]);
        if (status == HttpStatus.seeOther) {
          expect(redirected, [('GET', '')]);
          expect(result.isError, isFalse);
        } else {
          expect(redirected, isEmpty);
          expect(result.isError, isTrue);
          expect(result.text, 'HTTP $status');
        }
      });
    }
  });

  group('local fetch_url request logs', () {
    for (final includeLocation in [false, true]) {
      test(
        includeLocation
            ? 'redacts credentials in a response Location URL'
            : 'redacts URL credentials and sensitive response headers',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'kelivo_fetch_logs_',
          );
          final previousPaths = PathProviderPlatform.instance;
          final previousSaveOutput = RequestLogger.saveOutput;
          PathProviderPlatform.instance = _LogPaths(directory.path);
          RequestLogger.saveOutput = false;
          addTearDown(() async {
            await RequestLogger.setEnabled(false);
            RequestLogger.saveOutput = previousSaveOutput;
            PathProviderPlatform.instance = previousPaths;
            await directory.delete(recursive: true);
          });
          await RequestLogger.setEnabled(true);

          final source = await _serve('source.test', (request) {
            request.response.headers.set(
              HttpHeaders.setCookieHeader,
              'sid=test-cookie',
            );
            if (includeLocation) {
              request.response
                ..statusCode = HttpStatus.created
                ..headers.set(
                  HttpHeaders.locationHeader,
                  'http://test:location-password@other.test/?token=location-token',
                );
            }
            request.response.write('fixture response');
          });
          final url = source.replace(
            userInfo: 'test:request-password',
            queryParameters: {'token': 'request-key'},
          );
          final network = _FixtureNetwork([source]);
          final page = await network.run(() => _fetchLocally(url));
          expect(page.content, 'fixture response');

          final log = await _readRequestLog(directory);

          expect(log, contains('GET http://source.test:'));
          expect(log, contains('set-cookie'));
          for (final secret in [
            'request-password',
            'request-key',
            'test-cookie',
            if (includeLocation) ...['location-password', 'location-token'],
          ]) {
            expect(log, isNot(contains(secret)));
          }
        },
      );
    }
  });

  test('local fetch_url times out and closes a stalled connection', () async {
    final fixture = await _stallingServer();
    final network = _FixtureNetwork([fixture.url]);
    final result = expectLater(
      network.run(() => _fetchLocally(fixture.url, timeout: _deadline)),
      throwsA(
        predicate(
          (Object error) => error.toString().toLowerCase().contains('timeout'),
        ),
      ),
    );

    await fixture.received.timeout(_fixtureWait);
    await result.timeout(_fixtureWait);
    await fixture.disconnected.timeout(_fixtureWait);
  });

  test(
    '@kelivo/fetch closes the HTTP connection when its MCP call times out',
    () async {
      final fixture = await _stallingServer();
      final network = _FixtureNetwork([fixture.url]);
      final client = mcp.McpClient.createClient(
        mcp.McpClient.simpleConfig(
          name: 'fixture',
          version: '1.0.0',
          requestTimeout: _deadline,
        ),
      );
      addTearDown(client.disconnect);
      final engine = KelivoFetchMcpServerEngine();
      await client.connect(KelivoInMemoryClientTransport(engine));

      final result = expectLater(
        network.run(
          () =>
              client.callTool('kelivo_fetch', {'url': fixture.url.toString()}),
        ),
        throwsA(
          predicate(
            (Object error) => error.toString().contains('Request timed out'),
          ),
        ),
      );

      await fixture.received.timeout(_fixtureWait);
      await result.timeout(_fixtureWait);
      await expectLater(
        fixture.disconnected.timeout(_deadline),
        completes,
        reason: 'The MCP timeout must cancel the underlying HTTP request',
      );
    },
  );
}

Future<({bool isError, String text})> _callMcp(
  Uri url, [
  Map<String, dynamic> arguments = const {},
]) async {
  final engine = KelivoFetchMcpServerEngine();
  addTearDown(engine.close);
  final response =
      await engine.handleMessage({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': {
              'name': 'kelivo_fetch',
              'arguments': {'url': url.toString(), ...arguments},
            },
          })
          as Map<String, dynamic>;
  final result = response['result'] as Map<String, dynamic>;
  final content = (result['content'] as List).single as Map<String, dynamic>;
  return (isError: result['isError'] as bool, text: content['text'] as String);
}

Future<bool> _mcpFetchFails(Uri url) async => (await _callMcp(url)).isError;

Future<bool> _localFetchFails(Uri url) async {
  try {
    await _fetchLocally(url);
    return false;
  } on Exception {
    return true;
  }
}

Future<WebFetchPage> _fetchLocally(
  Uri url, {
  Duration timeout = _fixtureWait,
}) => WebFetchService.fetch(
  const LocalWebFetchSource(),
  url.toString(),
  commonOptions: SearchCommonOptions(timeout: timeout.inMilliseconds),
);

Future<Uri> _serve(
  String host,
  FutureOr<void> Function(HttpRequest) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    await handler(request);
    await request.response.close();
  });
  return Uri(scheme: 'http', host: host, port: server.port, path: '/fixture');
}

Future<({Uri url, Future<void> received, Future<void> disconnected})>
_stallingServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final received = Completer<void>();
  final disconnected = Completer<void>();
  final sockets = <Socket>[];
  addTearDown(() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  });
  server.listen((socket) {
    sockets.add(socket);
    socket.listen(
      (_) {
        if (!received.isCompleted) received.complete();
      },
      onDone: () {
        socket.destroy();
        if (!disconnected.isCompleted) disconnected.complete();
      },
    );
  });
  return (
    url: Uri(
      scheme: 'http',
      host: 'source.test',
      port: server.port,
      path: '/stall',
    ),
    received: received.future,
    disconnected: disconnected.future,
  );
}

class _FixtureNetwork extends HttpOverrides {
  _FixtureNetwork([Iterable<Uri> fixtures = const []])
    : _endpoints = {for (final uri in fixtures) (uri.host, uri.port)};

  final Set<(String, int)> _endpoints;
  final attempts = <Uri>[];

  Future<T> run<T>(Future<T> Function() request) =>
      HttpOverrides.runWithHttpOverrides(request, this);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, _, _) async {
      attempts.add(uri);
      // Only the named fixtures open sockets. Block every other destination
      // before DNS or TCP, even if the production URL checks let it through.
      if (!uri.isScheme('http') || !_endpoints.contains((uri.host, uri.port))) {
        throw const SocketException('Destination is outside the test fixtures');
      }
      return Socket.startConnect(InternetAddress.loopbackIPv4, uri.port);
    };
    return client;
  }
}

class _LogPaths extends PathProviderPlatform {
  _LogPaths(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<String> _readRequestLog(Directory directory) async {
  final file = File('${directory.path}/logs/logs.txt');
  final timer = Stopwatch()..start();
  while (timer.elapsed < _fixtureWait) {
    if (await file.exists()) {
      final log = await file.readAsString();
      if (RegExp(r'\[RES \d+\] done').hasMatch(log)) return log;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError(
    'Request logger did not finish writing the fixture response',
  );
}
