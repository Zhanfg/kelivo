/// Reference Library models for Story Runtime.
///
/// Imported novels are source material for analysis only. The callable asset is
/// a compact, abstract StyleProfile that contains no source excerpts, plot facts
/// or character identities.
library;

enum StoryReferenceSourceKind { file, pastedText }

enum StoryReferenceAspect {
  prose,
  narration,
  dialogue,
  description,
  action,
  atmosphere,
  horror,
  romanceIntimacy,
  pacing,
  characterInterior,
  worldbuilding,
}

final class StoryReferenceDocument {
  const StoryReferenceDocument({
    required this.id,
    required this.title,
    required this.sourceKind,
    required this.contentHash,
    required this.normalizedRelativePath,
    required this.characterCount,
    required this.chunkCount,
    required this.importedAtMs,
    this.sourceFileName,
    this.mime,
    this.language,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String title;
  final StoryReferenceSourceKind sourceKind;
  final String contentHash;

  /// Relative path under Story Reference Library storage. Never persist a
  /// sandbox-specific absolute path.
  final String normalizedRelativePath;
  final int characterCount;
  final int chunkCount;
  final int importedAtMs;
  final String? sourceFileName;
  final String? mime;
  final String? language;
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'source_kind': sourceKind.name,
    'content_hash': contentHash,
    'normalized_relative_path': normalizedRelativePath,
    'character_count': characterCount,
    'chunk_count': chunkCount,
    'imported_at_ms': importedAtMs,
    if (sourceFileName != null) 'source_file_name': sourceFileName,
    if (mime != null) 'mime': mime,
    if (language != null) 'language': language,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  factory StoryReferenceDocument.fromJson(Map<String, dynamic> json) {
    final sourceKind = switch (_string(json['source_kind'])) {
      'file' => StoryReferenceSourceKind.file,
      'pastedText' || 'pasted_text' => StoryReferenceSourceKind.pastedText,
      final value => throw FormatException('unknown_reference_source:$value'),
    };
    return StoryReferenceDocument(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      sourceKind: sourceKind,
      contentHash: _requiredString(json, 'content_hash'),
      normalizedRelativePath: _requiredString(json, 'normalized_relative_path'),
      characterCount: _nonNegativeInt(json, 'character_count'),
      chunkCount: _nonNegativeInt(json, 'chunk_count'),
      importedAtMs: _nonNegativeInt(json, 'imported_at_ms'),
      sourceFileName: _string(json['source_file_name']),
      mime: _string(json['mime']),
      language: _string(json['language']),
      metadata: Map.unmodifiable(_stringKeyedMap(json['metadata'])),
    );
  }
}

final class StoryReferenceChunk {
  const StoryReferenceChunk({
    required this.id,
    required this.documentId,
    required this.index,
    required this.text,
    required this.contentHash,
  });

  final String id;
  final String documentId;
  final int index;
  final String text;
  final String contentHash;
}

/// Abstract callable style asset derived from one or more analysis passes.
final class StoryReferenceStyleProfile {
  const StoryReferenceStyleProfile({
    required this.id,
    required this.documentId,
    required this.name,
    required this.sourceContentHash,
    required this.createdAtMs,
    this.language,
    this.aspects = const <StoryReferenceAspect>{},
    this.coreTraits = const <String>[],
    this.sentenceRhythm = const <String>[],
    this.paragraphing = const <String>[],
    this.diction = const <String>[],
    this.narrationMethods = const <String>[],
    this.dialogueMethods = const <String>[],
    this.descriptionMethods = const <String>[],
    this.actionMethods = const <String>[],
    this.atmosphereMethods = const <String>[],
    this.intimacyMethods = const <String>[],
    this.interiorityMethods = const <String>[],
    this.pacingMethods = const <String>[],
    this.avoidPatterns = const <String>[],
    this.metrics = const <String, double>{},
    this.schemaVersion = currentSchemaVersion,
  });

  static const int currentSchemaVersion = 1;

  final String id;
  final String documentId;
  final String name;
  final String sourceContentHash;
  final int createdAtMs;
  final String? language;
  final Set<StoryReferenceAspect> aspects;

  /// All fields below must be source-independent abstractions. They must not
  /// contain quotes, names, plot facts or distinctive source phrases.
  final List<String> coreTraits;
  final List<String> sentenceRhythm;
  final List<String> paragraphing;
  final List<String> diction;
  final List<String> narrationMethods;
  final List<String> dialogueMethods;
  final List<String> descriptionMethods;
  final List<String> actionMethods;
  final List<String> atmosphereMethods;

  /// Mature/intimate craft may be represented as pacing, emotional framing,
  /// sensory granularity, consent visibility and degree of directness. The
  /// profile stores abstractions rather than source passages.
  final List<String> intimacyMethods;

  final List<String> interiorityMethods;
  final List<String> pacingMethods;
  final List<String> avoidPatterns;

  /// Normalized 0..1 analysis dimensions such as dialogue_ratio,
  /// sensory_density, sentence_variance and intimacy_directness.
  final Map<String, double> metrics;
  final int schemaVersion;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': schemaVersion,
    'id': id,
    'document_id': documentId,
    'name': name,
    'source_content_hash': sourceContentHash,
    'created_at_ms': createdAtMs,
    if (language != null) 'language': language,
    'aspects': aspects.map((aspect) => aspect.name).toList()..sort(),
    'core_traits': coreTraits,
    'sentence_rhythm': sentenceRhythm,
    'paragraphing': paragraphing,
    'diction': diction,
    'narration_methods': narrationMethods,
    'dialogue_methods': dialogueMethods,
    'description_methods': descriptionMethods,
    'action_methods': actionMethods,
    'atmosphere_methods': atmosphereMethods,
    'intimacy_methods': intimacyMethods,
    'interiority_methods': interiorityMethods,
    'pacing_methods': pacingMethods,
    'avoid_patterns': avoidPatterns,
    'metrics': metrics,
  };

  factory StoryReferenceStyleProfile.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _int(json['schema_version'], fallback: 1);
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException('unsupported_reference_profile:$schemaVersion');
    }
    final metricsRaw = _stringKeyedMap(json['metrics']);
    final metrics = <String, double>{};
    for (final entry in metricsRaw.entries) {
      final value = entry.value;
      if (value is! num || value.isNaN || value.isInfinite) {
        throw FormatException('invalid_reference_metric:${entry.key}');
      }
      final normalized = value.toDouble();
      if (normalized < 0 || normalized > 1) {
        throw FormatException('reference_metric_out_of_range:${entry.key}');
      }
      metrics[entry.key] = normalized;
    }

