// Bounded artifact stream storage with digest verification and atomic publish.
// This component does not modify the W03 artifact URI or manifest schema.
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'artifact_manifest.dart';

final class ArtifactStore {
  ArtifactStore(this.root, {this.maxBytes = 512 * 1024 * 1024}) {
    if (maxBytes < 1) throw ArgumentError('Invalid artifact byte budget');
  }

  final Directory root;
  final int maxBytes;

  File _destination(ArtifactManifest manifest) =>
      File('${root.path}/${manifest.id}.artifact');

  /// Store bytes to a sibling staging path, verify, then rename into place.
  /// Existing IDs are never silently overwritten.
  Future<File> publish(
    ArtifactManifest manifest,
    Stream<List<int>> bytes,
  ) async {
    if (manifest.byteLength > maxBytes) {
      throw ArgumentError('Artifact exceeds configured size limit');
    }
    if (!await root.exists()) throw StateError('Missing artifact directory');
    final target = _destination(manifest);
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Artifact already exists');
    }
    final staging = await root.createTemp('.artifact-stage-');
    final scratch = File('${staging.path}/payload');
    IOSink? sink;
    try {
      sink = scratch.openWrite();
      var length = 0;
      await for (final chunk in bytes) {
        length += chunk.length;
        if (length > manifest.byteLength || length > maxBytes) {
          throw const FormatException('Artifact input exceeds expected length');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (length != manifest.byteLength ||
          (await sha256.bind(scratch.openRead()).first).toString() !=
              manifest.sha256Hex) {
        throw const FormatException('Artifact checksum or length mismatch');
      }
      if (await FileSystemEntity.type(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Artifact already published');
      }
      return await scratch.rename(target.path);
    } finally {
      if (sink != null) await sink.close();
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// Verify integrity before handing out the stream.
  /// Consumers must not mutate the managed file during reads.
  Future<Stream<List<int>>> openVerified(ArtifactManifest manifest) async {
    final file = _destination(manifest);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Artifact not found or is a symlink');
    }
    if (await file.length() != manifest.byteLength ||
        (await sha256.bind(file.openRead()).first).toString() !=
            manifest.sha256Hex) {
      throw const FormatException('Artifact content does not match manifest');
    }
    return file.openRead();
  }
}
