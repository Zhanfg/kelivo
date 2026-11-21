import 'package:Kelivo/core/services/mcp/kelivo_fetch/kelivo_fetch_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// #97 read-only baseline evidence; no requests leave this test process.
void main() {
  test('baseline diagnostic: parser accepts loopback HTTP (SSRF gap)', () {
    final payload = KelivoFetchRequestPayload.parse({
      'url': 'http://127.0.0.1:8080/private',
    });
    // This documents the current unsafe acceptance, not a security pass.
    expect(payload.url.host, '127.0.0.1');
    expect(payload.url.scheme, 'http');
  });

  test('POST pagination replay is rejected by existing implementation', () {
    expect(
      () => KelivoFetchRequestPayload.parse({
        'url': 'https://example.org/create',
        'method': 'POST',
        'body': '{"name":"x"}',
        'start_index': 20,
      }),
      throwsArgumentError,
    );
  });

  test('unsupported destructive verbs are rejected', () {
    expect(
      () => KelivoFetchRequestPayload.parse({
        'url': 'https://example.org/resource',
        'method': 'DELETE',
      }),
      throwsArgumentError,
    );
  });

  test(
    'SSRF guard rejects loopback, link-local and private IP literals',
    () {
      for (final url in [
        'http://127.0.0.1:8080/private',
        'http://169.254.169.254/latest/meta-data',
        'https://192.168.1.1/admin',
        'http://[::1]/',
      ]) {
        expect(
          () => KelivoFetchRequestPayload.parse({'url': url}),
          throwsArgumentError,
        );
      }
    },
    skip:
        '#97 BLOCKED: production URI admission and DNS rebinding protections not implemented',
  );

  test(
    'redirect target and credential forwarding require live transport review',
    () {
      // This requires a controlled HTTP adapter and explicit per-hop policy.
    },
    skip:
        '#97 BLOCKED: no redirect admission/header redaction policy; do not use network tests as proof',
  );
}
