import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/cache/story_capability_epoch.dart';
import 'package:Kelivo/features/story_runtime/cache/story_prompt_cache_plan.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_analysis_parser.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_analysis_service.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_chunker.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_import_service.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_leak_guard.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_models.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_profile_compiler.dart';
import 'package:Kelivo/features/story_runtime/reference/story_reference_store.dart';

void main() {
  group('Reference text chunking', () {
    test('is deterministic, bounded and paragraph aware', () {
      const chunker = StoryReferenceChunker(
        targetChars: 40,
        maxChars: 60,
        overlapChars: 8,
      );
      const text =
          '第一段有一些文字，用来说明环境。\n\n第二段继续描述人物动作和空间。\n\n第三段负责收束这一小节，并加入新的节奏变化。';

      final first = chunker.chunk(documentId: 'doc-1', text: text);
      final second = chunker.chunk(documentId: 'doc-1', text: text);

      expect(first.map((item) => item.id), second.map((item) => item.id));
      expect(first, isNotEmpty);
      expect(first.every((item) => item.text.length <= 60), isTrue);
    });
  });

  group('Reference analysis parser and leak guard', () {
    const parser = StoryReferenceAnalysisParser();

    test('parses abstract craft dimensions', () {
      final snapshot = parser.parse('''
      {
        "version": 1,
        "language": "zh-CN",
        "aspects": ["prose", "dialogue", "description"],
        "core_traits": ["叙述克制，重要信息延后揭示"],
        "sentence_rhythm": ["短句和中长句交替形成停顿"],
        "dialogue_methods": ["对话留白多于解释"],
        "description_methods": ["先写空间关系，再补局部感官"],
        "metrics": {"dialogue_ratio": 0.35, "sensory_density": 0.62}
      }
      ''');

      expect(snapshot.language, 'zh-CN');
      expect(snapshot.aspects, contains(StoryReferenceAspect.dialogue));
      expect(snapshot.metrics['sensory_density'], 0.62);
    });

    test('rejects copied source wording before profile creation', () {
      const source = '楼道尽头那盏坏掉的灯连续闪了三次，然后彻底熄灭。';
      final snapshot = parser.parse('''
      {
        "version": 1,
        "aspects": ["description"],
        "description_methods": ["楼道尽头那盏坏掉的灯连续闪了三次，然后彻底熄灭。"]
      }
      ''');

      final check = const StoryReferenceLeakGuard().check(
        sourceText: source,
        analysis: snapshot,
      );
      expect(check.blocked, isTrue);
    });
  });

  group('Reference Library import', () {
    late Directory tempDir;
    late _MemoryDocumentRepository documents;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kelivo_reference_test_');
      documents = _MemoryDocumentRepository();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('stores only a relative normalized-text path and deduplicates by hash', () async {
      final service = StoryReferenceImportService(
        repository: documents,
        appDataRootResolver: () async => tempDir,
      );

      final first = await service.importPastedText(
        title: '测试小说',
        text: '第一章\n\n这是用于风格分析的正文。',
      );
      final second = await service.importPastedText(
        title: '另一个标题',
        text: '第一章\n\n这是用于风格分析的正文。',
      );

      expect(first.deduplicated, isFalse);
      expect(second.deduplicated, isTrue);
      expect(second.document.id, first.document.id);
      expect(first.document.normalizedRelativePath, startsWith('story_reference_library/'));
      expect(first.document.normalizedRelativePath, isNot(startsWith(tempDir.path)));
      expect(await service.readNormalizedText(first.document), contains('用于风格分析'));
    });
  });

  group('Callable reference profiles', () {
    const profile = StoryReferenceStyleProfile(
      id: 'style-1',
      documentId: 'doc-1',
      name: '克制悬疑',
      sourceContentHash: 'source-hash',
      createdAtMs: 1,
      aspects: {
        StoryReferenceAspect.prose,
        StoryReferenceAspect.dialogue,
        StoryReferenceAspect.description,
        StoryReferenceAspect.romanceIntimacy,
      },
      coreTraits: ['信息延迟揭示，避免一次解释完整'],
      sentenceRhythm: ['紧张处缩短句长，缓冲段恢复中长句'],
      dialogueMethods: ['对话保留潜台词，不替角色解释情绪'],
      descriptionMethods: ['先确定空间关系，再选少量感官细节'],
      intimacyMethods: ['以关系和情绪推进为主，控制感官细节密度'],
      metrics: {'dialogue_ratio': 0.4},
    );

    test('compiler emits only selected abstract aspects', () {
      final compiled = const StoryReferenceProfileCompiler().compile(
        profiles: const [profile],
        invocations: const [
          StoryReferenceInvocation(
            profileId: 'style-1',
            strength: 0.7,
            enabledAspects: {
              StoryReferenceAspect.dialogue,
              StoryReferenceAspect.description,
            },
          ),
        ],
      );

      final contribution = compiled.single.contribution;
      expect(contribution.stability, StoryPromptStability.epochStable);
      expect(contribution.content, contains('DIALOGUE:'));
      expect(contribution.content, contains('DESCRIPTION:'));
      expect(contribution.content, isNot(contains('MATURE_RELATIONSHIP_CRAFT:')));
      expect(contribution.content, contains('Produce original prose'));
    });

    test('turn-scoped reference is volatile rather than cache-stable', () {
      final compiled = const StoryReferenceProfileCompiler().compile(
        profiles: const [profile],
        invocations: const [
          StoryReferenceInvocation(profileId: 'style-1', turnScoped: true),
        ],
      );
      expect(
        compiled.single.contribution.stability,
        StoryPromptStability.volatile,
      );
    });

    test('reference invocation change rolls capability epoch', () {
      const compiler = StoryReferenceProfileCompiler();
      final first = compiler.compile(
        profiles: const [profile],
        invocations: const [
          StoryReferenceInvocation(profileId: 'style-1', strength: 0.5),
        ],
      );
      final second = compiler.compile(
        profiles: const [profile],
        invocations: const [
          StoryReferenceInvocation(profileId: 'style-1', strength: 0.8),
        ],
      );
      final epochA = StoryCapabilityEpoch.canonical(
        epochId: 'a',
        worldlineId: 'wl',
        sceneEpochId: 'scene',
        referenceProfileFingerprints: [first.single.fingerprint],
      );
      final epochB = StoryCapabilityEpoch.canonical(
        epochId: 'b',
        worldlineId: 'wl',
        sceneEpochId: 'scene',
        referenceProfileFingerprints: [second.single.fingerprint],
      );

      expect(epochA.canReuseStablePrefixWith(epochB), isFalse);
    });
  });

  test('analysis pipeline reduces chunks and persists one profile', () async {
    final documents = _MemoryDocumentRepository();
    final profiles = _MemoryProfileRepository();
    final tempDir = await Directory.systemTemp.createTemp('kelivo_reference_analysis_');
    addTearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    final importService = StoryReferenceImportService(
      repository: documents,
      appDataRootResolver: () async => tempDir,
    );
    final imported = await importService.importPastedText(
      title: '长文本',
      text: List.filled(
        12,
        '场景在变化，人物通过动作和停顿推进交流，环境细节保持简洁。',
      ).join('\n\n'),
    );
    final source = await importService.readNormalizedText(imported.document);
    var analysisCalls = 0;
    var reduceCalls = 0;
    final service = StoryReferenceAnalysisService(
      chunker: const StoryReferenceChunker(
        targetChars: 80,
        maxChars: 120,
        overlapChars: 0,
      ),
      reductionBatchSize: 2,
    );

    final profile = await service.analyzeAndSave(
      document: imported.document,
      sourceText: source,
      profileRepository: profiles,
      runModel: (request) async {
        if (request.stage == StoryReferenceAnalysisStage.analyzeChunk) {
          analysisCalls++;
        } else {
          reduceCalls++;
        }
        return '''
        {
          "version": 1,
          "language": "zh-CN",
          "aspects": ["prose", "dialogue", "pacing"],
          "core_traits": ["叙述保持克制并逐步增加信息"],
          "sentence_rhythm": ["句长随紧张度变化"],
          "dialogue_methods": ["对话依靠停顿和潜台词推进"],
          "pacing_methods": ["场景转折前缩短信息释放间隔"],
          "metrics": {"dialogue_ratio": 0.4}
        }
        ''';
      },
    );

    expect(analysisCalls, greaterThan(1));
    expect(reduceCalls, greaterThan(0));
    expect(profile.documentId, imported.document.id);
    expect((await profiles.readAll()).single.id, profile.id);
  });
}

