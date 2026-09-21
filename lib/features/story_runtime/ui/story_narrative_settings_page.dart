import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../theme/app_font_weights.dart';
import '../narrative/story_narrative_profile.dart';
import '../narrative/story_narrative_profile_store.dart';

class StoryNarrativeSettingsPage extends StatefulWidget {
  const StoryNarrativeSettingsPage({
    super.key,
    required this.conversationId,
  });

  final String conversationId;

  @override
  State<StoryNarrativeSettingsPage> createState() =>
      _StoryNarrativeSettingsPageState();
}

class _StoryNarrativeSettingsPageState
    extends State<StoryNarrativeSettingsPage> {
  StoryNarrativeProfile? _profile;
  bool _saving = false;

  late final TextEditingController _voice;
  late final TextEditingController _pov;
  late final TextEditingController _rhythm;
  late final TextEditingController _dialogue;
  late final TextEditingController _description;
  late final TextEditingController _implicitness;
  late final TextEditingController _pacing;
  late final TextEditingController _scenePurpose;
  late final TextEditingController _dramaticQuestion;
  late final TextEditingController _pacingDirection;

  @override
  void initState() {
    super.initState();
    _voice = TextEditingController();
    _pov = TextEditingController();
    _rhythm = TextEditingController();
    _dialogue = TextEditingController();
    _description = TextEditingController();
    _implicitness = TextEditingController();
    _pacing = TextEditingController();
    _scenePurpose = TextEditingController();
    _dramaticQuestion = TextEditingController();
    _pacingDirection = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final profile = await StoryNarrativeProfileStore(
      context.read<BusinessPreferences>(),
    ).readOrDefault(widget.conversationId);
    if (!mounted) return;
    _apply(profile);
    setState(() => _profile = profile);
  }

  void _apply(StoryNarrativeProfile profile) {
    final style = profile.style;
    final director = profile.director;
    _voice.text = style.narrativeVoice;
    _pov.text = style.pov;
    _rhythm.text = style.sentenceRhythm;
    _dialogue.text = style.dialogue;
    _description.text = style.descriptionDensity;
    _implicitness.text = style.implicitness;
    _pacing.text = style.pacing;
    _scenePurpose.text = director.scenePurpose;
    _dramaticQuestion.text = director.dramaticQuestion;
    _pacingDirection.text = director.pacingDirection;
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[
      _voice,
      _pov,
      _rhythm,
      _dialogue,
      _description,
      _implicitness,
      _pacing,
      _scenePurpose,
      _dramaticQuestion,
      _pacingDirection,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final current = _profile;
    if (current == null || _saving) return;
    setState(() => _saving = true);
    try {
      final oldStyle = current.style;
      final oldDirector = current.director;
      final next = current.copyWith(
        style: StoryStyleDna(
          narrativeVoice: _voice.text.trim(),
          pov: _pov.text.trim(),
          narrativeDistance: oldStyle.narrativeDistance,
          sentenceRhythm: _rhythm.text.trim(),
          dialogue: _dialogue.text.trim(),
          descriptionDensity: _description.text.trim(),
          metaphorDensity: oldStyle.metaphorDensity,
          sensoryFocus: oldStyle.sensoryFocus,
          pacing: _pacing.text.trim(),
          expositionTolerance: oldStyle.expositionTolerance,
          implicitness: _implicitness.text.trim(),
          emotionalExplicitness: oldStyle.emotionalExplicitness,
          sceneTransitions: oldStyle.sceneTransitions,
          paragraphRhythm: oldStyle.paragraphRhythm,
          avoidPatterns: oldStyle.avoidPatterns,
        ),
        director: StoryNarrativeDirectorState(
          scenePurpose: _scenePurpose.text.trim(),
          dramaticQuestion: _dramaticQuestion.text.trim(),
          pacingDirection: _pacingDirection.text.trim(),
          informationAsymmetry: oldDirector.informationAsymmetry,
          affordances: oldDirector.affordances,
          repetitionWarnings: oldDirector.repetitionWarnings,
          tension: oldDirector.tension,
          targetTension: oldDirector.targetTension,
        ),
      );
      await StoryNarrativeProfileStore(
        context.read<BusinessPreferences>(),
      ).upsert(next);
      if (!mounted) return;
      setState(() => _profile = next);
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(zh ? '叙事设置已保存' : 'Narrative settings saved')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(zh ? '叙事' : 'Narrative'),
        actions: [
          TextButton(
            onPressed: profile == null || _saving ? null : _save,
            child: Text(_saving ? (zh ? '保存中…' : 'Saving…') : (zh ? '保存' : 'Save')),
          ),
        ],
      ),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Text(
                  zh ? '作品形态' : 'Story surface',
                  style: TextStyle(fontWeight: AppFontWeights.semibold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<StorySurfaceMode>(
                  initialValue: profile.surface,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: [
                    for (final mode in StorySurfaceMode.values)
                      DropdownMenuItem(
                        value: mode,
                        child: Text(_surfaceLabel(mode, zh)),
                      ),
                  ],
                  onChanged: (mode) {
                    if (mode == null) return;
                    setState(() => _profile = _profile?.copyWith(surface: mode));
                  },
                ),
                const SizedBox(height: 24),
                _SectionTitle(zh ? 'Style DNA' : 'Style DNA'),
                _Field(controller: _voice, label: zh ? '叙事声音' : 'Narrative voice'),
                _Field(controller: _pov, label: zh ? '视角 / POV' : 'POV'),
                _Field(controller: _rhythm, label: zh ? '句式节奏' : 'Sentence rhythm'),
                _Field(controller: _dialogue, label: zh ? '对白风格' : 'Dialogue'),
                _Field(controller: _description, label: zh ? '描写密度' : 'Description density'),
                _Field(controller: _implicitness, label: zh ? '含蓄 / 留白' : 'Implicitness'),
                _Field(controller: _pacing, label: zh ? '总体节奏' : 'Pacing'),
                const SizedBox(height: 24),
                _SectionTitle(zh ? 'Narrative Director' : 'Narrative Director'),
                _Field(
                  controller: _scenePurpose,
                  label: zh ? '当前场景目的' : 'Scene purpose',
                  maxLines: 2,
                ),
                _Field(
                  controller: _dramaticQuestion,
                  label: zh ? '戏剧问题' : 'Dramatic question',
                  maxLines: 2,
                ),
                _Field(
                  controller: _pacingDirection,
                  label: zh ? '节奏方向' : 'Pacing direction',
                ),
                const SizedBox(height: 16),
                Text(
                  zh
                      ? '这些内容约束“怎么写”，不会把 Runtime 状态变成固定剧情模板。世界事实和连续性仍由底层 Story Runtime 管理。'
                      : 'These controls shape how the story is written without turning runtime state into a fixed plot template. World facts and continuity remain owned by Story Runtime.',
                  style: TextStyle(
                    height: 1.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 17,
        fontWeight: AppFontWeights.semibold,
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

String _surfaceLabel(StorySurfaceMode mode, bool zh) => switch (mode) {
  StorySurfaceMode.novel => zh ? '小说' : 'Novel',
  StorySurfaceMode.roleplay => zh ? '角色扮演' : 'Roleplay',
  StorySurfaceMode.visualNovel => zh ? '视觉小说' : 'Visual novel',
  StorySurfaceMode.screenplay => zh ? '剧本' : 'Screenplay',
  StorySurfaceMode.experimental => zh ? '实验叙事' : 'Experimental',
};
