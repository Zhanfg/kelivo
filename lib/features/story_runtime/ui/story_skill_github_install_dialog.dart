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
) async {
  final repository = TextEditingController();
  final ref = TextEditingController();
  final subdirectory = TextEditingController();
  try {
    return await showDialog<StorySkillGitHubInstallRequest>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final valid = repository.text.trim().isNotEmpty;
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
                    controller: repository,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'GitHub 仓库',
                      hintText: 'owner/repo 或 https://github.com/owner/repo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ref,
                    decoration: const InputDecoration(
                      labelText: 'Branch / Tag / Ref（可选）',
                      hintText: '留空使用默认分支',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subdirectory,
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
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.of(dialogContext).pop(
                          StorySkillGitHubInstallRequest(
                            repositoryUrl: repository.text.trim(),
                            ref: _optional(ref.text),
                            subdirectory: _optional(subdirectory.text),
                          ),
                        )
                    : null,
                child: const Text('安装'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    repository.dispose();
    ref.dispose();
    subdirectory.dispose();
  }
}

String? _optional(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
