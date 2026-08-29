import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/reference/story_reference_text_extractor.dart';

void main() {
  test('EPUB import follows package spine order and reads title', () async {
    final tempDir = await Directory.systemTemp.createTemp('kelivo_epub_test_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final archive = Archive()
      ..add(
        ArchiveFile.string('META-INF/container.xml', '''<?xml version="1.0"?>
          <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
            <rootfiles>
              <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
            </rootfiles>
          </container>'''),
      )
      ..add(
        ArchiveFile.string(
          'OEBPS/content.opf',
          '''<?xml version="1.0" encoding="UTF-8"?>
          <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:title>测试 EPUB 小说</dc:title>
            </metadata>
            <manifest>
              <item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
              <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
            </manifest>
            <spine>
              <itemref idref="c1"/>
              <itemref idref="c2"/>
            </spine>
          </package>''',
        ),
      )
      ..add(
        ArchiveFile.string(
          'OEBPS/chapter1.xhtml',
          '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>第一章</h1><p>第一章正文。</p></body></html>',
        ),
      )
      ..add(
        ArchiveFile.string(
          'OEBPS/chapter2.xhtml',
          '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>第二章</h1><p>第二章正文。</p></body></html>',
        ),
      );

    final encoded = ZipEncoder().encodeBytes(archive);
    final file = File('${tempDir.path}/novel.epub');
    await file.writeAsBytes(encoded, flush: true);

    final extracted = await const StoryReferenceTextExtractor().extract(
      path: file.path,
    );

    expect(extracted.mime, 'application/epub+zip');
    expect(extracted.suggestedTitle, '测试 EPUB 小说');
    expect(extracted.text, contains('第一章正文。'));
    expect(extracted.text, contains('第二章正文。'));
    expect(
      extracted.text.indexOf('第一章正文。'),
      lessThan(extracted.text.indexOf('第二章正文。')),
    );
  });
}
