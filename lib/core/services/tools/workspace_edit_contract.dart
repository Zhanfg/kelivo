import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../workspace/unified_diff.dart';

class WorkspaceEditPath {
  const WorkspaceEditPath._(this.absolutePath, this.relativePath);

  /// Canonical target to use for file operations.
  final String absolutePath;

  /// Workspace-relative name with forward slashes.
  final String relativePath;
}

class WorkspaceEditPreview {
  const WorkspaceEditPreview._(this.currentHash, {this.patch, this.write});

  /// The current UTF-8 content hash, or null if the file no longer exists.
  final String? currentHash;

  /// A unified patch, empty for a no-op and null for a stale base.
  final String? patch;

  final WorkspaceAtomicWrite? write;

  bool get hasConflict => patch == null;
}

/// A fresh edit's inputs for atomic publication.
///
/// Stage the replacement in an exclusive temporary file in the canonical
/// target's directory and flush it before renaming it over the target. Recheck
/// the confined target and [expectedHash] immediately before rename, keeping
/// both stable through publication. A mismatch aborts publication.
///
/// Retain [originalContent] until the operation completes. On failure before
/// rename, discard the temporary file and leave the target intact. If a
/// published replacement must be rolled back, restore the original through
/// the same atomic rename while the target is still reserved for this edit.
class WorkspaceAtomicWrite {
  const WorkspaceAtomicWrite._({
    required this.target,
    required this.expectedHash,
    required this.originalContent,
    required this.replacementContent,
  });

  final WorkspaceEditPath target;
  final String expectedHash;
  final String originalContent;
  final String replacementContent;
}

class WorkspaceDirectoryPageRequest {
  WorkspaceDirectoryPageRequest({
    required this.directory,
    required this.pageSize,
    this.continuationToken,
  }) {
    if (pageSize < 1) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be positive');
    }
  }

  final WorkspaceEditPath directory;
  final int pageSize;

  /// Null starts a listing. Reuse the previous page's opaque token to continue
  /// the same directory snapshot in the same order.
  final String? continuationToken;
}

class WorkspaceDirectoryPage<T> {
  WorkspaceDirectoryPage({required List<T> entries, this.nextContinuationToken})
    : entries = List.unmodifiable(entries);

  /// Up to the requested page size of entries in stable snapshot order.
  final List<T> entries;

  /// Null means the snapshot is exhausted, including an empty directory.
  final String? nextContinuationToken;
}

/// Offline contract for previewing a workspace edit before publication.
class WorkspaceEditContract {
  const WorkspaceEditContract();

  /// Resolve before reading a snapshot. The caller supplies a real-path
  /// resolver that follows symlinks and returns a canonical absolute path.
  /// The lexical request and the resolved target must both be confined.
  Future<WorkspaceEditPath> resolvePath(
    String path, {
    required String workspaceRoot,
    required FutureOr<String> Function(String path) resolveRealPath,
    p.Context? pathContext,
  }) async {
    final paths = pathContext ?? p.context;
    bool isAbsolute(String value) =>
        paths.isAbsolute(value) &&
        !paths.isRootRelative(value) &&
        !value.contains('\u0000');

    if (!isAbsolute(workspaceRoot)) {
      throw ArgumentError.value(
        workspaceRoot,
        'workspaceRoot',
        'must be absolute',
      );
    }
    final root = paths.normalize(workspaceRoot);
    final outside = ArgumentError.value(path, 'path', 'outside workspace root');
    if (path.isEmpty || path.contains('\u0000') || paths.isRootRelative(path)) {
      throw outside;
    }

    final parts = paths.split(path).where((part) => part != '.').toList();
    var first = 0;
    if (paths.isAbsolute(path)) {
      first = paths.split(root).length;
      if (!paths.equals(root, paths.joinAll(parts.take(first)))) throw outside;
    }
    var depth = 0;
    for (final part in parts.skip(first)) {
      if (part == '..') {
        if (depth == 0) throw outside;
        depth--;
      } else {
        if (paths.style == p.Style.windows &&
            _ambiguousWindowsName.hasMatch(part)) {
          throw outside;
        }
        depth++;
      }
    }

    final lexicalTarget = paths.normalize(paths.join(root, path));
    if (!paths.equals(root, lexicalTarget) &&
        !paths.isWithin(root, lexicalTarget)) {
      throw outside;
    }
    final resolvedRoot = await resolveRealPath(root);
    final resolvedTarget = await resolveRealPath(lexicalTarget);
    if (!isAbsolute(resolvedRoot) || !isAbsolute(resolvedTarget)) throw outside;
    final realRoot = paths.normalize(resolvedRoot);
    final realTarget = paths.normalize(resolvedTarget);
    if (!paths.equals(realRoot, realTarget) &&
        !paths.isWithin(realRoot, realTarget)) {
      throw outside;
    }
    final relative = paths.relative(realTarget, from: realRoot);
    return WorkspaceEditPath._(realTarget, paths.split(relative).join('/'));
  }

