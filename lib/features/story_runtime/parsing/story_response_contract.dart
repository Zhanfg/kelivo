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

/// Sparse Story output contract used by the Narrative Director architecture.
///
/// The visible work is authoritative for presentation. The sidecar is optional:
/// emit it only when Kelivo needs a semantic event it cannot reliably derive
/// from text/runtime state. This prevents every turn from duplicating the prose
/// as JSON and keeps model tokens focused on the story itself.
const String storyResponseContractV2 = '''
[STORY_OUTPUT_V2]
Write only polished reader-facing fiction as ordinary Markdown prose.

Do not restate Story Runtime state, Style DNA, Scene Packet, ids, or constraints.
Do not format the response as an event log, game transcript, status panel, or JSON.

Normally stop after the prose.

Only when a machine-only semantic event is necessary and cannot be reliably
derived by Kelivo, append one trailing sidecar:
<!--KELIVO_STORY_EVENTS
{"version":1,"events":[EVENT,...]}
KELIVO_STORY_EVENTS-->
Nothing may follow it.

EVENT uses: type, actor, optional text, optional choices, optional metadata.
For action_result use type="action_result" and actor={"type":"world"}.
For choice_set use type="choice_set", actor={"type":"self"}, and choices with
{id,label,submit_text}. Other ordinary prose does not need an event.

The sidecar is sparse, not a mirror of the prose:
- include only indispensable interaction/state semantics;
- never duplicate ordinary narration merely to describe what was just written;
- action_result is a world event used only when the latest user action changes
  runtime state or when a short reader-facing action result is useful outside
  the prose. It may carry metadata:
  - feedback: short result summary, not a prose duplicate;
  - scene_patch: scene_id/location/time_label/pov and participant_add/remove;
  - relationship_patch: [{"from":"self|CHAR_ID","to":"self|CHAR_ID","delta":{"trust":-0.2,"fear":0.1}}];
  - continuity_patch / serial_patch / open_loops_add / open_loops_close as needed.
- relationship deltas are increments in [-1,1], not full relationship dumps;
- choice_set replaces the currently available formal choices and is allowed only
  when the user genuinely needs a meaningful decision;
- after an action_result, omit choice_set when no formal decision is currently available;
- omit the sidecar entirely when no semantic delta is needed;
- never discuss or reveal the sidecar in visible prose.
[/STORY_OUTPUT_V2]
''';

const StoryPromptContribution storyResponseContractContributionV2 =
    StoryPromptContribution(
      id: 'story.output.contract.v2',
      stability: StoryPromptStability.frozen,
      content: storyResponseContractV2,
      order: 100,
    );