final class _MemoryDocumentRepository
    implements StoryReferenceDocumentRepository {
  final List<StoryReferenceDocument> items = <StoryReferenceDocument>[];

  @override
  Future<List<StoryReferenceDocument>> readAll() async => List.unmodifiable(items);

  @override
  Future<StoryReferenceDocument?> readById(String id) async {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<StoryReferenceDocument?> findByContentHash(String contentHash) async {
    for (final item in items) {
      if (item.contentHash == contentHash) return item;
    }
    return null;
  }

  @override
  Future<void> upsert(StoryReferenceDocument document) async {
    items.removeWhere((item) => item.id == document.id);
    items.add(document);
  }

  @override
  Future<void> remove(String id) async {
    items.removeWhere((item) => item.id == id);
  }
}

final class _MemoryProfileRepository
    implements StoryReferenceProfileRepository {
  final List<StoryReferenceStyleProfile> items = <StoryReferenceStyleProfile>[];

  @override
  Future<List<StoryReferenceStyleProfile>> readAll() async => List.unmodifiable(items);

  @override
  Future<StoryReferenceStyleProfile?> readById(String id) async {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<List<StoryReferenceStyleProfile>> readForDocument(String documentId) async =>
      List.unmodifiable(items.where((item) => item.documentId == documentId));

  @override
  Future<void> upsert(StoryReferenceStyleProfile profile) async {
    items.removeWhere((item) => item.id == profile.id);
    items.add(profile);
  }

  @override
  Future<void> remove(String id) async {
    items.removeWhere((item) => item.id == id);
  }
}
