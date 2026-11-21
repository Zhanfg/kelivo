import 'dart:convert';

import 'package:Kelivo/core/services/tools/tool_capability_contract.dart';
import 'package:Kelivo/features/home/services/built_in_tool_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final seed = builtInToolCapabilityMatrix;
  final allGrants = ToolPermission.values.toSet();

  test('seed exactly covers the registered client functions', () {
    final diff = seed.checkRegistrations(BuiltInToolNames.functions);
    expect(diff.missingFromMatrix, isEmpty);
    expect(diff.unregistered, isEmpty);
  });

  test('consistency reports missing and stale declarations independently', () {
    final matrix = ToolCapabilityMatrix({'kept': {}, 'stale': {}});
    final diff = matrix.checkRegistrations(['kept', 'new_tool', 'kept']);
    expect(diff.missingFromMatrix, {'new_tool'});
    expect(diff.unregistered, {'stale'});
  });

  const native = {
    'get_time_info',
    'calculate',
    'ask_user_input_v0',
    'read_chat_context',
    'read_file',
    'view_image',
    'write_file',
    'edit_file',
    'list_dir',
    'glob',
    'grep',
  };
  const mobile = {...native, 'text_to_speech', 'browser'};
  const mobileGranted = {
    'calendar_query',
    'calendar_create',
    'get_current_location',
  };
  final cases = {
    ToolPlatform.android: (
      mobile,
      {...mobileGranted, 'phone_control', 'get_screen_time'},
    ),
    ToolPlatform.ios: (
      mobile,
      {
        ...mobileGranted,
        'reminders_query',
        'reminders_create',
        'reminders_complete',
      },
    ),
    ToolPlatform.macos: ({...native, 'browser'}, <String>{}),
    ToolPlatform.windows: ({...native, 'browser'}, <String>{}),
    ToolPlatform.linux: (native, <String>{}),
    ToolPlatform.web: (<String>{}, <String>{}),
  };
  for (final platform in ToolPlatform.values) {
    test('${platform.name} filters the seed before and after grants', () {
      final (always, gated) = cases[platform]!;
      expect(seed.advertisableTools(platform, {}), always);
      expect(seed.advertisableTools(platform, allGrants), {
        ...always,
        ...gated,
      });
    });
  }

  test('Android special access grants enable only their own tool', () {
    const platform = ToolPlatform.android;
    for (final entry in {
      ToolPermission.androidAccessibilityService: 'phone_control',
      ToolPermission.androidUsageAccess: 'get_screen_time',
      ToolPermission.foregroundLocation: 'get_current_location',
    }.entries) {
      final granted = seed.advertisableTools(platform, {entry.key});
      expect(granted.difference(mobile), {entry.value});
    }
  });

  test('a partial Android calendar grant returns a recoverable error', () {
    const platform = ToolPlatform.android;
    const read = ToolPermission.androidReadCalendar;
    const write = ToolPermission.androidWriteCalendar;
    expect(
      seed.advertisableTools(platform, {read}),
      contains('calendar_query'),
    );
    expect(
      seed.advertisableTools(platform, {read}),
      isNot(contains('calendar_create')),
    );
    expect(
      seed.invocationError('calendar_create', platform, {read})!.toJson(),
      {
        'error_code': 'tool_permission_required',
        'tool': 'calendar_create',
        'platform': 'android',
        'recoverable': true,
        'missing_permissions': ['androidWriteCalendar'],
      },
    );
    expect(
      seed
          .invocationError('calendar_create', platform, {})!
          .toJson()['missing_permissions'],
      ['androidReadCalendar', 'androidWriteCalendar'],
    );
    expect(
      seed.invocationError('calendar_create', platform, {write, read}),
      isNull,
    );
    expect(
      seed.advertisableTools(platform, {write, read}),
      contains('calendar_create'),
    );
  });

  test('iOS calendar, reminders and location grants are independent', () {
    final granted = seed.advertisableTools(ToolPlatform.ios, {
      ToolPermission.iosRemindersAccess,
      ToolPermission.foregroundLocation,
      ToolPermission.androidReadCalendar,
      ToolPermission.androidWriteCalendar,
    });
    expect(granted.difference(mobile), {
      'reminders_query',
      'reminders_create',
      'reminders_complete',
      'get_current_location',
    });
    expect(
      seed
          .invocationError('calendar_query', ToolPlatform.ios, {})!
          .missingPermissions,
      {ToolPermission.iosCalendarAccess},
    );
  });

  test(
    'unknown evidence fails closed independently of explicit exclusions',
    () {
      for (final tool in [
        'get_weather',
        'get_health_summary',
        'clipboard_tool',
        'not_registered',
      ]) {
        final error = seed.invocationError(tool, ToolPlatform.ios, allGrants)!;
        expect(error.code, 'tool_availability_unknown');
        expect(error.recoverable, isFalse);
        expect(
          seed.advertisableTools(ToolPlatform.ios, allGrants),
          isNot(contains(tool)),
        );
      }
      expect(
        seed
            .invocationError('get_weather', ToolPlatform.android, allGrants)!
            .code,
        'tool_unavailable',
      );
    },
  );

  test(
    'the matrix round-trips over JSON with the same admission decisions',
    () {
      final wire = jsonDecode(jsonEncode(seed)) as Map<String, dynamic>;
      final restored = ToolCapabilityMatrix.fromJson(wire);
      expect(restored.toJson(), wire);
      expect(wire['tools']['clipboard_tool']['ios'], {
        'availability': 'unknown',
      });
      for (final platform in ToolPlatform.values) {
        for (final grants in [<ToolPermission>{}, allGrants]) {
          expect(
            restored.advertisableTools(platform, grants),
            seed.advertisableTools(platform, grants),
          );
        }
      }
    },
  );

  test('malformed states and permission requirements fail closed', () {
    for (final invalid in [
      {'availability': 'assumeAvailable'},
      {'availability': 'permissionGated'},
      {'availability': 'permissionGated', 'requiredPermissions': []},
      {
        'availability': 'permissionGated',
        'requiredPermissions': ['typo'],
      },
      {
        'availability': 'available',
        'requiredPermissions': ['androidReadCalendar'],
      },
    ]) {
      expect(() => ToolCapability.fromJson(invalid), throwsFormatException);
    }
  });
}
