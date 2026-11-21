/// Static platform and permission eligibility for built-in client functions.
/// Callers intersect this set with their model, assistant and conversation
/// registrations. Invocation still observes live service state and approvals.
library;

enum ToolPlatform { android, ios, macos, windows, linux, web }

enum ToolAvailability { available, unavailable, permissionGated, unknown }

/// Effective grants supplied by the host. Enum names are the wire IDs.
enum ToolPermission {
  /// Usage Access for this app (Android PACKAGE_USAGE_STATS app-op).
  androidUsageAccess,

  /// Kelivo's phone control Accessibility service is enabled.
  androidAccessibilityService,
  androidReadCalendar,
  androidWriteCalendar,

  /// EventKit calendar access (full access on iOS 17+).
  iosCalendarAccess,
  iosRemindersAccess,

  /// Coarse or fine on Android, when-in-use or always on iOS.
  foregroundLocation,
}

T _decodeEnum<T extends Enum>(List<T> values, Object? raw) => values.firstWhere(
  (value) => value.name == raw,
  orElse: () => throw FormatException('Unknown $T value: $raw'),
);

final class ToolCapability {
  const ToolCapability._(this.availability) : requiredPermissions = const {};

  static const available = ToolCapability._(ToolAvailability.available);
  static const unavailable = ToolCapability._(ToolAvailability.unavailable);
  static const unknown = ToolCapability._(ToolAvailability.unknown);

  ToolCapability.permissionGated(Set<ToolPermission> permissions)
    : availability = ToolAvailability.permissionGated,
      requiredPermissions = Set.unmodifiable(permissions) {
    if (permissions.isEmpty) {
      throw const FormatException('A permission-gated tool requires a grant');
    }
  }

  final ToolAvailability availability;
  final Set<ToolPermission> requiredPermissions;

  Map<String, dynamic> toJson() => {
    'availability': availability.name,
    if (requiredPermissions.isNotEmpty)
      'requiredPermissions': _permissionIds(requiredPermissions),
  };

  factory ToolCapability.fromJson(Map<String, dynamic> json) {
    final state = _decodeEnum(ToolAvailability.values, json['availability']);
    final permissions = json['requiredPermissions'];
    if (state == ToolAvailability.permissionGated) {
      if (permissions is! List) {
        throw const FormatException('Expected requiredPermissions list');
      }
      return ToolCapability.permissionGated({
        for (final permission in permissions)
          _decodeEnum(ToolPermission.values, permission),
      });
    }
    if (permissions != null && !(permissions is List && permissions.isEmpty)) {
      throw const FormatException('Permissions require permissionGated state');
    }
    return ToolCapability._(state);
  }
}

List<String> _permissionIds(Set<ToolPermission> permissions) =>
    [for (final permission in permissions) permission.name]..sort();

/// A permission denial can be retried after granting all [missingPermissions].
final class ToolCapabilityError {
  const ToolCapabilityError._(
    this.tool,
    this.platform,
    this.code, [
    this.missingPermissions = const {},
  ]);

  final String tool;
  final ToolPlatform platform;
  final String code;
  final Set<ToolPermission> missingPermissions;

  bool get recoverable => missingPermissions.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'error_code': code,
    'tool': tool,
    'platform': platform.name,
    'recoverable': recoverable,
    if (recoverable) 'missing_permissions': _permissionIds(missingPermissions),
  };
}

final class ToolCapabilityMatrix {
  ToolCapabilityMatrix(Map<String, Map<ToolPlatform, ToolCapability>> tools)
    : tools = Map.unmodifiable({
        for (final entry in tools.entries)
          entry.key: Map<ToolPlatform, ToolCapability>.unmodifiable({
            for (final platform in ToolPlatform.values)
              platform: entry.value[platform] ?? ToolCapability.unknown,
          }),
      });

  final Map<String, Map<ToolPlatform, ToolCapability>> tools;

  /// An omitted platform or an unregistered name has unknown availability.
  ToolCapability capabilityFor(String tool, ToolPlatform platform) =>
      tools[tool]?[platform] ?? ToolCapability.unknown;

  /// Returns null when the call passes the platform and permission checks.
  ToolCapabilityError? invocationError(
    String tool,
    ToolPlatform platform,
    Set<ToolPermission> grantedPermissions,
  ) {
    final capability = capabilityFor(tool, platform);
    switch (capability.availability) {
      case ToolAvailability.available:
        return null;
      case ToolAvailability.unavailable:
        return ToolCapabilityError._(tool, platform, 'tool_unavailable');
      case ToolAvailability.unknown:
        return ToolCapabilityError._(
          tool,
          platform,
          'tool_availability_unknown',
        );
      case ToolAvailability.permissionGated:
        final missing = capability.requiredPermissions.difference(
          grantedPermissions,
        );
        if (missing.isEmpty) return null;
        return ToolCapabilityError._(
          tool,
          platform,
          'tool_permission_required',
          Set.unmodifiable(missing),
        );
    }
  }

  Set<String> advertisableTools(
    ToolPlatform platform,
    Set<ToolPermission> grantedPermissions,
  ) => {
    for (final tool in tools.keys)
      if (invocationError(tool, platform, grantedPermissions) == null) tool,
  };