    final aspects = <StoryReferenceAspect>{};
    for (final item in _strings(json['aspects'])) {
      aspects.add(
        StoryReferenceAspect.values.firstWhere(
          (value) => value.name == item,
          orElse: () => throw FormatException('unknown_reference_aspect:$item'),
        ),
      );
    }

    return StoryReferenceStyleProfile(
      id: _requiredString(json, 'id'),
      documentId: _requiredString(json, 'document_id'),
      name: _requiredString(json, 'name'),
      sourceContentHash: _requiredString(json, 'source_content_hash'),
      createdAtMs: _nonNegativeInt(json, 'created_at_ms'),
      language: _string(json['language']),
      aspects: Set.unmodifiable(aspects),
      coreTraits: _strings(json['core_traits']),
      sentenceRhythm: _strings(json['sentence_rhythm']),
      paragraphing: _strings(json['paragraphing']),
      diction: _strings(json['diction']),
      narrationMethods: _strings(json['narration_methods']),
      dialogueMethods: _strings(json['dialogue_methods']),
      descriptionMethods: _strings(json['description_methods']),
      actionMethods: _strings(json['action_methods']),
      atmosphereMethods: _strings(json['atmosphere_methods']),
      intimacyMethods: _strings(json['intimacy_methods']),
      interiorityMethods: _strings(json['interiority_methods']),
      pacingMethods: _strings(json['pacing_methods']),
      avoidPatterns: _strings(json['avoid_patterns']),
      metrics: Map.unmodifiable(metrics),
      schemaVersion: schemaVersion,
    );
  }
}

/// User-selected invocation of one derived profile.
final class StoryReferenceInvocation {
  const StoryReferenceInvocation({
    required this.profileId,
    this.strength = 0.65,
    this.enabledAspects = const <StoryReferenceAspect>{},
    this.turnScoped = false,
  }) : assert(strength >= 0 && strength <= 1);

  final String profileId;
  final double strength;
  final Set<StoryReferenceAspect> enabledAspects;

  /// One-turn references are volatile; persistent references are resolved into
  /// an explicit scene/capability epoch.
  final bool turnScoped;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _string(json[key]);
  if (value == null) throw FormatException('missing_reference_$key');
  return value;
}

String? _string(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('invalid_reference_string');
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _int(Object? value, {required int fallback}) {
  if (value == null) return fallback;
  if (value is! num || value.isNaN || value.isInfinite || value % 1 != 0) {
    throw const FormatException('invalid_reference_integer');
  }
  return value.toInt();
}

int _nonNegativeInt(Map<String, dynamic> json, String key) {
  final value = _int(json[key], fallback: -1);
  if (value < 0) throw FormatException('invalid_reference_$key');
  return value;
}

Map<String, Object?> _stringKeyedMap(Object? value) {
  if (value == null) return <String, Object?>{};
  if (value is! Map) throw const FormatException('invalid_reference_object');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<String> _strings(Object? value) {
  if (value == null) return const <String>[];
  if (value is! List) throw const FormatException('invalid_reference_list');
  final result = <String>[];
  for (final item in value) {
    final text = _string(item);
    if (text != null) result.add(text);
  }
  return List.unmodifiable(result);
}
