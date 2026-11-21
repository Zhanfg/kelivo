import 'dart:io';

import 'package:Kelivo/core/services/tools/search_filter_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = SearchFilterContract();
  final begin = DateTime.utc(2026, 11, 1);
  final end = DateTime.utc(2026, 11, 21);
  final source = Uri.parse('https://reports.example/brief');
  final publicAddress = InternetAddress('93.184.216.34');

  WebSearchResult result({
    Uri? url,
    DateTime? timestamp,
    String title = 'Research brief',
    String text = 'A summary of the latest research.',
  }) => WebSearchResult(
    title: title,
    sourceUrl: url ?? source,
    text: text,
    timestamp: timestamp ?? begin,
  );

  test('batch merge keeps order, original source URL and timestamp', () {
    final original = result(
      url: Uri.parse('https://REPORTS.example.:443/./brief#summary'),
    );
    final distinct = result(url: source.replace(query: 'edition=2'));
    final merged = policy.merge([
      [original],
      [result(timestamp: end), distinct],
    ]);
    expect(merged, [original, distinct]);
    expect(merged.first.sourceUrl, original.sourceUrl);
    expect(merged.first.timestamp, begin);
  });

  test('inclusive time bounds are applied before de-duplication', () {
    final atStart = result();
    final atEnd = result(
      url: source.replace(path: '/update'),
      timestamp: end,
    );
    final stale = result(timestamp: begin.subtract(const Duration(seconds: 1)));
    final future = result(timestamp: end.add(const Duration(seconds: 1)));
    expect(
      policy.merge([
        [stale, future],
        [atStart, atEnd],
      ], from: begin, through: end),
      [atStart, atEnd],
    );
    expect(
      () => policy.merge([], from: end, through: begin),
      throwsArgumentError,
    );
  });

  test('invalid sources and blank result metadata do not hide valid hits', () {
    final valid = result();
    expect(
      policy.merge([
        [
          result(url: Uri.parse('/relative')),
          result(url: Uri.parse('ftp://reports.example/brief')),
          result(url: source.replace(userInfo: 'reader')),
          result(title: ' '),
          result(text: '\n'),
        ],
        [valid],
      ]),
      [valid],
    );
  });

  test('a hostname requires public addresses for every DNS answer', () {
    final ipv6 = InternetAddress('2606:4700::1111');
    final admitted = policy.validateFetch(
      source,
      resolvedAddresses: [publicAddress, ipv6],
    );
    expect(admitted.allowed, isTrue);
    expect(admitted.url, source);
    expect(admitted.addresses, [publicAddress, ipv6]);
    expect(policy.validateFetch(source).allowed, isFalse);

    final denied = policy.validateFetch(
      source,
      resolvedAddresses: [publicAddress, InternetAddress('10.0.0.1')],
    );
    expect(denied.allowed, isFalse);
    expect(denied.addresses, isEmpty);
    expect(denied.reasons, contains('public connection addresses required'));
  });

  test('unsafe URLs and non-public IP literals are denied', () {
    for (final url in [
      'file:///document.pdf',
      'https://reader@reports.example/brief',
      'http://localhost/brief',
      'http://127.0.0.1/brief',
      'http://169.254.169.254/brief',
      'http://100.64.0.1/brief',
      'http://224.0.0.1/brief',
      'http://[::1]/brief',
      'http://[fc00::1]/brief',
      'http://[fe80::1]/brief',
      'http://[::ffff:127.0.0.1]/brief',
    ]) {
      expect(
        policy
            .validateFetch(Uri.parse(url), resolvedAddresses: [publicAddress])
            .allowed,
        isFalse,
        reason: url,
      );
    }
    final literal = policy.validateFetch(
      Uri.parse('https://${publicAddress.address}/brief'),
    );
    expect(literal.addresses.single.address, publicAddress.address);
  });

  test('redirects resolve relative URLs and revalidate each target', () {
    final redirect = policy.validateFetch(
      Uri.parse('archive/brief.pdf#section'),
      previousUrls: [source],
      resolvedAddresses: [publicAddress],
    );
    expect(redirect.allowed, isTrue);
    expect(
      redirect.url,
      Uri.parse('https://reports.example/archive/brief.pdf'),
    );

    final denied = policy.validateFetch(
      Uri.parse('//files.example/brief.pdf'),
      previousUrls: [source, redirect.url],
      resolvedAddresses: [InternetAddress('192.168.1.2')],
    );
    expect(denied.allowed, isFalse);
    expect(denied.reasons, contains('public connection addresses required'));
  });

  test('redirect loops and chains beyond the hop limit are denied', () {
    final loop = policy.validateFetch(
      Uri.parse('#summary'),
      previousUrls: [source],
      resolvedAddresses: [publicAddress],
    );
    expect(loop.reasons, contains('redirect loop'));

    final history = List.generate(
      SearchFilterContract.maxRedirects,
      (index) => source.replace(path: '/redirect-$index'),
    );
    expect(
      policy
          .validateFetch(
            source,
            previousUrls: history,
            resolvedAddresses: [publicAddress],
          )
          .allowed,
      isTrue,
    );
    final overLimit = policy.validateFetch(
      source,
      previousUrls: [...history, source.replace(path: '/last')],
      resolvedAddresses: [publicAddress],
    );
    expect(overLimit.reasons, contains('redirect limit exceeded'));
  });

  test('PDF pages retain references and a Unicode-safe continuation', () {
    final url = source.replace(path: '/brief.pdf');
    final prefix = List.filled(SearchFilterContract.pageSize - 1, 'a').join();
    final content = '$prefix📄end';

    WebDocumentArtifact page([int startIndex = 0]) => policy.documentPage(
      sourceUrl: url,
      fetchedAt: end,
      title: 'Research brief',
      format: WebDocumentFormat.pdf,
      content: content,
      startIndex: startIndex,
    );

    final first = page();
    expect(first.format, WebDocumentFormat.pdf);
    expect(first.title, 'Research brief');
    expect(first.content, prefix);
    expect(first.totalLength, content.length);
    expect(first.reference.sourceUrl, url);
    expect(first.reference.fetchedAt, end);
    expect(first.reference.startIndex, 0);
    expect(first.reference.endIndex, prefix.length);
    expect(first.nextStartIndex, first.reference.endIndex);

    final next = page(first.nextStartIndex!);
    expect(first.content + next.content, content);
    expect(next.reference.sourceUrl, first.reference.sourceUrl);
    expect(next.reference.fetchedAt, first.reference.fetchedAt);
    expect(next.reference.startIndex, first.reference.endIndex);
    expect(next.reference.endIndex, content.length);
    expect(next.nextStartIndex, isNull);
    expect(() => page(prefix.length + 1), throwsArgumentError);
    expect(() => page(content.length + 1), throwsRangeError);
  });

  test('structured content is returned as a referenceable artifact', () {
    const content = '{"items":[{"title":"Research brief"}]}';
    final artifact = policy.documentPage(
      sourceUrl: source,
      fetchedAt: begin,
      title: 'Research records',
      format: WebDocumentFormat.structured,
      content: content,
    );
    expect(artifact.format, WebDocumentFormat.structured);
    expect(artifact.content, content);
    expect(artifact.reference.sourceUrl, source);
    expect(artifact.reference.fetchedAt, begin);
    expect(artifact.reference.endIndex, content.length);
    expect(artifact.nextStartIndex, isNull);
  });
}
