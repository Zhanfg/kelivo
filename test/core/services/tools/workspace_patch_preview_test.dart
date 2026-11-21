import 'package:Kelivo/core/services/tools/workspace_patch_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const planner = WorkspacePatchPlanner();
  const diff = '@@ -1,2 +1,2 @@\n first\n-old\n+new';

  test('unified diff produces a read-only preview', () {
    final result = planner.preview(
      relativePath: 'src/example.dart',
      original: 'first\nold\nlast\n',
      unifiedDiff: diff,
    );
    expect(result.before, 'first\nold\nlast\n');
    expect(result.after, 'first\nnew\nlast\n');
    expect(result.unifiedDiff, diff);
  });

  test('mismatched original context is a conflict', () {
    expect(
      () => planner.preview(
        relativePath: 'src/example.dart',
        original: 'first\nchanged\nlast\n',
        unifiedDiff: diff,
      ),
      throwsA(isA<WorkspacePatchConflict>()),
    );
  });

  test('path traversal and Windows absolute paths are denied', () {
    for (final path in [
      '../secret',
      './src',
      '/etc/passwd',
      'C:\\secret',
      'src//file',
      'src/..\\secret',
    ]) {
      expect(
        () => planner.verifyPath(path),
        throwsA(isA<WorkspacePatchConflict>()),
      );
    }
  });

  test('multi-hunk and malformed hunk counts reject', () {
    expect(
      () => planner.preview(
        relativePath: 'a.txt',
        original: 'first\nold\n',
        unifiedDiff: '$diff\n@@ -4 +4 @@\n-x\n+y',
      ),
      throwsA(isA<WorkspacePatchConflict>()),
    );
    expect(
      () => planner.preview(
        relativePath: 'a.txt',
        original: 'first\nold\n',
        unifiedDiff: '@@ -1,3 +1,2 @@\n first\n-old\n+new',
      ),
      throwsA(isA<WorkspacePatchConflict>()),
    );
  });

  test('batch is all-or-nothing at the planning stage', () {
    expect(
      () => planner.planBatch([
        () => planner.preview(
          relativePath: 'good.txt',
          original: 'first\nold',
          unifiedDiff: diff,
        ),
        () => planner.preview(
          relativePath: '../bad',
          original: 'first\nold',
          unifiedDiff: diff,
        ),
      ]),
      throwsA(isA<WorkspacePatchConflict>()),
    );
  });
}
