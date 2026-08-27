import 'package:flutter/foundation.dart';

import '../agency/story_agency_policy.dart';
import 'story_runtime_state.dart';
import 'story_runtime_store.dart';

/// UI-facing controller for the currently attached conversation's Story Mode.
///
/// Conversation switches are generation-token guarded so a slow storage read
/// from an older conversation cannot overwrite the newly selected state.
final class StoryRuntimeController extends ChangeNotifier {
  StoryRuntimeController({required StoryRuntimeStore store}) : _store = store;

  final StoryRuntimeStore _store;

  StoryRuntimeSessionState? _state;
  String? _attachedConversationId;
  bool _loading = false;
  int _loadGeneration = 0;

  StoryRuntimeSessionState? get state => _state;
  String? get attachedConversationId => _attachedConversationId;
  bool get isLoading => _loading;
  bool get isEnabled => _state?.enabled ?? false;
  StoryAgencyMode get agencyMode =>
      _state?.agencyMode ?? StoryAgencyMode.balanced;

  Future<void> attachConversation(String? conversationId) async {
    final normalized = conversationId?.trim();
    final generation = ++_loadGeneration;

    if (normalized == null || normalized.isEmpty) {
      _attachedConversationId = null;
      _state = null;
      _loading = false;
      notifyListeners();
      return;
    }

    _attachedConversationId = normalized;
    _loading = true;
    notifyListeners();

    final loaded = await _store.readOrDefault(normalized);
    if (generation != _loadGeneration ||
        _attachedConversationId != normalized) {
      return;
    }

    _state = loaded;
    _loading = false;
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    final current = _requireState();
    if (current.enabled == enabled) return;
    await _replaceState(current.copyWith(enabled: enabled));
  }

  Future<void> setAgencyMode(StoryAgencyMode mode) async {
    final current = _requireState();
    if (current.agencyMode == mode) return;
    await _replaceState(current.copyWith(agencyMode: mode));
  }

  /// Starts or updates a cache-stable scene epoch. The actual scene snapshot is
  /// stored by the future world runtime; this lightweight state only tracks the
  /// current identity/revision required by orchestration and diagnostics.
  Future<void> setSceneEpoch({
    required String worldlineId,
    required String sceneEpochId,
    required int revision,
  }) async {
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'must be non-negative');
    }
    final normalizedWorldline = worldlineId.trim();
    final normalizedEpoch = sceneEpochId.trim();
    if (normalizedWorldline.isEmpty || normalizedEpoch.isEmpty) {
      throw ArgumentError('worldlineId and sceneEpochId must be non-empty');
    }

    final current = _requireState();
    await _replaceState(
      current.copyWith(
        worldlineId: normalizedWorldline,
        sceneEpochId: normalizedEpoch,
        sceneRevision: revision,
      ),
    );
  }

  Future<void> clearSceneEpoch({bool clearWorldline = false}) async {
    final current = _requireState();
    await _replaceState(
      current.copyWith(
        clearSceneEpochId: true,
        clearWorldlineId: clearWorldline,
        sceneRevision: 0,
      ),
    );
  }

  StoryRuntimeSessionState _requireState() {
    final current = _state;
    if (current == null) {
      throw StateError('story_runtime_no_conversation_attached');
    }
    return current;
  }

  Future<void> _replaceState(StoryRuntimeSessionState next) async {
    final conversationId = _attachedConversationId;
    if (conversationId == null || next.conversationId != conversationId) {
      throw StateError('story_runtime_conversation_changed');
    }

    await _store.upsert(next);
    if (_attachedConversationId != conversationId) return;
    _state = next;
    notifyListeners();
  }
}
