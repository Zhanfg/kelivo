import 'package:flutter/material.dart';

import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/app_font_weights.dart';

final class StorySkillGitHubInstallRequest {
  const StorySkillGitHubInstallRequest({
    required this.repositoryUrl,
    this.ref,
    this.subdirectory,
  });

  final String repositoryUrl;
  final String? ref;
  final String? subdirectory;
}

Future<StorySkillGitHubInstallRequest?> showStorySkillGitHubInstallDialog(
  BuildContext context,
) async {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<StorySkillGitHubInstallRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _StorySkillGitHubInstallSheet(),
  );
}

class _StorySkillGitHubInstallSheet extends StatefulWidget {
  const _StorySkillGitHubInstallSheet();

  @override
  State<_StorySkillGitHubInstallSheet> createState() =>
      _StorySkillGitHubInstallSheetState();
}

class _StorySkillGitHubInstallSheetState
    extends State<_StorySkillGitHubInstallSheet> {
  final TextEditingController _repository = TextEditingController();

  bool get _valid => _repository.text.trim().isNotEmpty;

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_valid) return;
    Haptics.light();
    Navigator.of(context).pop(
      StorySkillGitHubInstallRequest(repositoryUrl: _repository.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: IosCardPress(
                  borderRadius: BorderRadius.circular(12),
                  baseColor: Colors.transparent,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Center(
                    child: Icon(Lucide.ArrowLeft, size: 20, color: cs.onSurface),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '从 GitHub 安装 Skill',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: AppFontWeights.emphasis,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '只需要仓库地址。Kelivo 会自动读取默认分支、扫描 SKILL.md、选择 Skill 入口并固定到具体 commit；不会执行仓库脚本，也不会静默授予 MCP、工具或内存权限。',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: cs.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 8),
          IosFormTextField(
            label: 'GitHub 仓库',
            controller: _repository,
            hintText: 'owner/repo 或 https://github.com/owner/repo',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            autofocus: true,
            inlineLabel: false,
            outerPadding: const EdgeInsets.symmetric(vertical: 8),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: IosCardPress(
              borderRadius: BorderRadius.circular(14),
              baseColor: _valid
                  ? cs.primary
                  : cs.onSurface.withValues(alpha: 0.08),
              onTap: _valid ? _submit : null,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Lucide.Download,
                      size: 18,
                      color: _valid ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '自动查找并安装',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: AppFontWeights.semibold,
                        color: _valid ? cs.onPrimary : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
