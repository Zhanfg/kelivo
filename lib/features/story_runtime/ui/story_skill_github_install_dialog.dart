import 'package:flutter/material.dart';

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
) {
  return showDialog<StorySkillGitHubInstallRequest>(
    context: context,
    builder: (_) => const _StorySkillGitHubInstallDialog(),
  );
}

class _StorySkillGitHubInstallDialog extends StatefulWidget {
  const _StorySkillGitHubInstallDialog();

  @override
  State<_StorySkillGitHubInstallDialog> createState() =>
      _StorySkillGitHubInstallDialogState();
}

class _StorySkillGitHubInstallDialogState
    extends State<_StorySkillGitHubInstallDialog> {
  final TextEditingController _repository = TextEditingController();
  final TextEditingController _ref = TextEditingController();
  final TextEditingController _subdirectory = TextEditingController();

  bool get _valid => _repository.text.trim().isNotEmpty;

  @override
  void dispose() {
    _repository.dispose();
    _ref.dispose();
    _subdirectory.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(
      StorySkillGitHubInstallRequest(
        repositoryUrl: _repository.text.trim(),
        ref: _optional(_ref.text),
        subdirectory: _optional(_subdirectory.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('从 GitHub 安装 Skill'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '支持公开 GitHub 仓库和包含 SKILL.md 的子目录。GitHub 直装采用安全模式：不会执行脚本，也不会静默授予 MCP、工具或内存权限。',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _repository,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'GitHub 仓库',
                hintText: 'owner/repo 或 https://github.com/owner/repo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ref,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Branch / Tag / Ref（可选）',
                hintText: '留空使用默认分支',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subdirectory,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Skill 子目录（可选）',
                hintText: '例如 skills/humanizer',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: const Text('安装'),
        ),
      ],
    );
  }
}

String? _optional(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
