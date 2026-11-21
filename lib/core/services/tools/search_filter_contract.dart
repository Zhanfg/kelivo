import 'dart:io';

/// Formats that a reader can supply as extracted text or structured content.
enum WebDocumentFormat { html, pdf, structured }

class WebSearchResult {
  const WebSearchResult({
    required this.title,
    required this.sourceUrl,
    required this.text,
    required this.timestamp,
  });

  final String title;
  final Uri sourceUrl;
  final String text;
  final DateTime timestamp;
}

class WebFetchAdmission {
  const WebFetchAdmission(this.url, this.addresses, this.reasons);

  final Uri url;
  final List<InternetAddress> addresses;
  final List<String> reasons;

  bool get allowed => reasons.isEmpty;
}

class WebDocumentReference {
  const WebDocumentReference({
    required this.sourceUrl,
    required this.fetchedAt,
    required this.startIndex,
    required this.endIndex,
  });

  final Uri sourceUrl;
  final DateTime fetchedAt;
  final int startIndex;
  final int endIndex;
}

class WebDocumentArtifact {
  const WebDocumentArtifact({
    required this.title,
    required this.format,
    required this.content,
    required this.reference,
    required this.totalLength,
    required this.nextStartIndex,
  });

  final String title;
  final WebDocumentFormat format;
  final String content;
  final WebDocumentReference reference;
  final int totalLength;
  final int? nextStartIndex;
}

/// Offline contract for `search_web` and `fetch_url`.
class SearchFilterContract {
  const SearchFilterContract();

  static const int maxRedirects = 5;
  static const int pageSize = 10000;

  /// Merges batches in query order and keeps the first qualifying result for
  /// each normalized source URL. Fragments are ignored and queries preserved.
  /// Time bounds apply to the source timestamp and are inclusive.
  List<WebSearchResult> merge(
    Iterable<Iterable<WebSearchResult>> batches, {
    DateTime? from,
    DateTime? through,
  }) {
    if (from != null && through != null && from.isAfter(through)) {
      throw ArgumentError('search time bounds must be in order');
    }
    final results = <Uri, WebSearchResult>{};
    for (final result in batches.expand((batch) => batch)) {
      if (!_isWebUrl(result.sourceUrl) ||
          result.title.trim().isEmpty ||
          result.text.trim().isEmpty ||
          (from != null && result.timestamp.isBefore(from)) ||
          (through != null && result.timestamp.isAfter(through))) {
        continue;
      }
      results.putIfAbsent(_urlKey(result.sourceUrl), () => result);
    }
    return List.unmodifiable(results.values);
  }

  /// Validates one fetch hop. [previousUrls] lists the previously admitted
  /// hops in order. A relative redirect resolves against the last hop.
  /// For a hostname, supply all DNS answers for the resolved target in
  /// [resolvedAddresses]. IP literals are checked directly.
  /// Connections must use an admitted address without resolving it again.
  WebFetchAdmission validateFetch(
    Uri url, {
    List<Uri> previousUrls = const [],
    List<InternetAddress> resolvedAddresses = const [],
  }) {
    final target = previousUrls.isEmpty
        ? url
        : previousUrls.last.resolveUri(url);
    final reasons = <String>[];
    if (previousUrls.length > maxRedirects) {
      reasons.add('redirect limit exceeded');
    }
    if (previousUrls.map(_urlKey).contains(_urlKey(target))) {
      reasons.add('redirect loop');
    }

    var addresses = <InternetAddress>[];
    if (!_isWebUrl(target)) {
      reasons.add('absolute HTTP(S) URL without credentials required');
    } else {
      final host = _withoutTrailingDot(target.host);
      final literal = InternetAddress.tryParse(host);
      if (literal != null) {
        addresses = [literal];
      } else if (!_dnsHost.hasMatch(host) ||
          host.endsWith('.localhost') ||
          host.endsWith('.local') ||
          host.endsWith('.internal')) {
        reasons.add('public hostname required');
      } else {
        addresses = resolvedAddresses;
      }
      if (addresses.isEmpty || !addresses.every(_isPublicAddress)) {
        reasons.add('public connection addresses required');
      }
    }

    return WebFetchAdmission(
      target.removeFragment(),
      reasons.isEmpty ? List.unmodifiable(addresses) : const [],
      List.unmodifiable(reasons),
    );
  }

