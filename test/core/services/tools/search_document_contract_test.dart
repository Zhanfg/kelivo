import 'package:Kelivo/core/services/tools/search_document_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const contract = SearchDocumentContract();
  final now = DateTime.utc(2026, 11, 21);
  SearchDocumentHit hit(
    String url, {
    String content = 'abcdefghij',
    SearchDocumentKind kind = SearchDocumentKind.html,
    DateTime? published,
  }) => SearchDocumentHit(
    url: Uri.parse(url),
    title: 'Example',
    fetchedAtUtc: now,
    publishedAtUtc: published ?? now,
    content: content,
    kind: kind,
  );

  test('merge multiple queries preserves source URL and date', () {
    final a = hit('https://example.org/a');
    final b = hit('https://example.org/b');
    final results = contract.merge([
      [a],
      [a, b],
    ], notBeforeUtc: now);
    expect(results.length, 2);
    expect(results.first.url.scheme, 'https');
    expect(results.first.publishedAtUtc, now);
  });

  test('untrusted schemes, missing dates and older items are excluded', () {
    final results = contract.merge([
      [
        hit('file:///etc/passwd'),
        hit(
          'https://example.org/old',
          published: now.subtract(const Duration(days: 40)),
        ),
        hit('https://example.org/new'),
      ],
    ], notBeforeUtc: now.subtract(const Duration(days: 10)));
    expect(results.map((result) => result.url.toString()), [
      'https://example.org/new',
    ]);
  });

  test('PDF and structured content keep independent citations per chunk', () {
    final pages = contract.paginate(
      hit('https://example.org/report.pdf', kind: SearchDocumentKind.pdf),
      chars: 4,
    );
    expect(pages.length, 3);
    expect(pages.map((p) => p.content).join(), 'abcdefghij');
    expect(pages[0].citation, contains('chunk-1'));
    expect(pages[2].chunkCount, 3);
    final structured = contract.paginate(
      hit('https://example.org/data.json', kind: SearchDocumentKind.structured),
    );
    expect(structured.single.kind, SearchDocumentKind.structured);
  });

  test('empty document retains a citable page', () {
    final pages = contract.paginate(
      hit('https://example.org/empty', content: ''),
    );
    expect(pages.length, 1);
    expect(pages.single.content, isEmpty);
  });

  test('invalid pagination sizes and provenance fail closed', () {
    expect(
      () => contract.paginate(hit('https://example.org'), chars: 0),
      throwsArgumentError,
    );
    expect(
      () => contract.paginate(hit('http://127.0.0.1')),
      throwsArgumentError,
    );
    expect(() => contract.merge([], maxResults: 1001), throwsArgumentError);
  });
}
