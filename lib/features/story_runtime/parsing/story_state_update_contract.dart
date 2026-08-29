import '../cache/story_prompt_cache_plan.dart';

/// Small frozen extension to the v1 Story response envelope.
///
/// State changes ride inside event metadata so the visible event schema and
/// Kelivo ChatMessage representation stay stable. Omitted keys mean unchanged.
const StoryPromptContribution storyStateUpdateContractContributionV1 =
    StoryPromptContribution(
      id: 'story.response.state-update.v1',
      stability: StoryPromptStability.frozen,
      order: 110,
      content: '''[STORY_STATE_UPDATE_V1]
Use event.metadata only for machine-readable continuity changes. Never put runtime ids or these keys in visible text.
On scene_transition metadata may include: scene_id, location, time_label, participant_character_ids (array of stable character ids), pov.
Any event metadata may include: open_loops_add (string array), open_loops_close (string array), continuity_patch (object), serial_patch (object).
Omit unchanged fields. In continuity_patch or serial_patch, a null value deletes that key; other values replace it.
[/STORY_STATE_UPDATE_V1]''',
    );
