/// Pure local result normalization. It never fetches network resources.
enum SearchDocumentKind { html, pdf, structured }

class SearchDocumentHit {
  const SearchDocumentHit({
    required this.url,
    required this.title,
    required this.fetchedAtUtc,
    required this.kind,
    this.publishedAtUtc,
    this.content = '',
  });

  final Uri url;
  final String title;
  final DateTime fetchedAtUtc;
  final DateTime? publishedAtUtc;
  final SearchDocumentKind kind;
  final String content;
}

class SearchDocumentPage {
  const SearchDocumentPage({
    required this.sourceUrl,
    required this.kind,
    required this.chunkIndex,
    required this.chunkCount,
    required this.content,
    required this.citation,
  });
  final Uri sourceUrl;
  final SearchDocumentKind kind;
  final int chunkIndex;
  final int chunkCount;
  final String content;
  final String citation;
}

class SearchDocumentContract {
  const SearchDocumentContract();

  /// Applies deterministic ordering, origin deduplication and optional date filter.
  List<SearchDocumentHit> merge(
    Iterable<List<SearchDocumentHit>> batches, {
    DateTime? notBeforeUtc,
    int maxResults = 100,
  }) {
    if (maxResults < 0 || maxResults > 1000) {
      throw ArgumentError.value(maxResults, 'maxResults');
    }
    final seen = <String>{};
    final candidates = <SearchDocumentHit>[];
    for (final batch in batches) {
      for (final hit in batch) {
        if (hit.url.scheme != 'https' ||
            hit.url.host.isEmpty ||
            !hit.fetchedAtUtc.isUtc ||
            (hit.publishedAtUtc != null && !hit.publishedAtUtc!.isUtc)) {
          continue;
        }
        if (notBeforeUtc != null &&
            (hit.publishedAtUtc == null ||
                hit.publishedAtUtc!.isBefore(notBeforeUtc))) {
          continue;
        }
        final identity = hit.url.replace(fragment: '').toString();
        if (seen.add(identity)) candidates.add(hit);
      }
    }
    candidates.sort((a, b) {
      final order = b.fetchedAtUtc.compareTo(a.fetchedAtUtc);
      return order != 0 ? order : a.url.toString().compareTo(b.url.toString());
    });
    return List.unmodifiable(candidates.take(maxResults));
  }

  /// Creates citation-carrying chunks for already sanitized content.
  /// Network redirects, MIME sniffing and SSRF checks belong to the fetch layer.
  List<SearchDocumentPage> paginate(SearchDocumentHit hit, {int chars = 1000}) {
    if (chars < 1 || chars > 100000) {
      throw ArgumentError.value(chars, 'chars');
    }
    if (hit.url.scheme != 'https' || hit.url.host.isEmpty) {
      throw ArgumentError('HTTPS provenance required');
    }
    final length = hit.content.length;
    final count = length == 0 ? 1 : (length + chars - 1) ~/ chars;
    return List.unmodifiable(
      List.generate(count, (index) {
        final start = index * chars;
        final end = start + chars < length ? start + chars : length;
        return SearchDocumentPage(
          sourceUrl: hit.url,
          kind: hit.kind,
          chunkIndex: index,
          chunkCount: count,
          content: hit.content.substring(start, end),
          citation: '${hit.url}#chunk-${index + 1}',
        );
      }),
    );
  }
}
