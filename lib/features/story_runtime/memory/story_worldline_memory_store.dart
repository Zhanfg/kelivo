import '../../../core/services/json_blob_store.dart';
import 'story_worldline_memory.dart';

final class StoryWorldlineMemoryEnvelope {
  const StoryWorldlineMemoryEnvelope({
    required this.worldTreeId,
    required this.links,
  });

  final String worldTreeId;
  final List<StoryWorldlineMemoryLink> links;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'worldTreeId': worldTreeId,
    'links': links.map((item) => item.toJson()).toList(),
  };

  factory StoryWorldlineMemoryEnvelope.fromJson(Map<String, dynamic> json) =>
      StoryWorldlineMemoryEnvelope(
        worldTreeId: json['worldTreeId'] as String,
        links: ((json['links'] as List?) ?? const <Object?>[])
            .map(
              (item) => StoryWorldlineMemoryLink.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
}

final class StoryWorldlineMemoryStore
    extends JsonBlobStore<StoryWorldlineMemoryEnvelope> {
  StoryWorldlineMemoryStore(super.preferences);

  static const String key = 'story_worldline_memory_v1';

  @override
  String get storageKey => key;

  @override
  StoryWorldlineMemoryEnvelope decodeItem(Map<String, dynamic> json) =>
      StoryWorldlineMemoryEnvelope.fromJson(json);

  @override
  Map<String, dynamic> encodeItem(StoryWorldlineMemoryEnvelope item) =>
      item.toJson();

  Future<List<StoryWorldlineMemoryLink>> readForTree(String worldTreeId) async {
    final id = _required(worldTreeId);
    for (final item in await readAll()) {
      if (item.worldTreeId == id) return item.links;
    }
    return const <StoryWorldlineMemoryLink>[];
  }

  Future<void> writeForTree(
    String worldTreeId,
    List<StoryWorldlineMemoryLink> links,
  ) {
    return runExclusive(() async {
      final id = _required(worldTreeId);
      final items = await readAll();
      final next = <StoryWorldlineMemoryEnvelope>[];
      var replaced = false;
      for (final item in items) {
        if (item.worldTreeId != id) {
          next.add(item);
        } else if (!replaced) {
          next.add(
            StoryWorldlineMemoryEnvelope(
              worldTreeId: id,
              links: List.unmodifiable(links),
            ),
          );
          replaced = true;
        }
      }
      if (!replaced) {
        next.add(
          StoryWorldlineMemoryEnvelope(
            worldTreeId: id,
            links: List.unmodifiable(links),
          ),
        );
      }
      next.sort((a, b) => a.worldTreeId.compareTo(b.worldTreeId));
      await writeAll(next);
    });
  }
}

String _required(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError.value(value, 'worldTreeId');
  return normalized;
}
