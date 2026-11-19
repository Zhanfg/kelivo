import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef DiscoveryFetch = Future<Map<String, Object?>> Function(Uri uri);

class SkillDiscoveryException implements Exception {
  const SkillDiscoveryException(this.code);
  final String code;
  @override
  String toString() => 'SkillDiscoveryException($code)';
}

class SkillCandidate {
  const SkillCandidate({
    required this.name,
    required this.slug,
    required this.source,
    required this.installs,
    required this.landingUrl,
    required this.foundAt,
    this.sourceVerified = false,
    this.warning,
  });

  final String name;
  final String slug;
  final String source;
  final int installs;
  final Uri landingUrl;
  final DateTime foundAt;
  final bool sourceVerified;
  final String? warning;
}

/// Read-only discovery. Search results are untrusted and never installed.
class SkillsDiscovery {
  SkillsDiscovery({DiscoveryFetch? fetch, DateTime Function()? clock})
    : _fetch = fetch ?? _fetchJson,
      _clock = clock ?? DateTime.now;

  static final Uri _endpoint = Uri.https('skills.sh', '/api/search');
  final DiscoveryFetch _fetch;
  final DateTime Function() _clock;

  Future<List<SkillCandidate>> search(
    String query, {
    String? owner,
    int limit = 20,
  }) async {
    final term = query.trim();
    if (term.isEmpty ||
        term.length > 160 ||
        term.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const SkillDiscoveryException('invalid_query');
    }
    if (owner != null &&
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9-]{0,38}$').hasMatch(owner)) {
      throw const SkillDiscoveryException('invalid_owner');
    }
    if (limit < 1 || limit > 100) {
      throw const SkillDiscoveryException('invalid_limit');
    }
    final uri = _endpoint.replace(
      queryParameters: {'q': term, if (owner != null) 'owner': owner},
    );
    final Map<String, Object?> document;
    try {
      document = await _fetch(uri).timeout(const Duration(seconds: 12));
    } on SkillDiscoveryException {
      rethrow;
    } on TimeoutException {
      throw const SkillDiscoveryException('timeout');
    } catch (_) {
      throw const SkillDiscoveryException('network_error');
    }
    final rows = document['skills'];
    if (rows is! List) {
      throw const SkillDiscoveryException('invalid_response');
    }
    final output = <SkillCandidate>[];
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final id = row['id'];
      final name = row['name'];
      final source = row['source'];
      final installs = row['installs'];
      if (id is! String ||
          name is! String ||
          source is! String ||
          id.length > 200 ||
          name.length > 200 ||
          !RegExp(
            r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$',
          ).hasMatch(id)) {
        continue;
      }
      final parts = id.split('/');
      final landing = Uri.https('skills.sh', '/${parts.join('/')}');
      if (!seen.add(id)) continue;
      output.add(
        SkillCandidate(
          name: name,
          slug: parts.last,
          source: source,
          installs: installs is int && installs >= 0 ? installs : 0,
          landingUrl: landing,
          foundAt: _clock().toUtc(),
          warning: 'Unverified third-party skill; review before importing.',
        ),
      );
      if (output.length >= limit) break;
    }
    return List<SkillCandidate>.unmodifiable(output);
  }

  static Future<Map<String, Object?>> _fetchJson(Uri uri) async {
    if (uri.scheme != 'https' ||
        uri.host != 'skills.sh' ||
        uri.path != '/api/search') {
      throw const SkillDiscoveryException('invalid_endpoint');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..autoUncompress = true;
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode == 429) {
        throw const SkillDiscoveryException('rate_limited');
      }
      if (response.statusCode != 200) {
        throw const SkillDiscoveryException('http_error');
      }
      const maxBytes = 1024 * 1024;
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const SkillDiscoveryException('response_too_large');
        }
        bytes.addAll(chunk);
      }
      final parsed = jsonDecode(utf8.decode(bytes));
      if (parsed is! Map<String, dynamic>) {
        throw const SkillDiscoveryException('invalid_response');
      }
      return parsed;
    } on SkillDiscoveryException {
      rethrow;
    } catch (_) {
      throw const SkillDiscoveryException('network_error');
    } finally {
      client.close(force: true);
    }
  }
}