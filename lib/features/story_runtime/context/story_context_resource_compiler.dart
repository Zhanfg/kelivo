import '../cache/story_prompt_cache_plan.dart';
import 'story_context_resources.dart';

final class StoryContextResourceCompiler {
  const StoryContextResourceCompiler({this.maxKeywordEntries = 12});

  final int maxKeywordEntries;

  StoryCompiledContextResources compile({
    required StoryContextResources resources,
    required String turnText,
    required String worldlineId,
  }) {
    final stable = <StoryPromptContribution>[];
    final volatile = <StoryPromptContribution>[];

    final persona = resources.activePersona;
    if (persona != null) {
      stable.add(
        StoryPromptContribution(
          id: 'story.context.persona',
          stability: StoryPromptStability.epochStable,
          order: 320,
          content: _personaText(persona),
        ),
      );
    }

    final visibleEntries = resources.dataBankEntries
        .where((entry) => _visibleToWorldline(entry, worldlineId))
        .toList(growable: false);

    final alwaysActive =
        visibleEntries
            .where((entry) => entry.enabled && entry.alwaysActive)
            .toList(growable: false)
          ..sort(_compareDataBankEntries);
    if (alwaysActive.isNotEmpty) {
      stable.add(
        StoryPromptContribution(
          id: 'story.context.databank.always',
          stability: StoryPromptStability.epochStable,
          order: 340,
          content: _dataBankText(alwaysActive),
        ),
      );
    }

    final normalizedTurn = turnText.toLowerCase();
    final keywordMatches =
        visibleEntries
            .where(
              (entry) =>
                  entry.enabled &&
                  !entry.alwaysActive &&
                  entry.keywords.isNotEmpty &&
                  entry.keywords.any(
                    (keyword) => normalizedTurn.contains(keyword.toLowerCase()),
                  ),
            )
            .toList(growable: false)
          ..sort(_compareDataBankEntries);
    final limited = keywordMatches
        .take(maxKeywordEntries)
        .toList(growable: false);
    if (limited.isNotEmpty) {
      volatile.add(
        StoryPromptContribution(
          id: 'story.context.databank.keyword',
          stability: StoryPromptStability.volatile,
          order: 830,
          content: _dataBankText(limited),
        ),
      );
    }

    final quickReplies =
        resources.quickReplies
            .where((item) => item.enabled)
            .toList(growable: false)
          ..sort((a, b) {
            final order = a.order.compareTo(b.order);
            return order != 0 ? order : a.id.compareTo(b.id);
          });

    final regexRules =
        resources.regexRules
            .where((item) => item.enabled)
            .toList(growable: false)
          ..sort((a, b) {
            final order = a.order.compareTo(b.order);
            return order != 0 ? order : a.id.compareTo(b.id);
          });

    return StoryCompiledContextResources(
      stableContributions: List.unmodifiable(stable),
      volatileContributions: List.unmodifiable(volatile),
      quickReplies: List.unmodifiable(quickReplies),
      regexRules: List.unmodifiable(regexRules),
    );
  }

  String applyRegex(
    String input, {
    required StoryRegexTarget target,
    required Iterable<StoryRegexRule> rules,
  }) {
    var output = input;
    for (final rule in rules) {
      if (!rule.enabled || !rule.appliesTo(target)) continue;
      try {
        final expression = RegExp(
          rule.pattern,
          caseSensitive: rule.caseSensitive,
          multiLine: rule.multiLine,
          dotAll: rule.dotAll,
        );
        output = output.replaceAll(expression, rule.replacement);
      } on FormatException {
        // A malformed imported rule must not break message generation.
      }
    }
    return output;
  }
}

bool _visibleToWorldline(StoryDataBankEntry entry, String worldlineId) {
  if (!entry.enabled) return false;
  if (entry.worldlineIds.isEmpty) return true;
  return entry.worldlineIds.contains(worldlineId);
}

int _compareDataBankEntries(StoryDataBankEntry a, StoryDataBankEntry b) {
  final priority = b.priority.compareTo(a.priority);
  return priority != 0 ? priority : a.id.compareTo(b.id);
}

String _personaText(StoryPersona persona) {
  final buffer = StringBuffer('[STORY_PERSONA]\n');
  buffer.writeln('name=${persona.name}');
  if (persona.description.isNotEmpty) {
    buffer.writeln('description=${persona.description}');
  }
  if (persona.instructions.isNotEmpty) {
    buffer.writeln('instructions=${persona.instructions}');
  }
  buffer.write('[/STORY_PERSONA]');
  return buffer.toString();
}

String _dataBankText(List<StoryDataBankEntry> entries) {
  final buffer = StringBuffer('[STORY_DATA_BANK]\n');
  for (final entry in entries) {
    buffer.writeln('## ${entry.title}');
    buffer.writeln(entry.content.trim());
  }
  buffer.write('[/STORY_DATA_BANK]');
  return buffer.toString();
}