  ({Set<String> missingFromMatrix, Set<String> unregistered})
  checkRegistrations(Iterable<String> registrations) {
    final registered = registrations.toSet();
    final declared = tools.keys.toSet();
    return (
      missingFromMatrix: registered.difference(declared),
      unregistered: declared.difference(registered),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'tools': {
      for (final tool in tools.entries)
        tool.key: {
          for (final cell in tool.value.entries)
            cell.key.name: cell.value.toJson(),
        },
    },
  };

  factory ToolCapabilityMatrix.fromJson(Map<String, dynamic> json) {
    final tools = json['tools'];
    if (json['schemaVersion'] != 1 || tools is! Map<String, dynamic>) {
      throw const FormatException('Expected a v1 tool capability matrix');
    }
    final rows = <String, Map<ToolPlatform, ToolCapability>>{};
    for (final entry in tools.entries) {
      final cells = entry.value;
      if (cells is! Map<String, dynamic>) {
        throw FormatException('Expected platform entries for ${entry.key}');
      }
      final row = <ToolPlatform, ToolCapability>{};
      for (final cell in cells.entries) {
        final data = cell.value;
        if (data is! Map<String, dynamic>) {
          throw FormatException(
            'Expected capability for ${entry.key}/${cell.key}',
          );
        }
        row[_decodeEnum(ToolPlatform.values, cell.key)] =
            ToolCapability.fromJson(data);
      }
      rows[entry.key] = row;
    }
    return ToolCapabilityMatrix(rows);
  }
}

/// Matches BuiltInToolNames.functions, including both memory modes.
/// Keep the names independent of the registry so its additions and removals
/// surface in the registration consistency test.
final builtInToolCapabilityMatrix = _buildSeed();

ToolCapabilityMatrix _buildSeed() {
  const available = ToolCapability.available;
  const unknown = ToolCapability.unknown;
  const unavailable = ToolCapability.unavailable;
  const android = ToolPlatform.android;
  const ios = ToolPlatform.ios;
  const native = {
    android: available,
    ios: available,
    ToolPlatform.macos: available,
    ToolPlatform.windows: available,
    ToolPlatform.linux: available,
  };
  // LocalToolsService has explicit allowlists for device tools and browser.
  final unsupported = {for (final p in ToolPlatform.values) p: unavailable};
  final location = ToolCapability.permissionGated({
    ToolPermission.foregroundLocation,
  });
  final iosCalendar = ToolCapability.permissionGated({
    ToolPermission.iosCalendarAccess,
  });
  final iosReminders = ToolCapability.permissionGated({
    ToolPermission.iosRemindersAccess,
  });
  return ToolCapabilityMatrix({
    // Portable Dart time/calculation and the shared Flutter interaction card.
    'get_time_info': native,
    'calculate': native,
    'ask_user_input_v0': native,
    // Flutter Clipboard delegates to the host without a platform support test.
    'clipboard_tool': {},
    // The bundled flutter_tts plugin registers Android and iOS. Other hosts
    // depend on the selected playback backend.
    'text_to_speech': {android: available, ios: available},
    'phone_control': {
      ...unsupported,
      android: ToolCapability.permissionGated({
        ToolPermission.androidAccessibilityService,
      }),
    },
    'get_screen_time': {
      ...unsupported,
      android: ToolCapability.permissionGated({
        ToolPermission.androidUsageAccess,
      }),
    },
    // DeviceLocalToolsHandler.kt uses different permissions for query/create.
    'calendar_query': {
      ...unsupported,
      android: ToolCapability.permissionGated({
        ToolPermission.androidReadCalendar,
      }),
      ios: iosCalendar,
    },
    'calendar_create': {
      ...unsupported,
      android: ToolCapability.permissionGated({
        ToolPermission.androidReadCalendar,
        ToolPermission.androidWriteCalendar,
      }),
      ios: iosCalendar,
    },
    'get_current_location': {...unsupported, android: location, ios: location},
    for (final tool in [
      'reminders_query',
      'reminders_create',
      'reminders_complete',
    ])
      tool: {...unsupported, ios: iosReminders},
    // WeatherKit needs iOS 16+. Explicit coordinates need no location grant.
    // HealthKit requires a device probe and hides per-type read authorization.
    for (final tool in ['get_weather', 'get_health_summary'])
      tool: {...unsupported, ios: unknown},
    'browser': {
      ...unsupported,
      android: available,
      ios: available,
      ToolPlatform.macos: available,
      ToolPlatform.windows: available,
    },
    // WorkspaceToolsService uses host file operations on the five native
    // targets. Shell also requires a ready runtime (PRoot, iSH or desktop).
    for (final tool in [
      'read_file',
      'view_image',
      'write_file',
      'edit_file',
      'list_dir',
      'glob',
      'grep',
    ])
      tool: native,
    'shell': {ToolPlatform.web: unavailable},
    // The context reader operates on messages supplied by the conversation.
    'read_chat_context': native,
    // Search and memory registration depends on settings, with no per-OS
    // availability declaration for the configured backend.
    for (final tool in [
      'search_web',
      'fetch_url',
      'memory_read',
      'memory_update',
      'memory_search_profile',
      'memory_edit',
      'memory_delete',
      'update_user_profile',
      'chat_search',
      'create_memory',
      'edit_memory',
      'delete_memory',
    ])
      tool: {},
  });
}
