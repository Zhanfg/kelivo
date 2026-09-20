import '../cache/story_prompt_cache_plan.dart';

enum StoryRegexTarget { userInput, assistantOutput, both }

final class StoryPersona {
  const StoryPersona({
    required this.id,
    required this.name,
    this.description = '',
    this.instructions = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String description;
  final String instructions;
  final bool enabled;

  factory StoryPersona.fromJson(Map<String, dynamic> json) => StoryPersona(
    id: _requiredString(json, 'id'),
    name: _requiredString(json, 'name'),
    description: _string(json['description']),
    instructions: _string(json['instructions']),
    enabled: json['enabled'] != false,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'description': description,
    'instructions': instructions,
    'enabled': enabled,
  };
}

final class StoryQuickReply {
  const StoryQuickReply({
    required this.id,
    required this.label,
    required this.submitText,
    this.enabled = true,
    this.order = 0,
  });

  final String id;
  final String label;
  final String submitText;
  final bool enabled;
  final int order;

  factory StoryQuickReply.fromJson(Map<String, dynamic> json) =>
      StoryQuickReply(
        id: _requiredString(json, 'id'),
        label: _requiredString(json, 'label'),
        submitText: _requiredString(json, 'submitText'),
        enabled: json['enabled'] != false,
        order: _int(json['order']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'label': label,
    'submitText': submitText,
    'enabled': enabled,
    'order': order,
  };
}

final class StoryRegexRule {
  const StoryRegexRule({
    required this.id,
    required this.name,
    required this.pattern,
    this.replacement = '',
    this.target = StoryRegexTarget.both,
    this.enabled = true,
    this.caseSensitive = true,
    this.multiLine = false,
    this.dotAll = false,
    this.order = 0,
  });

  final String id;
  final String name;
  final String pattern;
  final String replacement;
  final StoryRegexTarget target;
  final bool enabled;
  final bool caseSensitive;
  final bool multiLine;
  final bool dotAll;
  final int order;

  factory StoryRegexRule.fromJson(Map<String, dynamic> json) => StoryRegexRule(
    id: _requiredString(json, 'id'),
    name: _requiredString(json, 'name'),
    pattern: _requiredString(json, 'pattern'),
    replacement: _string(json['replacement']),
    target: StoryRegexTarget.values.firstWhere(
      (value) => value.name == _string(json['target']),
      orElse: () => StoryRegexTarget.both,
    ),
    enabled: json['enabled'] != false,
    caseSensitive: json['caseSensitive'] != false,
    multiLine: json['multiLine'] == true,
    dotAll: json['dotAll'] == true,
    order: _int(json['order']),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'pattern': pattern,
    'replacement': replacement,
    'target': target.name,
    'enabled': enabled,
    'caseSensitive': caseSensitive,
    'multiLine': multiLine,
    'dotAll': dotAll,
    'order': order,
  };

  bool appliesTo(StoryRegexTarget requested) =>
      target == StoryRegexTarget.both ||
      requested == StoryRegexTarget.both ||
      target == requested;
}

final class StoryDataBankEntry {
  const StoryDataBankEntry({
    required this.id,
    required this.title,
    required this.content,
    this.keywords = const <String>[],
    this.enabled = true,
    this.alwaysActive = false,
    this.priority = 0,
    this.worldlineIds = const <String>[],
  });

  final String id;
  final String title;
  final String content;
  final List<String> keywords;
  final bool enabled;
  final bool alwaysActive;
  final int priority;

  /// Empty means the entry is visible to every worldline in this Story.
  final List<String> worldlineIds;

  factory StoryDataBankEntry.fromJson(Map<String, dynamic> json) =>
      StoryDataBankEntry(
        id: _requiredString(json, 'id'),
        title: _requiredString(json, 'title'),
        content: _requiredString(json, 'content'),
        keywords: _stringList(json['keywords']),
        enabled: json['enabled'] != false,
        alwaysActive: json['alwaysActive'] == true,
        priority: _int(json['priority']),
        worldlineIds: _stringList(json['worldlineIds']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'content': content,
    'keywords': keywords,
    'enabled': enabled,
    'alwaysActive': alwaysActive,
    'priority': priority,
    'worldlineIds': worldlineIds,
  };
}

final class StoryContextResources {
  const StoryContextResources({
    required this.conversationId,
    this.activePersonaId,
    this.personas = const <StoryPersona>[],
    this.quickReplies = const <StoryQuickReply>[],
    this.regexRules = const <StoryRegexRule>[],
    this.dataBankEntries = const <StoryDataBankEntry>[],
  });

  final String conversationId;
  final String? activePersonaId;
  final List<StoryPersona> personas;
  final List<StoryQuickReply> quickReplies;
  final List<StoryRegexRule> regexRules;
  final List<StoryDataBankEntry> dataBankEntries;

  StoryPersona? get activePersona {
    final id = activePersonaId?.trim();
    if (id == null || id.isEmpty) return null;
    for (final persona in personas) {
      if (persona.id == id && persona.enabled) return persona;
    }
    return null;
  }

  factory StoryContextResources.fromJson(Map<String, dynamic> json) =>
      StoryContextResources(
        conversationId: _requiredString(json, 'conversationId'),
        activePersonaId: _nullableString(json['activePersonaId']),
        personas: _mapList(
          json['personas'],
        ).map(StoryPersona.fromJson).toList(growable: false),
        quickReplies: _mapList(
          json['quickReplies'],
        ).map(StoryQuickReply.fromJson).toList(growable: false),
        regexRules: _mapList(
          json['regexRules'],
        ).map(StoryRegexRule.fromJson).toList(growable: false),
        dataBankEntries: _mapList(
          json['dataBankEntries'],
        ).map(StoryDataBankEntry.fromJson).toList(growable: false),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'conversationId': conversationId,
    'activePersonaId': activePersonaId,
    'personas': personas.map((item) => item.toJson()).toList(),
    'quickReplies': quickReplies.map((item) => item.toJson()).toList(),
    'regexRules': regexRules.map((item) => item.toJson()).toList(),
    'dataBankEntries': dataBankEntries.map((item) => item.toJson()).toList(),
  };
}

final class StoryCompiledContextResources {
  const StoryCompiledContextResources({
    this.stableContributions = const <StoryPromptContribution>[],
    this.volatileContributions = const <StoryPromptContribution>[],
    this.quickReplies = const <StoryQuickReply>[],
    this.regexRules = const <StoryRegexRule>[],
  });

  final List<StoryPromptContribution> stableContributions;
  final List<StoryPromptContribution> volatileContributions;
  final List<StoryQuickReply> quickReplies;
  final List<StoryRegexRule> regexRules;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _nullableString(json[key]);
  if (value == null) {
    throw FormatException('invalid_story_context_resource_$key');
  }
  return value;
}

String _string(Object? value) => value is String ? value.trim() : '';

String? _nullableString(Object? value) {
  final normalized = _string(value);
  return normalized.isEmpty ? null : normalized;
}

int _int(Object? value) => value is num ? value.toInt() : 0;

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return List.unmodifiable(
    value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty),
  );
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}
