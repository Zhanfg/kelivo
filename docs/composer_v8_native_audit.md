# Composer v8 native integration audit

This document records the implementation contract for moving the approved Composer v8 prototype into Kelivo without introducing a parallel input stack.

## Architecture invariant

`ChatInputBar` remains the single owner of the visible text field and its mature input state. The redesign must not mount a second hidden `ChatInputBar`, poll another widget for attachments, or duplicate IME/paste/ASR state.

The following existing behaviors are treated as non-regression requirements:

- `TextEditingController` selection/composing state and hardware-keyboard handling.
- IME composition guard before Enter-to-send.
- Flutter `ContentInsertionConfiguration` for pasted/inserted images.
- desktop clipboard image/file/text import and long-paste-as-file behavior.
- image compression queue, processing/failure state, attachment removal, and draft restore.
- rejected-send draft restoration.
- ASR session lifecycle and microphone cleanup across app lifecycle changes.
- mobile and desktop focus behavior.

## Approved visible Composer states

### Idle / typing

The default bottom row has four primary visual entrances:

1. `+`
2. combined model/reasoning icon
3. microphone
4. primary send/stop action

Secondary capabilities must remain reachable without becoming permanent bottom-row buttons.

### Long text

The normal field grows naturally. Once the rendered text reaches six visual lines, an expand affordance appears. Expanded editing is a focused editor using the same draft/controller semantics; it is not a second independent draft.

### Model / reasoning

The normal control is icon-only. Tapping it opens the reasoning interaction directly when the active model supports reasoning; model selection remains reachable from the advanced interaction.

The user-facing reasoning vocabulary is:

`Auto / Off / Low / Medium / High / Max`

Persisted provider budgets remain numeric. `composer_reasoning_level.dart` is the semantic adapter; custom numeric values are displayed through the nearest Composer level but are not rewritten until the user explicitly selects a preset.

There is no Composer `speed` setting.

### Generation

Current Kelivo cancellation is a real stop, not a resumable pause. The UI must not label cancellation as Pause until a provider-safe pause/resume contract exists.

Queue and Guide are separate product semantics:

- Queue means deferred user input after the active generation finishes.
- Guide means affecting an in-progress generation. It cannot be implemented as a visual alias for Queue.

Existing Kelivo queue storage currently accepts one queued item. Multi-item queue management requires a data-model change before the HTML interaction can be considered complete.

### Voice

Voice uses the same ASR provider/session owned by the Composer.

Transcript delivery is classified explicitly:

- `finalOnly`: no useful transcript before finish (Sherpa offline).
- `segmented`: progressive transcript after HTTP audio segments (MiMo / Step).
- `streaming`: realtime/near-realtime provider updates (System, OpenAI Realtime, DashScope, Qwen Audio, Volcengine).

Both segmented and streaming delivery may show live preview. Final-only delivery shows recording state first and fills the preview after transcription completes.

The voice surface is one coherent panel: transcript above, capsule controls below. Gesture hints and settings must not float over transcript text. Finishing transcription never auto-sends; the transcript remains editable and requires an explicit Send action.

Editing during live transcription needs two logical buffers:

- user-editable confirmed text;
- incoming provider partial/progressive text.

Provider updates must never overwrite user edits.

### Messages

Alignment belongs to the message row, not to the bubble width. User rows align right and assistant rows align left. A text bubble shrink-wraps short text and only grows until its maximum width; it must not use the remaining row width merely to achieve alignment.

## Implementation sequence

1. Remove the duplicate `ApprovedComposerShell` integration and restore a single native input owner.
2. Add semantic adapters/tests for reasoning and ASR transcript delivery.
3. Refactor the visible `ChatInputBar` presentation while preserving its existing input/attachment/IME state machine.
4. Replace mobile reasoning presentation with the approved local slider + advanced two-level interaction.
5. Rework voice presentation around confirmed/live transcript buffers and explicit final Send.
6. Decide and implement multi-item Queue storage and Guide generation semantics before exposing those controls as complete features.
7. Apply message shrink-wrap/alignment rules to both user and assistant rendering.
8. Add widget tests for 6-line expansion, IME preservation, attachment lifecycle, voice editing, queue states, and message width/alignment.
9. Run analyzer/tests, build arm64 APK, then inspect rendered screenshots before release.
