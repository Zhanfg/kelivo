import 'package:flutter/services.dart' show rootBundle;

import 'story_skill_models.dart';

const Set<String> defaultBuiltInStorySkillIds = <String>{
  'lieflat-less-ai-tone',
  'story-continuity-basics',
  'scene-writing-basics',
};

Future<List<StorySkillManifest>> loadBuiltInStorySkills() async {
  final lessAiTone = await rootBundle.loadString(
    'assets/story_skills/lieflat-less-ai-tone/SKILL.md',
  );
  return <StorySkillManifest>[
    StorySkillManifest(
      id: 'lieflat-less-ai-tone',
      name: '去 AI 味',
      version: '2026.08.24',
      description: '默认写作清理 Skill；按上游白名单规则减少 AI 写作痕迹。',
      instructions: <String>[lessAiTone],
      activationModes: const <StorySkillActivationMode>{
        StorySkillActivationMode.always,
      },
      metadata: const <String, Object?>{
        'builtIn': true,
        'defaultEnabled': true,
        'source': 'https://github.com/larashero3-dotcom/lieflat-less-ai-tone',
        'sourceCommit': '27d29232f10124db904ca9c0536d0b67cb3b2833',
      },
    ),
    const StorySkillManifest(
      id: 'story-continuity-basics',
      name: '叙事连续性',
      version: '1.0.0',
      description: '维持人物、时间、地点、物品、伤势与未解决后果的一致性。',
      instructions: <String>[
        '写作时保持既有事实连续：人物身份与关系、时间线、地点、持有物、伤势、承诺和未解决后果不得无故重置；信息不足时不要凭空补造关键事实。',
      ],
      activationModes: <StorySkillActivationMode>{
        StorySkillActivationMode.always,
      },
      metadata: <String, Object?>{
        'builtIn': true,
        'defaultEnabled': true,
      },
    ),
    const StorySkillManifest(
      id: 'scene-writing-basics',
      name: '场景写作基础',
      version: '1.0.0',
      description: '让场景推进依靠动作、环境反馈与角色反应，而不是重复总结。',
      instructions: <String>[
        '优先用可观察的动作、环境变化和角色即时反应推进场景；保持既定视角与语体，避免重复概括上一段已经呈现的信息，也不要为了润色擅自增加设定。',
      ],
      activationModes: <StorySkillActivationMode>{
        StorySkillActivationMode.always,
      },
      metadata: <String, Object?>{
        'builtIn': true,
        'defaultEnabled': true,
      },
    ),
  ];
}
