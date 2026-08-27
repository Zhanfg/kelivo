final class StoryMcpProfile {
  const StoryMcpProfile({
    required this.id,
    required this.name,
    this.serverIds = const <String>[],
    this.toolNames = const <String>[],
    this.includeAssistantDefaults = false,
    this.requireApproval = true,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String name;
  final List<String> serverIds;
  final List<String> toolNames;

  /// When true, tools already selected on the Assistant remain available in
  /// addition to this profile. When false, Story Mode exposes only this
  /// profile's allow-list.
  final bool includeAssistantDefaults;

  /// Story never bypasses Kelivo approval. This flag is descriptive policy for
  /// diagnostics/UI and may only tighten approval, never disable a native gate.
  final bool requireApproval;
  final Map<String, Object?> metadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'serverIds': serverIds,
    'toolNames': toolNames,
    'includeAssistantDefaults': includeAssistantDefaults,
    'requireApproval': requireApproval,
    'metadata': metadata,
  };

  factory StoryMcpProfile.fromJson(Map<String, dynamic> json) => StoryMcpProfile(
    id: (json['id'] as String).trim(),
    name: (json['name'] as String? ?? 'MCP Profile').trim(),
    serverIds: _stringList(json['serverIds']),
    toolNames: _stringList(json['toolNames']),
    includeAssistantDefaults: json['includeAssistantDefaults'] == true,
    requireApproval: json['requireApproval'] != false,
    metadata: Map<String, Object?>.from(
      (json['metadata'] as Map?) ?? const <String, Object?>{},
    ),
  );
}

final class StoryMcpProfileSelection {
  const StoryMcpProfileSelection({
    required this.conversationId,
    this.profileId,
  });

  final String conversationId;
  final String? profileId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'conversationId': conversationId,
    if (profileId != null) 'profileId': profileId,
  };

  factory StoryMcpProfileSelection.fromJson(Map<String, dynamic> json) =>
      StoryMcpProfileSelection(
        conversationId: (json['conversationId'] as String).trim(),
        profileId: _optionalString(json['profileId']),
      );
}

final class StoryMcpExposurePolicy {
  const StoryMcpExposurePolicy({
    required this.profileId,
    required this.allowedToolNames,
    required this.allowedServerIds,
    required this.includeAssistantDefaults,
    required this.requireApproval,
  });

  final String profileId;
  final Set<String> allowedToolNames;
  final Set<String> allowedServerIds;
  final bool includeAssistantDefaults;
  final bool requireApproval;
}

List<String> _stringList(Object? value) => value is List
    ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false)
    : const <String>[];

String? _optionalString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
