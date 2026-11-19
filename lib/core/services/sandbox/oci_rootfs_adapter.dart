import 'dart:convert';

/// Bounded, metadata-only OCI rootfs inspection.
///
/// Does not download, decompress, unpack or replace installed rootfs content.
final class OciRootfsDescriptor {
  OciRootfsDescriptor({
    required this.mediaType,
    required this.digest,
    required this.size,
  }) {
    if (!allowedMediaTypes.contains(mediaType)) {
      throw const FormatException('Unsupported OCI media type');
    }
    if (!RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid digest');
    }
    if (size < 0 || size > maxBytes) {
      throw const FormatException('Invalid descriptor size');
    }
  }

  static const maxBytes = 8 * 1024 * 1024 * 1024;
  static const allowedMediaTypes = {
    'application/vnd.oci.image.config.v1+json',
    'application/vnd.oci.image.layer.v1.tar',
    'application/vnd.oci.image.layer.v1.tar+gzip',
    'application/vnd.oci.image.layer.v1.tar+zstd',
  };

  final String mediaType;
  final String digest;
  final int size;

  factory OciRootfsDescriptor.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid OCI descriptor');
    }
    if (raw.keys.toSet().difference({
      'mediaType',
      'digest',
      'size',
    }).isNotEmpty) {
      throw const FormatException('Unsupported descriptor metadata');
    }
    final type = raw['mediaType'];
    final digest = raw['digest'];
    final size = raw['size'];
    if (type is! String || digest is! String || size is! int) {
      throw const FormatException('Invalid descriptor fields');
    }
    return OciRootfsDescriptor(mediaType: type, digest: digest, size: size);
  }
}

final class OciRootfsManifest {
  OciRootfsManifest({
    required this.config,
    required List<OciRootfsDescriptor> layers,
  }) : layers = List.unmodifiable(layers) {
    if (layers.isEmpty || layers.length > 128) {
      throw const FormatException('Invalid layer count');
    }
    if (config.mediaType != 'application/vnd.oci.image.config.v1+json') {
      throw const FormatException('Invalid OCI config media type');
    }
    for (final layer in layers) {
      if (layer.mediaType == 'application/vnd.oci.image.config.v1+json') {
        throw const FormatException('Config cannot be an OCI layer');
      }
    }
    final total = layers.fold<int>(0, (sum, layer) => sum + layer.size);
    if (total > 16 * 1024 * 1024 * 1024) {
      throw const FormatException('Layer total exceeds budget');
    }
  }

  final OciRootfsDescriptor config;
  final List<OciRootfsDescriptor> layers;

  factory OciRootfsManifest.parse(String source) {
    if (utf8.encode(source).length > 512 * 1024) {
      throw const FormatException('OCI manifest exceeds metadata budget');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('Invalid OCI JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid OCI manifest');
    }
    if (decoded.keys.toSet().difference({
      'schemaVersion',
      'mediaType',
      'config',
      'layers',
    }).isNotEmpty) {
      throw const FormatException('Unsupported manifest key');
    }
    if (decoded['schemaVersion'] != 2 ||
        decoded['mediaType'] != 'application/vnd.oci.image.manifest.v1+json') {
      throw const FormatException('Unsupported OCI manifest version');
    }
    final rawLayers = decoded['layers'];
    if (rawLayers is! List || rawLayers.length > 128) {
      throw const FormatException('Invalid OCI layers');
    }
    return OciRootfsManifest(
      config: OciRootfsDescriptor.fromJson(decoded['config']),
      layers: rawLayers.map(OciRootfsDescriptor.fromJson).toList(),
    );
  }
}

/// Check proposed TAR entry metadata before any decompression/extraction.
/// Callers must additionally prevent symlink traversal, hardlink traversal,
/// compression bombs and filesystem races using a sandboxed extractor.
final class OciTarEntryPolicy {
  const OciTarEntryPolicy._();

  static void check({
    required String name,
    required String type,
    required int size,
  }) {
    if (name.isEmpty ||
        name.length > 1024 ||
        name.startsWith('/') ||
        name.startsWith('\\') ||
        name.contains('\\') ||
        name.contains('\u0000') ||
        RegExp(r'^[a-zA-Z]:').hasMatch(name) ||
        name.split('/').any((part) => part == '..' || part == '.')) {
      throw const FormatException('Unsafe TAR entry path');
    }
    if (type != 'file' && type != 'directory') {
      throw const FormatException('Links and device nodes are not supported');
    }
    if (size < 0 || size > 1024 * 1024 * 1024) {
      throw const FormatException('TAR entry size exceeds limit');
    }
  }
}
