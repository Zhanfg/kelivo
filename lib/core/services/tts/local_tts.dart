import 'dart:convert';
import 'dart:io' as io;

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/foundation.dart';
import 'package:moss_local_tts/moss_local_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Compatibility helper for the local-first TTS integration. Dart's [io.File]
/// exposes [io.File.exists] rather than `isFile`; keeping this extension lets
/// the imported TTS coordinator use the same intent without touching playback
/// behavior.
extension FileExistenceCompatibility on io.File {
  Future<bool> isFile() => exists();
}

enum TtsBackendMode {
  automatic('auto'),
  localOnly('local'),
  cloudOnly('cloud'),
  systemOnly('system');

  const TtsBackendMode(this.storageValue);
  final String storageValue;

  static TtsBackendMode fromStorage(String? value) {
    return TtsBackendMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => TtsBackendMode.automatic,
    );
  }
}

enum TtsBackendChoice { local, cloud, system, unavailable }

TtsBackendChoice resolveTtsBackend({
  required TtsBackendMode mode,
  required bool localInstalled,
  required bool localReady,
  required bool cloudAvailable,
}) {
  switch (mode) {
    case TtsBackendMode.automatic:
      // A downloaded local model is a privacy boundary: do not silently send
      // text to a remote service if the local runtime happens to fail.
      if (localInstalled) {
        return localReady
            ? TtsBackendChoice.local
            : TtsBackendChoice.unavailable;
      }
      if (cloudAvailable) return TtsBackendChoice.cloud;
      return TtsBackendChoice.system;
    case TtsBackendMode.localOnly:
      return localReady ? TtsBackendChoice.local : TtsBackendChoice.unavailable;
    case TtsBackendMode.cloudOnly:
      return cloudAvailable
          ? TtsBackendChoice.cloud
          : TtsBackendChoice.unavailable;
    case TtsBackendMode.systemOnly:
      return TtsBackendChoice.system;
  }
}

final class LocalTtsAudioResult {
  const LocalTtsAudioResult({
    required this.filePath,
    this.mime = 'audio/wav',
    this.duration,
  });

  final String filePath;
  final String mime;
  final Duration? duration;
}

abstract interface class LocalTtsBackend {
  String get id;
  int get maxCharsPerRequest;

  Future<bool> isInstalled();
  Future<bool> isReady();
  Future<LocalTtsAudioResult> synthesize(
    String text, {
    bool Function()? cancelled,
  });
  Future<void> unload();
}

final class MossLocalModelValidation {
  const MossLocalModelValidation({
    required this.rootPath,
    required this.tokenizerPath,
    required this.missingPaths,
  });

  final String rootPath;
  final String? tokenizerPath;
  final List<String> missingPaths;

  bool get isValid => tokenizerPath != null && missingPaths.isEmpty;
}

final class MossLocalModelInstallResult {
  const MossLocalModelInstallResult({
    required this.rootPath,
    required this.validation,
  });

  final String rootPath;
  final MossLocalModelValidation validation;
}

/// Local-only MOSS model discovery, validation and installation.
///
/// This class intentionally has no HTTP dependency. Calling [validate],
/// [isInstalled] or [installFromDirectory] never contacts GitHub, Hugging Face,
/// or a cloud TTS API. Installation copies a user-selected model folder into
/// Kelivo's application support directory, validates a staging copy first and
/// only then swaps it into the live location.
final class MossLocalModelStore {
  MossLocalModelStore({this.rootDirectory});

  final io.Directory? rootDirectory;

  static const String modelFolderName = 'moss_tts_nano';
  static const List<String> _manifestCandidates = <String>[
    'browser_poc_manifest.json',
    'MOSS-TTS-Nano-100M-ONNX/browser_poc_manifest.json',
    'MOSS-TTS-Nano-ONNX-CPU/browser_poc_manifest.json',
  ];

  Future<io.Directory> resolveRootDirectory() async {
    if (rootDirectory != null) return rootDirectory!;
    final support = await getApplicationSupportDirectory();
    return io.Directory(p.join(support.path, 'tts_models', modelFolderName));
  }

  Future<bool> isInstalled() async {
    try {
      return (await validate()).isValid;
    } catch (_) {
      return false;
    }
  }