  /// Returns a slice of one already extracted document snapshot. Offsets and
  /// lengths use UTF-16 code units, with an exclusive reference end. Pass the
  /// final URL after redirects and reuse the snapshot when continuing a read.
  WebDocumentArtifact documentPage({
    required Uri sourceUrl,
    required DateTime fetchedAt,
    required String title,
    required WebDocumentFormat format,
    required String content,
    int startIndex = 0,
  }) {
    if (!_isWebUrl(sourceUrl)) {
      throw ArgumentError.value(sourceUrl, 'sourceUrl', 'invalid document URL');
    }
    RangeError.checkValueInInterval(
      startIndex,
      0,
      content.length,
      'startIndex',
    );
    if (_splitsSurrogatePair(content, startIndex)) {
      throw ArgumentError.value(startIndex, 'startIndex', 'splits a character');
    }

    var end = startIndex + pageSize;
    if (end > content.length) end = content.length;
    if (_splitsSurrogatePair(content, end)) end--;
    return WebDocumentArtifact(
      title: title,
      format: format,
      content: content.substring(startIndex, end),
      reference: WebDocumentReference(
        sourceUrl: sourceUrl,
        fetchedAt: fetchedAt,
        startIndex: startIndex,
        endIndex: end,
      ),
      totalLength: content.length,
      nextStartIndex: end < content.length ? end : null,
    );
  }

  static final _dnsHost = RegExp(
    r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+'
    r'[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$',
  );

  static bool _isWebUrl(Uri url) =>
      (url.scheme == 'http' || url.scheme == 'https') &&
      url.host.isNotEmpty &&
      !url.authority.contains('@') &&
      url.port > 0 &&
      url.port <= 65535;

  static Uri _urlKey(Uri url) {
    final key = url.removeFragment().normalizePath();
    if (!key.hasAuthority) return key;
    return key.replace(
      host: _withoutTrailingDot(key.host),
      path: key.path.isEmpty ? '/' : key.path,
    );
  }

  static String _withoutTrailingDot(String host) =>
      host.endsWith('.') ? host.substring(0, host.length - 1) : host;

  static bool _isPublicAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) {
      // Exclude private and special-purpose address blocks.
      return switch (bytes) {
        [0 || 10 || 127, _, _, _] => false,
        [100, >= 64 && <= 127, _, _] => false,
        [169, 254, _, _] => false,
        [172, >= 16 && <= 31, _, _] => false,
        [192, 0, 0 || 2, _] => false,
        [192, 88, 99, _] => false,
        [192, 168, _, _] => false,
        [198, 18 || 19, _, _] => false,
        [198, 51, 100, _] => false,
        [203, 0, 113, _] => false,
        [< 224, _, _, _] => true,
        _ => false,
      };
    }

    // Admit native global unicast IPv6 outside special-purpose blocks.
    return switch (bytes) {
      [0x20, 0x01, <= 0x01, ...] => false,
      [0x20, 0x01, 0x0d, 0xb8, ...] => false,
      [0x20, 0x02, ...] => false,
      [0x3f, 0xff, <= 0x0f, ...] => false,
      [>= 0x20 && <= 0x3f, ...] => true,
      _ => false,
    };
  }

  static bool _splitsSurrogatePair(String content, int index) {
    if (index == 0 || index == content.length) return false;
    final before = content.codeUnitAt(index - 1);
    final after = content.codeUnitAt(index);
    return before >= 0xD800 &&
        before <= 0xDBFF &&
        after >= 0xDC00 &&
        after <= 0xDFFF;
  }
}
