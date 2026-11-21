/// Conservative in-memory unified-diff preview. Never writes to disk.
class WorkspacePatchConflict implements Exception {
  const WorkspacePatchConflict(this.reason);
  final String reason;
  @override
  String toString() => 'WorkspacePatchConflict: $reason';
}

class WorkspacePatchPreview {
  const WorkspacePatchPreview({
    required this.relativePath,
    required this.before,
    required this.after,
    required this.unifiedDiff,
  });
  final String relativePath;
  final String before;
  final String after;
  final String unifiedDiff;
}

class WorkspacePatchPlanner {
  const WorkspacePatchPlanner();

  void verifyPath(String relativePath) {
    final path = relativePath.replaceAll('\\', '/');
    if (relativePath.isEmpty ||
        path.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(path) ||
        path
            .split('/')
            .any(
              (segment) => segment.isEmpty || segment == '.' || segment == '..',
            ) ||
        relativePath.contains('\\') ||
        relativePath.contains('\u0000')) {
      throw const WorkspacePatchConflict('unsafe workspace-relative path');
    }
  }

  /// Only one hunk is accepted; unsupported metadata and multi-hunks fail
  /// instead of silently overwriting content. Real writes need a separate
  /// validated atomic file service and symlink containment checks.
  WorkspacePatchPreview preview({
    required String relativePath,
    required String original,
    required String unifiedDiff,
  }) {
    verifyPath(relativePath);
    final lines = unifiedDiff.replaceAll('\r\n', '\n').split('\n');
    final headers = lines.where((line) => line.startsWith('@@ ')).toList();
    if (headers.length != 1) {
      throw const WorkspacePatchConflict('exactly one hunk required');
    }
    final match = RegExp(
      r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
    ).firstMatch(headers.single);
    if (match == null) {
      throw const WorkspacePatchConflict('invalid unified diff header');
    }
    final oldLine = int.parse(match.group(1)!);
    final oldCount = int.parse(match.group(2) ?? '1');
    final newCount = int.parse(match.group(4) ?? '1');
    if (oldLine < 1 || oldCount < 0 || newCount < 0) {
      throw const WorkspacePatchConflict('invalid hunk bounds');
    }
    final headerIndex = lines.indexOf(headers.single);
    if (headerIndex > 2 ||
        lines
            .take(headerIndex)
            .any(
              (line) => !(line.startsWith('--- ') || line.startsWith('+++ ')),
            )) {
      throw const WorkspacePatchConflict('unsupported patch metadata');
    }
    final body = lines.skip(headerIndex + 1).toList();
    if (body.isNotEmpty && body.last.isEmpty) body.removeLast();
    final removed = <String>[];
    final added = <String>[];
    for (final line in body) {
      if (line.isEmpty) {
        throw const WorkspacePatchConflict('unprefixed patch line');
      }
      if (line.startsWith(' ') || line.startsWith('-')) {
        removed.add(line.substring(1));
      }
      if (line.startsWith(' ') || line.startsWith('+')) {
        added.add(line.substring(1));
      }
      if (!' +-'.contains(line[0])) {
        throw const WorkspacePatchConflict('unsupported patch command');
      }
    }
    if (removed.length != oldCount || added.length != newCount) {
      throw const WorkspacePatchConflict('hunk line count mismatch');
    }
    final hasFinalNewline = original.endsWith('\n');
    final source = original.isEmpty ? <String>[] : original.split('\n');
    if (hasFinalNewline) source.removeLast();
    final offset = oldLine - 1;
    if (offset + oldCount > source.length ||
        source.skip(offset).take(oldCount).join('\n') != removed.join('\n')) {
      throw const WorkspacePatchConflict('original context mismatch');
    }
    final updated = <String>[
      ...source.take(offset),
      ...added,
      ...source.skip(offset + oldCount),
    ];
    final content = updated.join('\n') + (hasFinalNewline ? '\n' : '');
    return WorkspacePatchPreview(
      relativePath: relativePath,
      before: original,
      after: content,
      unifiedDiff: unifiedDiff,
    );
  }

  List<WorkspacePatchPreview> planBatch(
    Iterable<WorkspacePatchPreview Function()> operations,
  ) {
    // No I/O occurs. If any preview conflicts, the entire plan fails.
    return List.unmodifiable(
      operations.map((operation) => operation()).toList(),
    );
  }
}
