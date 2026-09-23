import '../cache/story_prompt_cache_plan.dart';

/// Stable v1 output contract for the main story model.
///
/// Keep this text frozen within a protocol version. Dynamic scene, memory,
/// character and presentation data belongs in later cache classes, not here.
///
/// The reader-visible prose comes first. Structured events are duplicated in a
/// trailing HTML comment so Kelivo can progressively render normal prose while
/// streaming, then persist semantic events after finalization without exposing
/// protocol JSON in Chat mode.
const String storyResponseContractV1 = '''
[STORY_OUTPUT_V1]
Write the polished reader-visible story response first as ordinary Markdown prose.
Do not wrap the visible prose in JSON, XML, a code fence, or protocol markers.

After the visible prose, append exactly one trailing HTML comment in this form:
<!--KELIVO_STORY_EVENTS
{"version":1,"events":[EVENT,...]}
KELIVO_STORY_EVENTS-->
Nothing may follow that closing marker.

The events must semantically mirror the visible prose. EVENT fields:
- type: narration | dialogue | action | expression | scene_transition | choice_set | runtime_notice
- actor: {"type":"self"} | {"type":"world"} | {"type":"character","character_id":"STABLE_ID"}
- text: optional ordered array of {"text":"...","effect":"...","decoration":"...","motion":"..."}
- choices: only for choice_set; ordered array of {"id":"...","label":"...","submit_text":"..."}
- timeout_ms: optional positive integer; use only when time pressure matters
- timeout_action_id: optional choice id or "silence"
- metadata: optional small JSON object

Actor rules:
- self is always the real user in second-person narration. Never invent or switch to a player character.
- narration, scene_transition and runtime_notice use world.
- dialogue uses self or character.
- action/expression use self or character.
- choice_set uses self.

Presentation rules:
- Use semantic text effects only when narratively meaningful. Never output raw RGB, font size, vibration duration or animation parameters.
- Keep ordinary prose ordinary. Horror/distortion effects are exceptional emphasis, not default styling.
- Do not serialize reasoning, tool calls, tool results or approval UI into the event JSON. Kelivo carries those as native runtime parts.
- Do not force user interaction every turn. Emit choice_set only when the user actually needs a meaningful decision.
- The HTML comment is machine-readable sidecar data and must never be discussed in the visible prose.
[/STORY_OUTPUT_V1]
''';

const StoryPromptContribution storyResponseContractContributionV1 =
    StoryPromptContribution(
      id: 'story.output.contract.v1',
      stability: StoryPromptStability.frozen,
      content: storyResponseContractV1,
      order: 100,
    );
