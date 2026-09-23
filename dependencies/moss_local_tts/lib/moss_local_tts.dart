import 'package:flutter/services.dart';

final class MossLocalTtsSynthesisResult {
  const MossLocalTtsSynthesisResult({
    required this.outputPath,
    required this.generatedFrames,
    required this.sampleRate,
    required this.durationMs,
    required this.elapsedMs,
  });

  final String outputPath;
  final int generatedFrames;
  final int sampleRate;
  final int durationMs;
  final int elapsedMs;
}

final class MossLocalTts {
  const MossLocalTts();

  static const MethodChannel _channel = MethodChannel(
    'com.psyche.kelivo/moss_local_tts',
  );

  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<MossLocalTtsSynthesisResult> synthesize({
    required String modelRoot,
    required List<int> textTokenIds,
    String voice = 'Junhao',
    int cpuThreads = 2,
    int maxFrames = 375,
    int? seed,
  }) async {
    if (textTokenIds.isEmpty) {
      throw ArgumentError.value(textTokenIds, 'textTokenIds', 'Must not be empty');
    }
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'synthesize',
      <String, dynamic>{
        'modelRoot': modelRoot,
        'textTokenIds': textTokenIds,
        'voice': voice,
        'cpuThreads': cpuThreads,
        'maxFrames': maxFrames,
        if (seed != null) 'seed': seed,
      },
    );
    if (result == null) {
      throw StateError('MOSS local TTS returned no result');
    }
    final outputPath = result['outputPath']?.toString() ?? '';
    if (outputPath.isEmpty) {
      throw StateError('MOSS local TTS returned no output path');
    }
    return MossLocalTtsSynthesisResult(
      outputPath: outputPath,
      generatedFrames: (result['generatedFrames'] as num?)?.toInt() ?? 0,
      sampleRate: (result['sampleRate'] as num?)?.toInt() ?? 0,
      durationMs: (result['durationMs'] as num?)?.toInt() ?? 0,
      elapsedMs: (result['elapsedMs'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> unload() async {
    try {
      await _channel.invokeMethod<void>('unload');
    } on MissingPluginException {
      // Android is the only supported runtime for now.
    }
  }
}