  Future<MossLocalModelInstallResult> installFromDirectory(
    String sourcePath,
  ) async {
    final normalizedSourcePath = p.normalize(sourcePath.trim());
    if (normalizedSourcePath.isEmpty) {
      throw ArgumentError.value(sourcePath, 'sourcePath');
    }
    final source = io.Directory(normalizedSourcePath);
    if (!await source.exists()) {
      throw StateError('Selected MOSS model folder does not exist.');
    }

    final sourceValidation = await MossLocalModelStore(
      rootDirectory: source,
    ).validate();
    if (!sourceValidation.isValid) {
      throw StateError(
        'Selected MOSS model folder is incomplete: '
        '${sourceValidation.missingPaths.join(', ')}',
      );
    }

    final target = await resolveRootDirectory();
    final sourceAbsolute = p.normalize(source.absolute.path);
    final targetAbsolute = p.normalize(target.absolute.path);
    if (p.equals(sourceAbsolute, targetAbsolute)) {
      return MossLocalModelInstallResult(
        rootPath: target.path,
        validation: sourceValidation,
      );
    }
    if (p.isWithin(sourceAbsolute, targetAbsolute) ||
        p.isWithin(targetAbsolute, sourceAbsolute)) {
      throw StateError(
        'Choose a model source folder outside Kelivo local TTS storage.',
      );
    }

    await target.parent.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final staging = io.Directory('${target.path}.install-$stamp');
    final backup = io.Directory('${target.path}.backup-$stamp');
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      await _copyDirectory(source, staging);

      final stagedValidation = await MossLocalModelStore(
        rootDirectory: staging,
      ).validate();
      if (!stagedValidation.isValid) {
        throw StateError(
          'Copied MOSS model failed validation: '
          '${stagedValidation.missingPaths.join(', ')}',
        );
      }

      var backedUp = false;
      if (await target.exists()) {
        if (await backup.exists()) await backup.delete(recursive: true);
        await target.rename(backup.path);
        backedUp = true;
      }
      try {
        await staging.rename(target.path);
      } catch (_) {
        if (backedUp && await backup.exists() && !await target.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete(recursive: true);

      final installedValidation = await validate();
      if (!installedValidation.isValid) {
        throw StateError(
          'Installed MOSS model failed final validation: '
          '${installedValidation.missingPaths.join(', ')}',
        );
      }
      return MossLocalModelInstallResult(
        rootPath: target.path,
        validation: installedValidation,
      );
    } finally {
      if (await staging.exists()) {
        try {
          await staging.delete(recursive: true);
        } catch (_) {}
      }
      if (await backup.exists()) {
        // A backup is only left here after a failed operation. Restore it when
        // possible rather than silently deleting the last valid model.
        try {
          if (!await target.exists()) {
            await backup.rename(target.path);
          }
        } catch (_) {}
      }
    }
  }

  Future<void> removeInstalledModel() async {
    final target = await resolveRootDirectory();
    if (await target.exists()) await target.delete(recursive: true);
  }

  Future<MossLocalModelValidation> validate() async {
    final root = await resolveRootDirectory();
    final missing = <String>[];
    io.File? manifestFile;
    for (final candidate in _manifestCandidates) {
      final file = io.File(p.join(root.path, candidate));
      if (await file.exists()) {
        manifestFile = file;
        break;
      }
    }
    if (manifestFile == null) {
      return MossLocalModelValidation(
        rootPath: root.path,
        tokenizerPath: null,
        missingPaths: const <String>['browser_poc_manifest.json'],
      );
    }

    final manifest = _jsonMap(jsonDecode(await manifestFile.readAsString()));
    if (manifest.isEmpty) {
      return MossLocalModelValidation(
        rootPath: root.path,
        tokenizerPath: null,
        missingPaths: const <String>['invalid browser_poc_manifest.json'],
      );
    }
    final manifestDir = manifestFile.parent;
    final modelFiles = _jsonMap(manifest['model_files']);
    final ttsMeta = await _resolveManifestRelativeFile(
      manifestDir,
      _stringValue(modelFiles['tts_meta']) ?? 'tts_browser_onnx_meta.json',
    );
    final codecMeta = await _resolveManifestRelativeFile(
      manifestDir,
      _stringValue(modelFiles['codec_meta']) ??
          '../MOSS-Audio-Tokenizer-Nano-ONNX/codec_browser_onnx_meta.json',
    );
    final tokenizer = await _resolveManifestRelativeFile(
      manifestDir,
      _stringValue(modelFiles['tokenizer_model']) ?? 'tokenizer.model',
    );

    if (!await ttsMeta.exists()) missing.add(ttsMeta.path);
    if (!await codecMeta.exists()) missing.add(codecMeta.path);
    if (!await tokenizer.exists()) missing.add(tokenizer.path);

    if (await ttsMeta.exists()) {
      try {
        final meta = _jsonMap(jsonDecode(await ttsMeta.readAsString()));
        final files = _jsonMap(meta['files']);
        for (final key in const <String>[
          'prefill',
          'decode_step',
          'local_fixed_sampled_frame',
        ]) {
          final relative = _stringValue(files[key]);
          if (relative == null || relative.isEmpty) {
            missing.add('${ttsMeta.path}:files.$key');
            continue;
          }
          final file = io.File(p.join(ttsMeta.parent.path, relative));
          if (!await file.exists()) missing.add(file.path);
        }
        if (!await _hasExternalDataFile(ttsMeta.parent)) {
          missing.add('${ttsMeta.parent.path}${p.separator}*.data');
        }
      } catch (_) {
        missing.add('invalid ${ttsMeta.path}');
      }
    }

    if (await codecMeta.exists()) {
      try {
        final meta = _jsonMap(jsonDecode(await codecMeta.readAsString()));
        final files = _jsonMap(meta['files']);
        final relative = _stringValue(files['decode_full']);
        if (relative == null || relative.isEmpty) {
          missing.add('${codecMeta.path}:files.decode_full');
        } else {
          final file = io.File(p.join(codecMeta.parent.path, relative));
          if (!await file.exists()) missing.add(file.path);
        }
        if (!await _hasExternalDataFile(codecMeta.parent)) {
          missing.add('${codecMeta.parent.path}${p.separator}*.data');
        }
      } catch (_) {
        missing.add('invalid ${codecMeta.path}');
      }
    }

    return MossLocalModelValidation(
      rootPath: root.path,
      tokenizerPath: await tokenizer.exists() ? tokenizer.path : null,
      missingPaths: missing,
    );
  }

  static Future<void> _copyDirectory(
    io.Directory source,
    io.Directory destination,
  ) async {
    await for (final entity in source.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final nextPath = p.join(destination.path, name);
      if (entity is io.Directory) {
        final next = io.Directory(nextPath);
        await next.create(recursive: true);
        await _copyDirectory(entity, next);
      } else if (entity is io.File) {
        await entity.copy(nextPath);
      }
    }
  }

  static Map<String, dynamic> _jsonMap(Object? value) {
    if (value is! Map) return const <String, dynamic>{};
    return Map<String, dynamic>.from(value);
  }

  static String? _stringValue(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static Future<io.File> _resolveManifestRelativeFile(
    io.Directory manifestDir,
    String relativePath,
  ) async {
    final direct = io.File(p.normalize(p.join(manifestDir.path, relativePath)));
    if (await direct.exists()) return direct;
    final alias = relativePath
        .replaceAll('MOSS-TTS-Nano-ONNX-CPU', 'MOSS-TTS-Nano-100M-ONNX')
        .replaceAll(
          'MOSS-Audio-Tokenizer-Nano-ONNX-CPU',
          'MOSS-Audio-Tokenizer-Nano-ONNX',
        );
    return io.File(p.normalize(p.join(manifestDir.path, alias)));
  }

  static Future<bool> _hasExternalDataFile(io.Directory directory) async {
    if (!await directory.exists()) return false;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is io.File && entity.path.toLowerCase().endsWith('.data')) {
        return true;
      }
    }
    return false;
  }
}

