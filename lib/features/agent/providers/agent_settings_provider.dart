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
  static const String maxParallelAgentsKey = 'agent_max_parallel_agents_v1';
  static const String subagentIsolationKey = 'agent_subagent_isolation_v1';
  static const String modelProviderKey = 'agent_model_provider_v1';
  static const String modelIdKey = 'agent_model_id_v1';

  final BusinessPreferences preferences;
  late final Future<void> loaded;

  AgentPermissionMode _permissionMode = AgentPermissionMode.ask;
  bool _showToolOutput = true;
  int _maxParallelAgents = 3;
  bool _subagentIsolation = true;
  String? _modelProvider;
  String? _modelId;

  AgentPermissionMode get permissionMode => _permissionMode;
  bool get showToolOutput => _showToolOutput;
  int get maxParallelAgents => _maxParallelAgents;
  bool get subagentIsolation => _subagentIsolation;
  String? get modelProvider => _modelProvider;
  String? get modelId => _modelId;
  bool get hasModelOverride =>
      (_modelProvider?.isNotEmpty ?? false) && (_modelId?.isNotEmpty ?? false);

  Future<void> _load() async {
    if (!preferences.isLoaded) await preferences.load();
    _permissionMode = AgentPermissionModeCodec.fromStorage(
      preferences.getString(permissionModeKey),
    );
    _showToolOutput = preferences.getBool(showToolOutputKey) ?? true;
    _maxParallelAgents =
        (preferences.getInt(maxParallelAgentsKey) ?? 3).clamp(1, 4);
    _subagentIsolation =
        preferences.getBool(subagentIsolationKey) ?? true;
    _modelProvider = preferences.getString(modelProviderKey);
    _modelId = preferences.getString(modelIdKey);
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

  Future<void> setMaxParallelAgents(int value) async {
    await loaded;
    final next = value.clamp(1, 4);
    if (_maxParallelAgents == next) return;
    await preferences.setInt(maxParallelAgentsKey, next);
    _maxParallelAgents = next;
    notifyListeners();
  }

  Future<void> setSubagentIsolation(bool value) async {
    await loaded;
    if (_subagentIsolation == value) return;
    await preferences.setBool(subagentIsolationKey, value);
    _subagentIsolation = value;
    notifyListeners();
  }

  Future<void> setModel(String providerKey, String modelId) async {
    await loaded;
    _modelProvider = providerKey;
    _modelId = modelId;
    await preferences.setString(AgentSettingsProvider.modelProviderKey, providerKey);
    await preferences.setString(AgentSettingsProvider.modelIdKey, modelId);
    notifyListeners();
  }

  Future<void> clearModelOverride() async {
    await loaded;
    _modelProvider = null;
    _modelId = null;
    await preferences.remove(AgentSettingsProvider.modelProviderKey);
    await preferences.remove(AgentSettingsProvider.modelIdKey);
    notifyListeners();
  }
}
