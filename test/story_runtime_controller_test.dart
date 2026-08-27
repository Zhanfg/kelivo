import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/agency/story_agency_policy.dart';
import 'package:Kelivo/features/story_runtime/state/story_runtime_controller.dart';
import 'package:Kelivo/features/story_runtime/state/story_runtime_state.dart';
import 'package:Kelivo/features/story_runtime/state/story_runtime_store.dart';

void main() {
  group('StoryRuntimeController', () {
    test('serializes rapid mutations without dropping earlier changes', () async {
      final repository = _FakeStoryRuntimeRepository();
      final controller = StoryRuntimeController(store: repository);
      await controller.attachConversation('conv-1');

      final enable = controller.setEnabled(true);
      final agency = controller.setAgencyMode(StoryAgencyMode.cinematic);
      await Future.wait([enable, agency]);

      expect(controller.isEnabled, isTrue);
      expect(controller.agencyMode, StoryAgencyMode.cinematic);
      expect(repository.states['conv-1']?.enabled, isTrue);
      expect(
        repository.states['conv-1']?.agencyMode,
        StoryAgencyMode.cinematic,
      );
    });

    test('a delayed old conversation cannot overwrite a newer attachment', () async {
      final repository = _FakeStoryRuntimeRepository();
      final delayedA = Completer<StoryRuntimeSessionState>();
      repository.delayedReads['conv-a'] = delayedA;

      final controller = StoryRuntimeController(store: repository);
      final attachA = controller.attachConversation('conv-a');
      expect(controller.attachedConversationId, 'conv-a');
      expect(controller.isLoading, isTrue);

      await controller.attachConversation('conv-b');
      expect(controller.attachedConversationId, 'conv-b');
      expect(controller.state?.conversationId, 'conv-b');
      expect(controller.isLoading, isFalse);

      delayedA.complete(
        const StoryRuntimeSessionState(
          conversationId: 'conv-a',
          enabled: true,
          agencyMode: StoryAgencyMode.cinematic,
        ),
      );
      await attachA;

      expect(controller.attachedConversationId, 'conv-b');
      expect(controller.state?.conversationId, 'conv-b');
      expect(controller.isEnabled, isFalse);
      expect(controller.agencyMode, StoryAgencyMode.balanced);
    });

    test('read failure clears loading state for the active conversation', () async {
      final repository = _FakeStoryRuntimeRepository();
      repository.readErrors['conv-bad'] = StateError('storage failed');
      final controller = StoryRuntimeController(store: repository);

      await expectLater(
        controller.attachConversation('conv-bad'),
        throwsA(isA<StateError>()),
      );

      expect(controller.attachedConversationId, 'conv-bad');
      expect(controller.isLoading, isFalse);
      expect(controller.state, isNull);
    });

    test('scene epoch mutation remains conversation scoped', () async {
      final repository = _FakeStoryRuntimeRepository();
      final controller = StoryRuntimeController(store: repository);
      await controller.attachConversation('conv-scene');

      await controller.setSceneEpoch(
        worldlineId: 'wl-main',
        sceneEpochId: 'scene-42',
        revision: 3,
      );

      expect(controller.state?.worldlineId, 'wl-main');
      expect(controller.state?.sceneEpochId, 'scene-42');
      expect(controller.state?.sceneRevision, 3);

      await controller.clearSceneEpoch(clearWorldline: false);
      expect(controller.state?.worldlineId, 'wl-main');
      expect(controller.state?.sceneEpochId, isNull);
      expect(controller.state?.sceneRevision, 0);
    });
  });
}

final class _FakeStoryRuntimeRepository
    implements StoryRuntimeSessionRepository {
  final Map<String, StoryRuntimeSessionState> states =
      <String, StoryRuntimeSessionState>{};
  final Map<String, Completer<StoryRuntimeSessionState>> delayedReads =
      <String, Completer<StoryRuntimeSessionState>>{};
  final Map<String, Object> readErrors = <String, Object>{};

  @override
  Future<StoryRuntimeSessionState?> readForConversation(
    String conversationId,
  ) async {
    final error = readErrors[conversationId];
    if (error != null) throw error;
    final delayed = delayedReads[conversationId];
    if (delayed != null) return delayed.future;
    return states[conversationId];
  }

  @override
  Future<StoryRuntimeSessionState> readOrDefault(String conversationId) async {
    final existing = await readForConversation(conversationId);
    return existing ?? StoryRuntimeSessionState(conversationId: conversationId);
  }

  @override
  Future<void> upsert(StoryRuntimeSessionState state) async {
    states[state.conversationId] = state;
  }

  @override
  Future<void> setEnabled(String conversationId, bool enabled) async {
    final current =
        states[conversationId] ??
        StoryRuntimeSessionState(conversationId: conversationId);
    states[conversationId] = current.copyWith(enabled: enabled);
  }

  @override
  Future<void> removeForConversation(String conversationId) async {
    states.remove(conversationId);
  }
}