final class MossLocalTtsBackend implements LocalTtsBackend {
  MossLocalTtsBackend({
    MossLocalModelStore? modelStore,
    MossLocalTts nativeBridge = const MossLocalTts(),
    this.voice = 'Junhao',
    this.cpuThreads = 2,
    this.maxFrames = 375,
  }) : modelStore = modelStore ?? MossLocalModelStore(),
       // Keep the public constructor parameter stable while satisfying callers.
       // ignore: prefer_initializing_formals
       _nativeBridge = nativeBridge;

  final MossLocalModelStore modelStore;
  final MossLocalTts _nativeBridge;
  final String voice;
  final int cpuThreads;
  final int maxFrames;

  SentencePieceTokenizer? _tokenizer;
  String? _tokenizerPath;

  @override
  String get id => 'moss-tts-nano-onnx';

  @override
  int get maxCharsPerRequest => 64;

  @override
  Future<bool> isInstalled() => modelStore.isInstalled();

  @override
  Future<bool> isReady() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    if (!await isInstalled()) return false;
    return _nativeBridge.isSupported();
  }

  @override
  Future<LocalTtsAudioResult> synthesize(
    String text, {
    bool Function()? cancelled,
  }) async {
    if (cancelled?.call() == true) {
      throw StateError('Local TTS synthesis cancelled');
    }
    final validation = await modelStore.validate();
    if (!validation.isValid || validation.tokenizerPath == null) {
      throw StateError(
        'MOSS local model is incomplete: ${validation.missingPaths.join(', ')}',
      );
    }
    if (!await _nativeBridge.isSupported()) {
      throw UnsupportedError('MOSS local TTS is only available on Android');
    }

    final tokenizer = _tokenizerFor(validation.tokenizerPath!);
    final encoding = tokenizer.encode(text, addSpecialTokens: false);
    final tokenIds = encoding.ids.toList(growable: false);
    if (tokenIds.isEmpty) {
      throw StateError('MOSS tokenizer produced no text tokens');
    }
    if (cancelled?.call() == true) {
      throw StateError('Local TTS synthesis cancelled');
    }

    final synthesis = await _nativeBridge.synthesize(
      modelRoot: validation.rootPath,
      textTokenIds: tokenIds,
      voice: voice,
      cpuThreads: cpuThreads,
      maxFrames: maxFrames,
    );
    return LocalTtsAudioResult(
      filePath: synthesis.outputPath,
      duration: Duration(milliseconds: synthesis.durationMs),
    );
  }

  SentencePieceTokenizer _tokenizerFor(String path) {
    final cached = _tokenizer;
    if (cached != null && _tokenizerPath == path) return cached;
    final tokenizer = SentencePieceTokenizer.fromModelFileSync(
      path,
      config: const SentencePieceConfig(),
    );
    _tokenizer = tokenizer;
    _tokenizerPath = path;
    return tokenizer;
  }

  @override
  Future<void> unload() async {
    _tokenizer = null;
    _tokenizerPath = null;
    await _nativeBridge.unload();
  }
}
