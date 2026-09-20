import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/cache/story_prompt_cache_plan.dart';
import 'package:Kelivo/features/story_runtime/context/story_context_resource_compiler.dart';
import 'package:Kelivo/features/story_runtime/context/story_context_resources.dart';

void main() {
  const compiler = StoryContextResourceCompiler();

  test('persona and always-active data bank become epoch-stable context', () {
    const resources = StoryContextResources(
      conversationId: 'conv-1',
      activePersonaId: 'persona-1',
      personas: [
        StoryPersona(
          id: 'persona-1',
          name: 'Self',
          description: 'Careful observer',
          instructions: 'Keep the user in second person.',
        ),
      ],
      dataBankEntries: [
        StoryDataBankEntry(
          id: 'always',
          title: 'World rule',
          content: 'The station is under quarantine.',
          alwaysActive: true,
        ),
      ],
    );

    final result = compiler.compile(
      resources: resources,
      turnText: 'Look around.',
      worldlineId: 'wl-main',
    );

    expect(result.stableContributions, hasLength(2));
    expect(
      result.stableContributions.map((item) => item.stability),
      everyElement(StoryPromptStability.epochStable),
    );
    expect(
      result.stableContributions.first.content,
      contains('Keep the user in second person.'),
    );
    expect(
      result.stableContributions.last.content,
      contains('station is under quarantine'),
    );
  });

  test('keyword data bank activation is turn-scoped and worldline-aware', () {
    const resources = StoryContextResources(
      conversationId: 'conv-1',
      dataBankEntries: [
        StoryDataBankEntry(
          id: 'red-key',
          title: 'Red key',
          content: 'The red key opens the archive.',
          keywords: ['red key'],
          worldlineIds: ['wl-main'],
        ),
        StoryDataBankEntry(
          id: 'sibling-only',
          title: 'Sibling fact',
          content: 'This fact belongs to another branch.',
          keywords: ['red key'],
          worldlineIds: ['wl-sibling'],
        ),
      ],
    );

    final result = compiler.compile(
      resources: resources,
      turnText: 'I inspect the red key.',
      worldlineId: 'wl-main',
    );

    expect(result.volatileContributions, hasLength(1));
    expect(
      result.volatileContributions.single.content,
      contains('red key opens the archive'),
    );
    expect(
      result.volatileContributions.single.content,
      isNot(contains('another branch')),
    );
  });

  test('quick replies are ordered and disabled replies stay hidden', () {
    const resources = StoryContextResources(
      conversationId: 'conv-1',
      quickReplies: [
        StoryQuickReply(id: 'b', label: 'B', submitText: 'B', order: 20),
        StoryQuickReply(id: 'a', label: 'A', submitText: 'A', order: 10),
        StoryQuickReply(
          id: 'off',
          label: 'Off',
          submitText: 'Off',
          enabled: false,
        ),
      ],
    );

    final result = compiler.compile(
      resources: resources,
      turnText: '',
      worldlineId: 'wl-main',
    );

    expect(result.quickReplies.map((item) => item.id), ['a', 'b']);
  });

  test('regex engine applies matching targets and skips malformed imports', () {
    const rules = [
      StoryRegexRule(
        id: 'user',
        name: 'Normalize',
        pattern: r'\s+',
        replacement: ' ',
        target: StoryRegexTarget.userInput,
      ),
      StoryRegexRule(
        id: 'bad',
        name: 'Broken import',
        pattern: '[',
        replacement: '',
        target: StoryRegexTarget.userInput,
      ),
    ];

    expect(
      compiler.applyRegex(
        'hello   world',
        target: StoryRegexTarget.userInput,
        rules: rules,
      ),
      'hello world',
    );
    expect(
      compiler.applyRegex(
        'hello   world',
        target: StoryRegexTarget.assistantOutput,
        rules: rules,
      ),
      'hello   world',
    );
  });

  test('resources JSON round-trip preserves all SillyTavern-style primitives', () {
    const source = StoryContextResources(
      conversationId: 'conv-1',
      activePersonaId: 'p',
      personas: [StoryPersona(id: 'p', name: 'Persona')],
      quickReplies: [StoryQuickReply(id: 'q', label: 'Go', submitText: 'Go')],
      regexRules: [
        StoryRegexRule(id: 'r', name: 'Rule', pattern: 'x', replacement: 'y'),
      ],
      dataBankEntries: [
        StoryDataBankEntry(
          id: 'd',
          title: 'Lore',
          content: 'Fact',
          keywords: ['fact'],
        ),
      ],
    );

    final restored = StoryContextResources.fromJson(source.toJson());

    expect(restored.conversationId, 'conv-1');
    expect(restored.activePersona?.id, 'p');
    expect(restored.quickReplies.single.submitText, 'Go');
    expect(restored.regexRules.single.replacement, 'y');
    expect(restored.dataBankEntries.single.keywords, ['fact']);
  });
}
