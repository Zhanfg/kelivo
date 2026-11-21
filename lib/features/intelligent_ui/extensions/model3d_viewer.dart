import 'dart:convert';
import 'dart:typed_data';

/// GLB v2 metadata and interaction-state prototype only.
///
/// This does not rasterize a 3D mesh; a separate renderer/host approval and
/// Android/desktop GPU performance gate are required before integration.
final class GlbModelDocument {
  GlbModelDocument._(this.nodes, this.meshCount, this.byteLength);

  final List<String> nodes;
  final int meshCount;
  final int byteLength;

  /// Parse a bounded binary glTF 2.0 container without reading external URIs.
  factory GlbModelDocument.parse(Uint8List bytes, {int maxBytes = 8 << 20}) {
    if (bytes.length < 20 || bytes.length > maxBytes || maxBytes <= 0) {
      throw const FormatException('Invalid GLB size');
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != 0x46546c67 ||
        data.getUint32(4, Endian.little) != 2 ||
        data.getUint32(8, Endian.little) != bytes.length) {
      throw const FormatException('Invalid GLB header or version');
    }
    if (data.getUint32(12, Endian.little) % 4 != 0 ||
        data.getUint32(16, Endian.little) != 0x4e4f534a) {
      throw const FormatException('Missing aligned JSON chunk');
    }
    final length = data.getUint32(12, Endian.little);
    if (length > bytes.length - 20) {
      throw const FormatException('Truncated JSON chunk');
    }
    final decoded = jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)));
    if (decoded is! Map<String, dynamic> ||
        decoded['asset'] is! Map ||
        decoded['asset']['version'] != '2.0') {
      throw const FormatException('Invalid glTF 2.0 metadata');
    }
    final nodesRaw = decoded['nodes'];
    final meshesRaw = decoded['meshes'];
    if (nodesRaw != null && nodesRaw is! List ||
        meshesRaw != null && meshesRaw is! List ||
        nodesRaw is List && nodesRaw.length > 10000 ||
        meshesRaw is List && meshesRaw.length > 10000) {
      throw const FormatException('Unsafe node/mesh count');
    }
    final nodeNames = <String>[];
    for (final node in nodesRaw is List ? nodesRaw : const []) {
      if (node is! Map || node['name'] != null && node['name'] is! String) {
        throw const FormatException('Invalid glTF node');
      }
      final name = (node['name'] as String?) ?? 'Node ${nodeNames.length}';
      if (name.length > 128) throw const FormatException('Node name too long');
      nodeNames.add(name);
    }
    var cursor = 20 + length;
    if (cursor < bytes.length) {
      if (bytes.length - cursor < 8) {
        throw const FormatException('Incomplete BIN header');
      }
      final binLen = data.getUint32(cursor, Endian.little);
      final binType = data.getUint32(cursor + 4, Endian.little);
      cursor += 8;
      if (binType != 0x004e4942 ||
          binLen % 4 != 0 ||
          binLen != bytes.length - cursor) {
        throw const FormatException('Invalid BIN chunk');
      }
    }
    return GlbModelDocument._(
      List.unmodifiable(nodeNames),
      meshesRaw is List ? meshesRaw.length : 0,
      bytes.length,
    );
  }
}

/// Pure viewer state for orbit/zoom/selection and offscreen pause semantics.
final class GlbViewerState {
  GlbViewerState(this.document);
  final GlbModelDocument document;
  double yawRadians = 0;
  double pitchRadians = 0;
  double zoom = 1;
  int? selectedNode;
  bool paused = true;

  void setVisible(bool visible) {
    paused = !visible;
  }

  void orbit(double yawDelta, double pitchDelta) {
    if (paused) return;
    if (!yawDelta.isFinite || !pitchDelta.isFinite) {
      throw ArgumentError('Invalid rotation');
    }
    yawRadians += yawDelta;
    pitchRadians = (pitchRadians + pitchDelta).clamp(-1.5, 1.5);
  }

  void setZoom(double value) {
    if (!value.isFinite || value < 0.1 || value > 8) {
      throw ArgumentError('Zoom out of bounds');
    }
    if (!paused) zoom = value;
  }

  void select(int? index) {
    if (index != null && (index < 0 || index >= document.nodes.length)) {
      throw RangeError.index(index, document.nodes);
    }
    if (!paused) selectedNode = index;
  }
}
