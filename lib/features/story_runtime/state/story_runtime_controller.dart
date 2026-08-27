import 'package:flutter/foundation.dart';

import '../agency/story_agency_policy.dart';
import 'story_runtime_state.dart';
import 'story_runtime_store.dart';

/// UI-facing controller for the currently attached conversation's Story Mode.
///
/// Conversation switches are generation-token guarded so a slow storage read
/// from an older conversation cannot overwrite the newly selected state.
final class StoryRuntimeController extends ChangeNotifier {
  StoryRuntimeController({required StoryRuntimeSessionRepository store})
    : _store = store;

  final StoryRuntimeSessionRepository _store;

  StoryRuntimeSessionState? _state;
  String? _attachedConversationId;
  bool _loading = false;
  int _loadGeneration = 0;
  Future<void> _mutationTail = Future<void>.value();

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

    try {
      final loaded = await _store.readOrDefault(normalized);
      if (generation != _loadGeneration ||
          _attachedConversationId != normalized) {
        return;
      }

      _state = loaded;
      _loading = false;
      notifyListeners();
    } catch (_) {
      if (generation == _loadGeneration &&
          _attachedConversationId == normalized) {
        _loading = false;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> setEnabled(bool enabled) {
    return _mutate((current) {
      if (current.enabled == enabled) return current;
      return current.copyWith(enabled: enabled);
    });
  }

  Future<void> setAgencyMode(StoryAgencyMode mode) {
    return _mutate((current) {
      if (current.agencyMode == mode) return current;
      return current.copyWith(agencyMode: mode);
    });
  }

  /// Starts or updates a cache-stable scene epoch. The actual scene snapshot is
  /// stored by the future world runtime; this lightweight state only tracks the
  /// current identity/revision required by orchestration and diagnostics.
  Future<void> setSceneEpoch({
    required String worldlineId,
    required String sceneEpochId,
    required int revision,
  }) {
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'must be non-negative');
    }
    final normalizedWorldline = worldlineId.trim();
    final normalizedEpoch = sceneEpochId.trim();
    if (normalizedWorldline.isEmpty || normalizedEpoch.isEmpty) {
      throw ArgumentError('worldlineId and sceneEpochId must be non-empty');
    }

    return _mutate(
      (current) => current.copyWith(
        worldlineId: normalizedWorldline,
        sceneEpochId: normalizedEpoch,
        sceneRevision: revision,
      ),
    );
  }

  Future<void> clearSceneEpoch({bool clearWorldline = false}) {
    return _mutate(
      (current) => current.copyWith(
        clearSceneEpochId: true,
        clearWorldlineId: clearWorldline,
        sceneRevision: 0,
      ),
    );
  }

  Future<void> _mutate(
    StoryRuntimeSessionState Function(StoryRuntimeSessionState current) update,
  ) {
    final acceptedConversationId = _attachedConversationId;
    if (acceptedConversationId == null) {
      return Future<void>.error(
        StateError('story_runtime_no_conversation_attached'),
      );
    }

    final operation = _mutationTail.then((_) async {
      if (_attachedConversationId != acceptedConversationId) {
        throw StateError('story_runtime_conversation_changed');
      }
      final current = _requireState();
      final next = update(current);
      if (identical(next, current)) return;

      await _store.upsert(next);
      if (_attachedConversationId != acceptedConversationId) return;
      _state = next;
      notifyListeners();
    });
    _mutationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  StoryRuntimeSessionState _requireState() {
    final current = _state;
    if (current == null) {
      throw StateError('story_runtime_no_conversation_attached');
    }
    return current;
  }
}
