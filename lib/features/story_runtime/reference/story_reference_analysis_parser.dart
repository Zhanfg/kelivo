import 'dart:convert';

import 'story_reference_models.dart';

final class StoryReferenceAnalysisSnapshot {
  const StoryReferenceAnalysisSnapshot({
    required this.language,
    required this.aspects,
    required this.coreTraits,
    required this.sentenceRhythm,
    required this.paragraphing,
    required this.diction,
    required this.narrationMethods,
    required this.dialogueMethods,
    required this.descriptionMethods,
    required this.actionMethods,
    required this.atmosphereMethods,
    required this.intimacyMethods,
    required this.interiorityMethods,
    required this.pacingMethods,
    required this.avoidPatterns,
    required this.metrics,
  });

  final String? language;
  final Set<StoryReferenceAspect> aspects;
  final List<String> coreTraits;
  final List<String> sentenceRhythm;
  final List<String> paragraphing;
  final List<String> diction;
  final List<String> narrationMethods;
  final List<String> dialogueMethods;
  final List<String> descriptionMethods;
  final List<String> actionMethods;
  final List<String> atmosphereMethods;
  final List<String> intimacyMethods;
  final List<String> interiorityMethods;
  final List<String> pacingMethods;
  final List<String> avoidPatterns;
  final Map<String, double> metrics;

  Iterable<String> get allTextFields sync* {
    yield* coreTraits;
    yield* sentenceRhythm;
    yield* paragraphing;
    yield* diction;
    yield* narrationMethods;
    yield* dialogueMethods;
    yield* descriptionMethods;
    yield* actionMethods;
    yield* atmosphereMethods;
    yield* intimacyMethods;
    yield* interiorityMethods;
    yield* pacingMethods;
    yield* avoidPatterns;
  }
}

/// Defensive parser for reference-analysis model output.
final class StoryReferenceAnalysisParser {
  const StoryReferenceAnalysisParser({
    this.maxItemsPerField = 32,
    this.maxItemChars = 360,
    this.maxMetrics = 64,
  });

  final int maxItemsPerField;
  final int maxItemChars;
  final int maxMetrics;

  StoryReferenceAnalysisSnapshot parse(String raw) {
    final source = _stripJsonFence(raw);
    late final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw StoryReferenceAnalysisException(
        'invalid_json',
        detail: error.message,
      );
    }
    if (decoded is! Map) {
      throw const StoryReferenceAnalysisException('root_not_object');
    }
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    final version = json['version'];
    if (version is! num || version != 1) {
      throw const StoryReferenceAnalysisException('unsupported_version');
    }

    final aspects = <StoryReferenceAspect>{};
    for (final item in _list(json, 'aspects')) {
      final name = _text(item, 'aspect');
      try {
        aspects.add(
          StoryReferenceAspect.values.firstWhere((value) => value.name == name),
        );
      } on StateError {
        throw StoryReferenceAnalysisException(
          'unknown_reference_aspect',
          detail: name,
        );
      }
    }

    final metricsRaw = json['metrics'];
    final metrics = <String, double>{};
    if (metricsRaw != null) {
      if (metricsRaw is! Map) {
        throw const StoryReferenceAnalysisException('invalid_metrics');
      }
      if (metricsRaw.length > maxMetrics) {
        throw const StoryReferenceAnalysisException('too_many_metrics');
      }
      for (final entry in metricsRaw.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty || !RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(key)) {
          throw StoryReferenceAnalysisException(
            'invalid_metric_name',
            detail: key,
          );
        }
        final value = entry.value;
        if (value is! num || value.isNaN || value.isInfinite) {
          throw StoryReferenceAnalysisException(
            'invalid_metric_value',
            detail: key,
          );
        }
        final normalized = value.toDouble();
        if (normalized < 0 || normalized > 1) {
          throw StoryReferenceAnalysisException(
            'metric_out_of_range',
            detail: key,
          );
        }
        metrics[key] = normalized;
      }
    }

    return StoryReferenceAnalysisSnapshot(
      language: _optionalText(json['language']),
      aspects: Set.unmodifiable(aspects),
      coreTraits: _textField(json, 'core_traits'),
      sentenceRhythm: _textField(json, 'sentence_rhythm'),
      paragraphing: _textField(json, 'paragraphing'),
      diction: _textField(json, 'diction'),
      narrationMethods: _textField(json, 'narration_methods'),
      dialogueMethods: _textField(json, 'dialogue_methods'),
      descriptionMethods: _textField(json, 'description_methods'),
      actionMethods: _textField(json, 'action_methods'),
      atmosphereMethods: _textField(json, 'atmosphere_methods'),
      intimacyMethods: _textField(json, 'intimacy_methods'),
      interiorityMethods: _textField(json, 'interiority_methods'),
      pacingMethods: _textField(json, 'pacing_methods'),
      avoidPatterns: _textField(json, 'avoid_patterns'),
      metrics: Map.unmodifiable(metrics),
    );
  }

  List<String> _textField(Map<String, Object?> json, String key) {
    final raw = _list(json, key);
    if (raw.length > maxItemsPerField) {
      throw StoryReferenceAnalysisException('too_many_items', detail: key);
    }
    final result = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final text = _text(item, key);
      if (text.length > maxItemChars) {
        throw StoryReferenceAnalysisException('item_too_large', detail: key);
      }
      if (seen.add(text)) result.add(text);
    }
    return List.unmodifiable(result);
  }
}

final class StoryReferenceAnalysisException implements Exception {
  const StoryReferenceAnalysisException(this.code, {this.detail});

  final String code;
  final String? detail;

  @override
  String toString() => detail == null
      ? 'StoryReferenceAnalysisException($code)'
      : 'StoryReferenceAnalysisException($code: $detail)';
}

List<Object?> _list(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const <Object?>[];
  if (value is! List) {
    throw StoryReferenceAnalysisException('invalid_list', detail: key);
  }
  return value.cast<Object?>();
}

String _text(Object? value, String field) {
  if (value is! String) {
    throw StoryReferenceAnalysisException('invalid_text', detail: field);
  }
  final text = value.trim();
  if (text.isEmpty) {
    throw StoryReferenceAnalysisException('empty_text', detail: field);
  }
  return text;
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const StoryReferenceAnalysisException('invalid_optional_text');
  }
  final text = value.trim();
  return text.isEmpty ? null : text;
}

String _stripJsonFence(String raw) {
  var source = raw.trim();
  if (!source.startsWith('```')) return source;
  final firstLineEnd = source.indexOf('\n');
  if (firstLineEnd == -1 || !source.endsWith('```')) return source;
  final fence = source.substring(0, firstLineEnd).trim().toLowerCase();
  if (fence != '```' && fence != '```json') return source;
  return source.substring(firstLineEnd + 1, source.length - 3).trim();
}
