import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/tts/local_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('resolveTtsBackend', () {
    test('automatic prefers a ready local model over cloud', () {
      expect(
        resolveTtsBackend(
          mode: TtsBackendMode.automatic,
          localInstalled: true,
          localReady: true,
          cloudAvailable: true,
        ),
        TtsBackendChoice.local,
      );
    });

    test('automatic does not leak to cloud when installed local runtime fails', () {
      expect(
        resolveTtsBackend(
          mode: TtsBackendMode.automatic,
          localInstalled: true,
          localReady: false,
          cloudAvailable: true,
        ),
        TtsBackendChoice.unavailable,
      );
    });

    test('automatic uses cloud only when no local model is installed', () {
      expect(
        resolveTtsBackend(
          mode: TtsBackendMode.automatic,
          localInstalled: false,
          localReady: false,
          cloudAvailable: true,
        ),
        TtsBackendChoice.cloud,
      );
    });

    test('automatic falls back to system TTS without local or cloud', () {
      expect(
        resolveTtsBackend(
          mode: TtsBackendMode.automatic,
          localInstalled: false,
          localReady: false,
          cloudAvailable: false,
        ),
        TtsBackendChoice.system,
      );
    });

    test('explicit modes stay strict', () {
      expect(
        resolveTtsBackend(
          mode: TtsBackendMode.localOnly,
          localInstalled: false,
          localReady: false,
          cloudAvailable: true,
        ),
        TtsBackendChoice.unavailable,
      );
      expect(
        resolveTtsBackend(
          mode: TtsBackendMode.cloudOnly,
          localInstalled: true,
          localReady: true,
          cloudAvailable: true,
        ),
        TtsBackendChoice.cloud,
      );
      expect(
        resolveTtsBackend(
          mode: TtsBackendMode.systemOnly,
          localInstalled: true,
          localReady: true,
          cloudAvailable: true,
        ),
        TtsBackendChoice.system,
      );
    });
  });

  group('MossLocalModelStore', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kelivo_moss_tts_test_');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('validates a complete local ONNX layout without network access', () async {
      await _writeCompleteModel(root);
      final store = MossLocalModelStore(rootDirectory: root);

      final validation = await store.validate();

      expect(validation.isValid, isTrue);
      expect(validation.missingPaths, isEmpty);
      expect(validation.tokenizerPath, isNotNull);
      expect(await store.isInstalled(), isTrue);
    });

    test('reports a missing ONNX file as not installed', () async {
      await _writeCompleteModel(root);
      final missing = File(
        p.join(
          root.path,
          'MOSS-TTS-Nano-100M-ONNX',
          'moss_tts_decode_step.onnx',
        ),
      );
      await missing.delete();
      final store = MossLocalModelStore(rootDirectory: root);

      final validation = await store.validate();

      expect(validation.isValid, isFalse);
      expect(validation.missingPaths, contains(missing.path));
      expect(await store.isInstalled(), isFalse);
    });
  });
}

Future<void> _writeCompleteModel(Directory root) async {
  final ttsDir = Directory(
    p.join(root.path, 'MOSS-TTS-Nano-100M-ONNX'),
  );
  final codecDir = Directory(
    p.join(root.path, 'MOSS-Audio-Tokenizer-Nano-ONNX'),
  );
  await ttsDir.create(recursive: true);
  await codecDir.create(recursive: true);

  await File(p.join(ttsDir.path, 'browser_poc_manifest.json')).writeAsString(
    jsonEncode(<String, dynamic>{
      'model_files': <String, dynamic>{
        'tts_meta': 'tts_browser_onnx_meta.json',
        'codec_meta':
            '../MOSS-Audio-Tokenizer-Nano-ONNX/codec_browser_onnx_meta.json',
        'tokenizer_model': 'tokenizer.model',
      },
    }),
  );
  await File(p.join(ttsDir.path, 'tts_browser_onnx_meta.json')).writeAsString(
    jsonEncode(<String, dynamic>{
      'files': <String, dynamic>{
        'prefill': 'moss_tts_prefill.onnx',
        'decode_step': 'moss_tts_decode_step.onnx',
        'local_fixed_sampled_frame': 'moss_tts_local_fixed_sampled_frame.onnx',
      },
    }),
  );
  await File(
    p.join(codecDir.path, 'codec_browser_onnx_meta.json'),
  ).writeAsString(
    jsonEncode(<String, dynamic>{
      'files': <String, dynamic>{
        'decode_full': 'moss_audio_tokenizer_decode_full.onnx',
      },
    }),
  );

  for (final path in <String>[
    p.join(ttsDir.path, 'tokenizer.model'),
    p.join(ttsDir.path, 'moss_tts_prefill.onnx'),
    p.join(ttsDir.path, 'moss_tts_decode_step.onnx'),
    p.join(ttsDir.path, 'moss_tts_local_fixed_sampled_frame.onnx'),
    p.join(ttsDir.path, 'moss_tts_global_shared.data'),
    p.join(codecDir.path, 'moss_audio_tokenizer_decode_full.onnx'),
    p.join(codecDir.path, 'moss_audio_tokenizer_shared.data'),
  ]) {
    await File(path).writeAsBytes(const <int>[0]);
  }
}
