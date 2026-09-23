import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'story_reference_analysis_parser.dart';
import 'story_reference_chunker.dart';
import 'story_reference_leak_guard.dart';
import 'story_reference_models.dart';

final class StoryReferenceProfileFactory {
  const StoryReferenceProfileFactory({
    this.leakGuard = const StoryReferenceLeakGuard(),
  });

  final StoryReferenceLeakGuard leakGuard;

  StoryReferenceStyleProfile build({
    required StoryReferenceDocument document,
    required String sourceText,
    required StoryReferenceAnalysisSnapshot analysis,
    String? name,
    int? createdAtMs,
  }) {
    final normalizedSource = normalizeReferenceText(sourceText);
    final sourceHash = sha256.convert(utf8.encode(normalizedSource)).toString();
    if (sourceHash != document.contentHash) {
      throw const StoryReferenceProfileException('source_hash_mismatch');
    }

    final leak = leakGuard.check(
      sourceText: normalizedSource,
      analysis: analysis,
    );
    if (leak.blocked) {
      // Deliberately omit the matching source fragment from the exception so it
      // cannot leak into ordinary logs or UI telemetry.
      throw StoryReferenceProfileException(
        'source_phrase_leak_detected',
        detail: leak.reasonCode,
      );
    }

    final profileName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : '${document.title} Style';
    final profileId = _profileId(document, analysis, profileName);
    return StoryReferenceStyleProfile(
      id: profileId,
      documentId: document.id,
      name: profileName,
      sourceContentHash: document.contentHash,
      createdAtMs: createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
      language: analysis.language,
      aspects: analysis.aspects,
      coreTraits: analysis.coreTraits,
      sentenceRhythm: analysis.sentenceRhythm,
      paragraphing: analysis.paragraphing,
      diction: analysis.diction,
      narrationMethods: analysis.narrationMethods,
      dialogueMethods: analysis.dialogueMethods,
      descriptionMethods: analysis.descriptionMethods,
      actionMethods: analysis.actionMethods,
      atmosphereMethods: analysis.atmosphereMethods,
      intimacyMethods: analysis.intimacyMethods,
      interiorityMethods: analysis.interiorityMethods,
      pacingMethods: analysis.pacingMethods,
      avoidPatterns: analysis.avoidPatterns,
      metrics: analysis.metrics,
    );
  }
}

final class StoryReferenceProfileException implements Exception {
  const StoryReferenceProfileException(this.code, {this.detail});

  final String code;
  final String? detail;

  @override
  String toString() => detail == null
      ? 'StoryReferenceProfileException($code)'
      : 'StoryReferenceProfileException($code: $detail)';
}

String _profileId(
  StoryReferenceDocument document,
  StoryReferenceAnalysisSnapshot analysis,
  String name,
) {
  final aspects = analysis.aspects.map((value) => value.name).toList()..sort();
  final metricKeys = analysis.metrics.keys.toList()..sort();
  final payload = jsonEncode(<String, Object?>{
    'document_id': document.id,
    'source_hash': document.contentHash,
    'name': name,
    'aspects': aspects,
    'core_traits': analysis.coreTraits,
    'metrics': <String, double>{
      for (final key in metricKeys) key: analysis.metrics[key]!,
    },
  });
  final hash = sha256.convert(utf8.encode(payload)).toString();
  return 'style_${hash.substring(0, 24)}';
}
