import 'package:Kelivo/core/services/tools/workspace_edit_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const policy = WorkspaceEditContract();

  Future<WorkspaceEditPath> resolve(String path) => policy.resolvePath(
    path,
    workspaceRoot: '/workspace',
    resolveRealPath: (path) => path,
    pathContext: p.posix,
  );

  test(
    'fresh edit yields a patch with workspace headers and context',
    () async {
      final target = await resolve('drafts/../notes.txt');
      const before = 'first\nold\nlast\n';
      const after = 'first\nnew\nlast\n';
      final base = policy.contentHash(before);
      final preview = policy.preview(
        target: target,
        expectedHash: base,
        currentContent: before,
        proposedContent: after,
      );

      expect(target.absolutePath, '/workspace/notes.txt');
      expect(preview.hasConflict, isFalse);
      expect(preview.currentHash, base);
      expect(preview.patch, '''
--- a/notes.txt
+++ b/notes.txt
@@ -1,3 +1,3 @@
 first
-old
+new
 last
''');
      final write = preview.write!;
      expect(write.target, target);
      expect(write.expectedHash, base);
      expect(write.originalContent, before);
      expect(write.replacementContent, after);
    },
  );

  test('separated changes yield separate correctly numbered hunks', () async {
    final target = await resolve('/workspace/docs/notes.txt');
    const middle = '1\n2\n3\n4\n5\n6\n7\n8\n';
    const before = 'old first\n${middle}old last\n';
    final preview = policy.preview(
      target: target,
      expectedHash: policy.contentHash(before),
      currentContent: before,
      proposedContent: 'new first\n${middle}new last\n',
    );
    expect(preview.patch, '''
--- a/docs/notes.txt
+++ b/docs/notes.txt
@@ -1,4 +1,4 @@
-old first
+new first
 1
 2
 3
@@ -7,4 +7,4 @@
 6
 7
 8
-old last
+new last
''');
  });

  test('patch preserves CRLF and marks an unterminated line', () async {
    final target = await resolve('notes.txt');
    const before = 'keep\r\nlast';
    final preview = policy.preview(
      target: target,
      expectedHash: policy.contentHash(before),
      currentContent: before,
      proposedContent: 'keep\r\nlast\n',
    );
    expect(
      preview.patch,
      '--- a/notes.txt\n+++ b/notes.txt\n@@ -1,2 +1,2 @@\n'
      ' keep\r\n-last\n\\ No newline at end of file\n+last\n',
    );
  });

  test('an edit of an empty file uses a zero-length range', () async {
    final preview = policy.preview(
      target: await resolve('empty.txt'),
      expectedHash: policy.contentHash(''),
      currentContent: '',
      proposedContent: 'new\n',
    );
    expect(preview.patch, '''
--- a/empty.txt
+++ b/empty.txt
@@ -0,0 +1,1 @@
+new
''');
  });

  test('the content fingerprint is SHA-256 of exact UTF-8 text', () {
    expect(
      policy.contentHash('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(policy.contentHash('abc\r\n'), isNot(policy.contentHash('abc\n')));
  });

  test('stale and deleted files provide no patch or write plan', () async {
    final target = await resolve('notes.txt');
    final base = policy.contentHash('base\n');
    for (final current in ['concurrent edit\n', null]) {
      final preview = policy.preview(
        target: target,
        expectedHash: base,
        currentContent: current,
        proposedContent: 'concurrent edit\n',
      );
      expect(preview.hasConflict, isTrue);
      expect(
        preview.currentHash,
        current == null ? null : policy.contentHash(current),
      );
      expect(preview.patch, isNull);
      expect(preview.write, isNull);
    }
  });

  test('a fresh no-op needs no write plan', () async {
    final preview = policy.preview(
      target: await resolve('notes.txt'),
      expectedHash: policy.contentHash('same\n'),
      currentContent: 'same\n',
      proposedContent: 'same\n',
    );
    expect(preview.hasConflict, isFalse);
    expect(preview.patch, isEmpty);
    expect(preview.write, isNull);
  });

  test('paths cannot climb above the root or use a sibling prefix', () async {
    for (final path in [
      '../outside.txt',
      'nested/../../outside.txt',
      '../workspace/notes.txt',
      '/workspace/../workspace/notes.txt',
      '/workspace-other/notes.txt',
      '/outside/notes.txt',
      'bad\u0000path',
    ]) {
      await expectLater(resolve(path), throwsArgumentError, reason: path);
    }
  });

  test('canonical paths are checked after resolving links', () async {
    const realPaths = {
      '/workspace': '/real/workspace',
      '/workspace/inside.txt': '/real/workspace/notes.txt',
      '/workspace/outside.txt': '/real/workspace-other/notes.txt',
    };
    Future<WorkspaceEditPath> resolveLink(String path) => policy.resolvePath(
      path,
      workspaceRoot: '/workspace',
      resolveRealPath: (path) async => realPaths[path]!,
      pathContext: p.posix,
    );

    final inside = await resolveLink('inside.txt');
    expect(inside.absolutePath, '/real/workspace/notes.txt');
    expect(inside.relativePath, 'notes.txt');
    await expectLater(resolveLink('outside.txt'), throwsArgumentError);
  });

  test(
    'Windows drive paths are confined and use portable patch names',
    () async {
      Future<WorkspaceEditPath> resolveWindows(String path) =>
          policy.resolvePath(
            path,
            workspaceRoot: r'C:\workspace',
            resolveRealPath: (path) => path,
            pathContext: p.windows,
          );

      final target = await resolveWindows(r'C:\workspace\docs\notes.txt');
      expect(target.relativePath, 'docs/notes.txt');
      await expectLater(
        resolveWindows(r'D:\workspace\notes.txt'),
        throwsArgumentError,
      );
      await expectLater(
        resolveWindows(r'..\..\notes.txt'),
        throwsArgumentError,
      );
      await expectLater(resolveWindows(r'C:notes.txt'), throwsArgumentError);
    },
  );

  test(
    'directory pages carry page size and an optional continuation token',
    () async {
      final directory = await resolve('.');
      expect(directory.absolutePath, '/workspace');
      final firstRequest = WorkspaceDirectoryPageRequest(
        directory: directory,
        pageSize: 2,
      );
      final firstPage = WorkspaceDirectoryPage(
        entries: ['a.txt', 'b.txt'],
        nextContinuationToken: 'snapshot-cursor',
      );
      final nextRequest = WorkspaceDirectoryPageRequest(
        directory: directory,
        pageSize: firstRequest.pageSize,
        continuationToken: firstPage.nextContinuationToken,
      );
      final lastPage = WorkspaceDirectoryPage(entries: ['c.txt']);

      expect(firstRequest.continuationToken, isNull);
      expect(firstPage.entries, ['a.txt', 'b.txt']);
      expect(nextRequest.directory, firstRequest.directory);
      expect(nextRequest.pageSize, 2);
      expect(nextRequest.continuationToken, 'snapshot-cursor');
      expect(lastPage.nextContinuationToken, isNull);
      expect(
        () => WorkspaceDirectoryPageRequest(directory: directory, pageSize: 0),
        throwsArgumentError,
      );
    },
  );
}
