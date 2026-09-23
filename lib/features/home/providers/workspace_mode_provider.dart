import 'package:flutter/foundation.dart';

import '../../../core/database/business_preferences.dart';
import '../models/workspace_mode.dart';

class WorkspaceModeProvider extends ChangeNotifier {
  WorkspaceModeProvider({required this.preferences}) {
    loaded = _load();
  }

  static const String preferenceKey = 'workspace_mode_selected_v1';

  /// Compatibility key used by the existing Story branch. Reading it here
  /// makes the future Story + Agent merge preserve the user's selected mode.
  static const String legacyStorySelectedKey = 'story_workspace_selected_v1';

  final BusinessPreferences preferences;
  WorkspaceMode _mode = WorkspaceMode.chat;
  bool _busy = false;

  late final Future<void> loaded;

  WorkspaceMode get mode => _mode;
  bool get busy => _busy;

  Future<void> _load() async {
    await preferences.load();
    final stored = preferences.getString(preferenceKey);
    if (stored != null && stored.isNotEmpty) {
      _mode = WorkspaceModeCodec.fromStorage(stored);
    } else if (preferences.getBool(legacyStorySelectedKey) == true) {
      _mode = WorkspaceMode.story;
    }
    notifyListeners();
  }

  Future<void> setMode(WorkspaceMode mode) async {
    await loaded;
    if (_busy || mode == _mode) return;
    _busy = true;
    notifyListeners();
    try {
      await preferences.setString(preferenceKey, mode.name);
      _mode = mode;
      notifyListeners();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
