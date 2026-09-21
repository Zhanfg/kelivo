import 'package:flutter/foundation.dart';

import '../../../core/database/business_preferences.dart';

enum AgentPermissionMode { ask, auto, planFirst, readOnly }

extension AgentPermissionModeCodec on AgentPermissionMode {
  static AgentPermissionMode fromStorage(String? value) {
    return AgentPermissionMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AgentPermissionMode.ask,
    );
  }
}

class AgentSettingsProvider extends ChangeNotifier {
  AgentSettingsProvider({required this.preferences}) {
    loaded = _load();
  }

  static const String permissionModeKey = 'agent_permission_mode_v1';
  static const String showToolOutputKey = 'agent_show_tool_output_v1';

  final BusinessPreferences preferences;
  late final Future<void> loaded;

  AgentPermissionMode _permissionMode = AgentPermissionMode.ask;
  bool _showToolOutput = true;

  AgentPermissionMode get permissionMode => _permissionMode;
  bool get showToolOutput => _showToolOutput;

  Future<void> _load() async {
    if (!preferences.isLoaded) await preferences.load();
    _permissionMode = AgentPermissionModeCodec.fromStorage(
      preferences.getString(permissionModeKey),
    );
    _showToolOutput = preferences.getBool(showToolOutputKey) ?? true;
    notifyListeners();
  }

  Future<void> setPermissionMode(AgentPermissionMode mode) async {
    await loaded;
    if (_permissionMode == mode) return;
    await preferences.setString(permissionModeKey, mode.name);
    _permissionMode = mode;
    notifyListeners();
  }

  Future<void> setShowToolOutput(bool value) async {
    await loaded;
    if (_showToolOutput == value) return;
    await preferences.setBool(showToolOutputKey, value);
    _showToolOutput = value;
    notifyListeners();
  }
}
