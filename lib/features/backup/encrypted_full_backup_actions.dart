import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/backup.dart';
import '../../core/providers/backup_provider.dart';
import '../../core/providers/backup_reminder_provider.dart';
import '../../core/services/backup/encrypted_full_backup.dart';
import '../../core/services/native_file_save.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/snackbar.dart';
import 'backup_restart_dialog.dart';
import 'backup_task_runner.dart';

bool _isZh(BuildContext context) =>
    Localizations.localeOf(context).languageCode.startsWith('zh');

Future<String?> _promptPassword(
  BuildContext context, {
  required bool confirm,
}) async {
  final zh = _isZh(context);
  final password = TextEditingController();
  final confirmation = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final passwordValue = password.text;
          final confirmationValue = confirmation.text;
          final valid =
              passwordValue.length >= 8 &&
              (!confirm || passwordValue == confirmationValue);
          return AlertDialog(
            title: Text(
              confirm
                  ? (zh ? '设置备份密码' : 'Set backup password')
                  : (zh ? '输入备份密码' : 'Enter backup password'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: password,
                  obscureText: true,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: zh ? '密码' : 'Password',
                    helperText: zh
                        ? '至少 8 个字符；密码不会写入备份。'
                        : 'At least 8 characters. The password is never stored in the backup.',
                  ),
                ),
                if (confirm) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmation,
                    obscureText: true,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: zh ? '再次输入密码' : 'Confirm password',
                      errorText:
                          confirmationValue.isNotEmpty &&
                              passwordValue != confirmationValue
                          ? (zh ? '两次密码不一致' : 'Passwords do not match')
                          : null,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(zh ? '取消' : 'Cancel'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.of(dialogContext).pop(passwordValue)
                    : null,
                child: Text(
                  confirm
                      ? (zh ? '加密导出' : 'Encrypt & export')
                      : (zh ? '继续' : 'Continue'),
                ),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    password.dispose();
    confirmation.dispose();
  }
}

Future<RestoreMode?> _chooseRestoreMode(BuildContext context) {
  final zh = _isZh(context);
  return showDialog<RestoreMode>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(zh ? '选择恢复模式' : 'Choose restore mode'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(zh ? '完全覆盖' : 'Overwrite'),
            subtitle: Text(
              zh ? '以备份内容替换当前数据。' : 'Replace current data with the backup.',
            ),
            onTap: () => Navigator.of(dialogContext).pop(RestoreMode.overwrite),
          ),
          ListTile(
            title: Text(zh ? '增量合并' : 'Merge'),
            subtitle: Text(
              zh
                  ? '保留当前数据并合并备份内容。'
                  : 'Keep current data and merge backup content.',
            ),
            onTap: () => Navigator.of(dialogContext).pop(RestoreMode.merge),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
      ],
    ),
  );
}

Future<void> exportEncryptedFullBackupAction(
  BuildContext context,
  BackupProvider provider,
) async {
  final password = await _promptPassword(context, confirm: true);
  if (password == null || !context.mounted) return;
  final zh = _isZh(context);
  File? file;
  final ok = await runBackupTask(
    context,
    title: zh ? '导出完整加密备份' : 'Export encrypted complete backup',
    task: (handle) async {
      file = await provider.exportEncryptedFullBackup(
        password: password,
        onProgress: handle.report,
        cancelToken: handle.cancelToken,
      );
    },
  );
  if (!ok || file == null) return;
  final exported = file!;
  try {
    if (!context.mounted) return;
    if (Platform.isAndroid || Platform.isIOS) {
      final saved = await NativeFileSave.saveFileFromPath(
        sourcePath: exported.path,
        fileName: exported.uri.pathSegments.last,
      );
      if (saved && context.mounted) {
        await context.read<BackupReminderProvider>().recordBackupCompleted();
      }
      return;
    }

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: zh ? '导出完整加密备份' : 'Export encrypted complete backup',
      fileName: exported.uri.pathSegments.last,
      type: FileType.custom,
      allowedExtensions: const ['kelivo'],
    );
    if (savePath == null) return;
    await File(savePath).parent.create(recursive: true);
    await exported.copy(savePath);
    if (context.mounted) {
      await context.read<BackupReminderProvider>().recordBackupCompleted();
    }
  } catch (error) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: error.toString(),
      type: NotificationType.error,
    );
  } finally {
    await EncryptedFullBackupCodec.cleanupTemporaryFile(file);
  }
}

Future<void> importEncryptedFullBackupAction(
  BuildContext context,
  BackupProvider provider,
) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['kelivo'],
  );
  final path = result?.files.single.path;
  if (path == null || !context.mounted) return;

  final password = await _promptPassword(context, confirm: false);
  if (password == null || !context.mounted) return;
  final mode = await _chooseRestoreMode(context);
  if (mode == null || !context.mounted) return;

  final l10n = AppLocalizations.of(context)!;
  final ok = await runBackupTask(
    context,
    title: _isZh(context) ? '恢复完整加密备份' : 'Restore encrypted complete backup',
    errorMessage: (error) =>
        l10n.backupPageRestoreFailedMessage(error.toString()),
    task: (handle) => provider.restoreEncryptedFullBackup(
      File(path),
      password: password,
      mode: mode,
      onProgress: handle.report,
      cancelToken: handle.cancelToken,
    ),
  );
  if (!ok || !context.mounted) return;
  await showBackupRestartRequiredDialog(
    context,
    skippedConversations: provider.skippedConversations,
  );
}
