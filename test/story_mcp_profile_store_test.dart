import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/features/story_runtime/mcp/story_mcp_profile.dart';
import 'package:Kelivo/features/story_runtime/mcp/story_mcp_profile_store.dart';

import 'support/business_test_harness.dart';

void main() {
  test(
    'deleting a Story MCP profile clears every dangling selection',
    () async {
      final harness = await createBusinessTestHarness();
      final profiles = StoryMcpProfileStore(harness.preferences);
      final selections = StoryMcpProfileSelectionStore(harness.preferences);

      const writing = StoryMcpProfile(
        id: 'profile-writing',
        name: 'Writing',
        serverIds: <String>['server-a'],
      );
      const research = StoryMcpProfile(
        id: 'profile-research',
        name: 'Research',
        serverIds: <String>['server-b'],
      );

      await profiles.upsert(writing);
      await profiles.upsert(research);
      await selections.select('conversation-a', writing.id);
      await selections.select('conversation-b', writing.id);
      await selections.select('conversation-c', research.id);

      expect(await selections.clearProfileReferences(writing.id), 2);
      expect(
        (await selections.readForConversation('conversation-a')).profileId,
        isNull,
      );
      expect(
        (await selections.readForConversation('conversation-b')).profileId,
        isNull,
      );
      expect(
        (await selections.readForConversation('conversation-c')).profileId,
        research.id,
      );

      expect(await profiles.remove(writing.id), isTrue);
      expect(await profiles.readById(writing.id), isNull);
      expect((await profiles.readById(research.id))?.name, 'Research');
      expect(await profiles.remove('missing-profile'), isFalse);
    },
  );
}