  /// SHA-256 of the exact text encoded as UTF-8, including line endings.
  String contentHash(String content) =>
      sha256.convert(utf8.encode(content)).toString();

  WorkspaceEditPreview preview({
    required WorkspaceEditPath target,
    required String expectedHash,
    required String? currentContent,
    required String proposedContent,
  }) {
    if (target.relativePath == '.') {
      throw ArgumentError.value(
        target.absolutePath,
        'target',
        'must be a file',
      );
    }
    if (currentContent == null) return const WorkspaceEditPreview._(null);
    final currentHash = contentHash(currentContent);
    if (currentHash != expectedHash) return WorkspaceEditPreview._(currentHash);
    if (currentContent == proposedContent) {
      return WorkspaceEditPreview._(currentHash, patch: '');
    }
    return WorkspaceEditPreview._(
      currentHash,
      patch: _patch(target.relativePath, currentContent, proposedContent),
      write: WorkspaceAtomicWrite._(
        target: target,
        expectedHash: expectedHash,
        originalContent: currentContent,
        replacementContent: proposedContent,
      ),
    );
  }

  static final _ambiguousWindowsName = RegExp(r'[:]|[. ]$');
  static final _lines = RegExp(r'[^\n]*\n|[^\n]+');
  static final _quotedPathChars = RegExp(r'["\\\x00-\x1f\x7f]');

  static String _patch(String path, String before, String after) {
    final lineIds = <String, int>{};
    final lines = <String>[];

    // The shared renderer compares logical lines. Use IDs so CRLF and
    // unterminated lines retain their exact spelling through the diff.
    String encodeLines(String text) {
      final encoded = StringBuffer();
      for (final match in _lines.allMatches(text)) {
        final line = match[0]!;
        final id = lineIds.putIfAbsent(line, () {
          lines.add(line);
          return lines.length - 1;
        });
        encoded.writeln(id);
      }
      return encoded.toString();
    }

    final oldLines = encodeLines(before);
    final newLines = encodeLines(after);
    final diff = UnifiedDiff.compute(
      oldLines,
      newLines,
      maxChars: 64 * (oldLines.length + newLines.length + 1),
    );
    final patch = StringBuffer()
      ..writeln('--- ${_quotePath('a/$path')}')
      ..writeln('+++ ${_quotePath('b/$path')}');
    for (final line in const LineSplitter().convert(diff.text).skip(2)) {
      if (line.startsWith('@@')) {
        patch.writeln(line);
        continue;
      }
      final original = lines[int.parse(line.substring(1))];
      patch
        ..write(line[0])
        ..write(original);
      if (!original.endsWith('\n')) {
        patch.write('\n\\ No newline at end of file\n');
      }
    }
    return patch.toString();
  }

  static String _quotePath(String path) {
    if (!_quotedPathChars.hasMatch(path) && !path.contains(' ')) return path;
    final escaped = path.replaceAllMapped(_quotedPathChars, (match) {
      final character = match[0]!;
      if (character == '"' || character == '\\') return '\\$character';
      final octal = character.codeUnitAt(0).toRadixString(8).padLeft(3, '0');
      return '\\$octal';
    });
    return '"$escaped"';
  }
}
