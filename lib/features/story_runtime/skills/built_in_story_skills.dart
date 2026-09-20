import 'package:flutter/services.dart' show rootBundle;

import 'story_skill_models.dart';

const Set<String> defaultBuiltInStorySkillIds = <String>{
  'galgame-core',
  'lieflat-less-ai-tone',
  'story-continuity-basics',
  'scene-writing-basics',
  'worldline-manager',
  'context-aware-tts',
};

Future<List<StorySkillManifest>> loadBuiltInStorySkills() async {
  final lessAiTone = await rootBundle.loadString(
    'assets/story_skills/lieflat-less-ai-tone/SKILL.md',
  );
  final humanWritingCore = await rootBundle.loadString(
    'assets/story_skills/lieflat-less-ai-tone/prompts/10_kelivo_human_writing_core.md',
  );
  final visualTaste = await rootBundle.loadString(
    'assets/story_skills/visual-taste-basics/SKILL.md',
  );
  final githubSerialization = await rootBundle.loadString(
    'assets/story_skills/github-story-serialization/SKILL.md',
  );
  return <StorySkillManifest>[
    const StorySkillManifest(
      id: 'galgame-core',
      name: 'Galgame Core · 视觉小说核心',
      version: '1.0.0',
      description: '第二人称有限视角、用户主导自身行动、低风险自动推进与关键选择停点。',
      instructions: <String>[
        '以第二人称有限视角推进故事：用户始终控制自己的言行与不可逆选择，模型不得替用户决定关键行动、态度或承诺。',
        '对环境反馈、NPC 的自然反应和低风险连续动作可直接推进，不要每一小步都追问；仅在信息不足、存在重大歧义、不可逆后果或明显世界线分叉时停下等待用户。',
        'NPC 可以拥有主动性、目标和误判，但不得通过旁白读取用户未表达的思想；保持场景内信息边界与角色认知差异。',
      ],
      activationModes: <StorySkillActivationMode>{
        StorySkillActivationMode.always,
      },
      metadata: <String, Object?>{'builtIn': true, 'defaultEnabled': true},
    ),
    StorySkillManifest(
      id: 'lieflat-less-ai-tone',
      name: 'Human Writing Core · 去 AI 味',
      version: '2026.08.27',
      description: '默认写作 Skill：保留实测白名单规则，并融合中英文 anti-slop、风格保真、任务路由与事实守恒。',
      instructions: <String>[lessAiTone, humanWritingCore],
      activationModes: const <StorySkillActivationMode>{
        StorySkillActivationMode.always,
      },
      metadata: const <String, Object?>{
        'builtIn': true,
        'defaultEnabled': true,
        'maintainedBy': 'Kelivo',
        'source': 'https://github.com/larashero3-dotcom/lieflat-less-ai-tone',
        'sourceCommit': '27d29232f10124db904ca9c0536d0b67cb3b2833',
        'synthesizedSources': <String>[
          'https://github.com/blader/humanizer',
          'https://github.com/op7418/Humanizer-zh',
          'https://github.com/hardikpandya/stop-slop',
          'https://github.com/hylarucoder/ai-flavor-remover',
          'https://github.com/MrGeDiao/shuorenhua',
          'https://github.com/petergyang/no-ai-slop',
          'https://github.com/KKKKhazix/human-writing',
          'https://github.com/OUBIGFA/De-AI-Prompt-Enhancer-Writer-Booster-SKILL',
          'https://github.com/dongbeixiaohuo/writing-agent',
          'https://github.com/alchaincyf/nuwa-skill',
          'https://github.com/Hello-SimpleAI/chatgpt-comparison-detection',
        ],
      },
    ),
    const StorySkillManifest(
      id: 'story-continuity-basics',
      name: 'Continuity Keeper · 叙事连续性',
      version: '1.0.0',
      description: '维持人物、时间、地点、物品、伤势与未解决后果的一致性。',
      instructions: <String>[
        '写作时保持既有事实连续：人物身份与关系、时间线、地点、持有物、伤势、承诺和未解决后果不得无故重置；信息不足时不要凭空补造关键事实。',
      ],
      activationModes: <StorySkillActivationMode>{
        StorySkillActivationMode.always,
      },
      metadata: <String, Object?>{'builtIn': true, 'defaultEnabled': true},
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
      metadata: <String, Object?>{'builtIn': true, 'defaultEnabled': true},
    ),
    const StorySkillManifest(
      id: 'worldline-manager',
      name: 'Worldline Manager · 世界线管理',
      version: '1.0.0',
      description: '保持分支边界，避免兄弟世界线事实串线，并在重大分歧处尊重用户决策。',
      instructions: <String>[
        '把当前世界线视为唯一可见事实来源：不得把兄弟分支独有事件、记忆、关系变化或物品状态带入当前分支。',
        '遇到会显著改变长期剧情、角色关系或不可逆状态的选择时，不要替用户暗中合并或重写世界线；应明确保留分叉可能性。',
      ],
      activationModes: <StorySkillActivationMode>{
        StorySkillActivationMode.always,
      },
      metadata: <String, Object?>{'builtIn': true, 'defaultEnabled': true},
    ),
    const StorySkillManifest(
      id: 'context-aware-tts',
      name: 'Context-aware TTS · 上下文语音',
      version: '1.0.0',
      description: '优先使用 Story 的上下文感知语音链路；具体合成仍由 Kelivo 原生 TTS 负责。',
      activationModes: <StorySkillActivationMode>{
        StorySkillActivationMode.always,
      },
      ttsPolicy: StorySkillTtsPolicy.preferEnabled,
      permissions: <StorySkillPermission>{StorySkillPermission.tts},
      metadata: <String, Object?>{'builtIn': true, 'defaultEnabled': true},
    ),
    const StorySkillManifest(
      id: 'lore-author',
      name: 'Lore Author · 世界设定编写',
      version: '1.0.0',
      description: '手动启用的设定编写辅助；内容仍写入 Kelivo 原生 World Book，而不是 Story 私有存储。',
      instructions: <String>[
        '编写世界设定时优先生成独立、可检索、低冗余的事实条目；关键词应覆盖用户可能实际提及的名称、别名和概念。',
        '把稳定世界事实与当前剧情事件分开：长期设定进入 World Book，当前世界线变化进入连续性/记忆系统，不要把二者混写。',
      ],
      activationModes: <StorySkillActivationMode>{
        StorySkillActivationMode.manual,
      },
      metadata: <String, Object?>{'builtIn': true, 'defaultEnabled': false},
    ),
    StorySkillManifest(
      id: 'visual-taste-basics',
      name: 'Visual Taste · 视觉审美',
      version: '2026.08.27',
      description: '前端/UI 设计审美 Skill；减少典型 AI UI 套路，并保持 Kelivo Material 3 设计语言。',
      instructions: <String>[visualTaste],
      activationModes: const <StorySkillActivationMode>{
        StorySkillActivationMode.manual,
      },
      metadata: const <String, Object?>{
        'builtIn': true,
        'defaultEnabled': false,
        'source': 'https://github.com/Leonxlnx/taste-skill',
      },
    ),
    StorySkillManifest(
      id: 'github-story-serialization',
      name: 'GitHub Story Serialization',
      version: '1.0.0',
      description: '按需导出/恢复版本化 Story bundle，并通过现有 GitHub MCP 做仓库传输。',
      instructions: <String>[githubSerialization],
      toolIds: const <String>['story_export_bundle', 'story_restore_bundle'],
      activationModes: const <StorySkillActivationMode>{
        StorySkillActivationMode.manual,
      },
      permissions: const <StorySkillPermission>{
        StorySkillPermission.localTools,
        StorySkillPermission.mcp,
        StorySkillPermission.filesystemRead,
        StorySkillPermission.filesystemWrite,
      },
      metadata: const <String, Object?>{
        'builtIn': true,
        'defaultEnabled': false,
        'transport': 'github-mcp',
        'bundleFormat': 'kelivo-story-bundle',
      },
    ),
  ];
}
