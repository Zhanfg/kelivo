import '../cache/story_prompt_cache_plan.dart';

/// Stable extraction contract used by a dedicated analysis model.
///
/// The source novel is temporary analysis input. The result must be an abstract
/// craft profile, not a synopsis, quotation bank, imitation prompt or source
/// reconstruction.
const String storyReferenceAnalysisContractV1 = '''
[STORY_REFERENCE_ANALYSIS_V1]
Analyze the supplied reference-fiction chunk only to extract reusable writing-craft abstractions.

Never output:
- quotations or sample sentences from the source;
- source character/place/item names, plot events, lore, or chapter-specific facts;
- distinctive phrases or wording that would let a reader reconstruct the source;
- an instruction to imitate a named author;
- reasoning or commentary outside the JSON object.

Return exactly one JSON object:
{
  "version": 1,
  "language": "...",
  "aspects": ["prose", "narration", "dialogue", "description", "action", "atmosphere", "horror", "romanceIntimacy", "pacing", "characterInterior", "worldbuilding"],
  "core_traits": ["abstract trait", ...],
  "sentence_rhythm": ["abstract technique", ...],
  "paragraphing": ["abstract technique", ...],
  "diction": ["abstract technique", ...],
  "narration_methods": ["abstract technique", ...],
  "dialogue_methods": ["abstract technique", ...],
  "description_methods": ["abstract technique", ...],
  "action_methods": ["abstract technique", ...],
  "atmosphere_methods": ["abstract technique", ...],
  "intimacy_methods": ["abstract technique", ...],
  "interiority_methods": ["abstract technique", ...],
  "pacing_methods": ["abstract technique", ...],
  "avoid_patterns": ["what would break this profile", ...],
  "metrics": {"dimension_name": 0.0}
}

Rules for metrics:
- values are normalized 0..1;
- use stable craft dimensions such as dialogue_ratio, sentence_variance, paragraph_density, sensory_density, interiority, action_density, figurative_density, tension_density, description_granularity, intimacy_directness;
- omit a metric when the chunk does not support it.

For mature relationship or intimacy scenes, extract only craft-level properties such as pacing, emotional framing, sensory granularity, boundary/consent visibility, degree of directness, scene-to-aftermath balance and relationship focus. Never reproduce source passages.
[/STORY_REFERENCE_ANALYSIS_V1]
''';

const StoryPromptContribution storyReferenceAnalysisContractContributionV1 =
    StoryPromptContribution(
      id: 'story.reference.analysis.contract.v1',
      stability: StoryPromptStability.frozen,
      content: storyReferenceAnalysisContractV1,
      order: 120,
    );

/// Stable reduction contract for merging many chunk analyses into one callable
/// profile without re-reading the whole novel in the main Story model.
const String storyReferenceReductionContractV1 = '''
[STORY_REFERENCE_REDUCTION_V1]
Merge multiple abstract chunk analyses into one coherent writing-craft profile.
Keep only recurrent or strongly supported traits. Resolve contradictions by describing conditional use, not by averaging incompatible prose into vagueness.
Do not invent source facts. Do not add quotations, character names, plot summaries, author names or sample prose.
Return the same JSON fields as STORY_REFERENCE_ANALYSIS_V1 with version=1.
[/STORY_REFERENCE_REDUCTION_V1]
''';
