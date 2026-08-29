import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/tts_provider.dart';
import '../../../core/services/tts/local_tts.dart';
import '../../../core/services/tts/tts_text_selection.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import 'package:Kelivo/theme/app_semantic_colors.dart';

class TtsSettingsPage extends StatelessWidget {
  const TtsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.ttsServicesPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.ttsServicesPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.ttsSettingsPageTitle),
      ),
      body: const TtsSettingsContent(),
    );
  }
}

class TtsSettingsContent extends StatefulWidget {
  const TtsSettingsContent({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  State<TtsSettingsContent> createState() => _TtsSettingsContentState();
}

class _TtsSettingsContentState extends State<TtsSettingsContent> {
  final MossLocalModelStore _localModelStore = MossLocalModelStore();
  Future<_LocalTtsStatus>? _localStatusFuture;
  bool _localBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _localStatusFuture ??= _readLocalStatus();
  }

  Future<_LocalTtsStatus> _readLocalStatus() async {
    final validation = await _localModelStore.validate();
    var ready = false;
    if (validation.isValid && mounted) {
      try {
        ready = await context.read<TtsProvider>().isLocalTtsReady();
      } catch (_) {}
    }
    return _LocalTtsStatus(validation: validation, ready: ready);
  }

  void _refreshLocalStatus() {
    if (!mounted) return;
    setState(() => _localStatusFuture = _readLocalStatus());
  }

  Future<void> _installLocalModel() async {
    if (_localBusy) return;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择 MOSS-TTS-Nano ONNX 模型目录',
    );
    if (path == null || path.trim().isEmpty || !mounted) return;
    setState(() => _localBusy = true);
    try {
      final tts = context.read<TtsProvider>();
      await tts.stop();
      final result = await _localModelStore.installFromDirectory(path);
      if (!mounted) return;
      await tts.setBackendMode(TtsBackendMode.automatic);
      _showMessage(
        result.validation.isValid
            ? '本地 MOSS TTS 已安装。自动模式现在会优先使用本地模型。'
            : '模型复制完成，但最终校验未通过。',
      );
    } catch (error) {
      if (mounted) _showMessage('本地模型安装失败：$error');
    } finally {
      if (mounted) {
        setState(() => _localBusy = false);
        _refreshLocalStatus();
      }
    }
  }

  Future<void> _removeLocalModel() async {
    if (_localBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除本地 TTS 模型？'),
        content: const Text('只删除 Kelivo 保存的 MOSS 模型文件，不会删除网络 TTS 配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _localBusy = true);
    try {
      final tts = context.read<TtsProvider>();
      await tts.stop();
      await _localModelStore.removeInstalledModel();
      if (tts.backendMode == TtsBackendMode.localOnly) {
        await tts.setBackendMode(TtsBackendMode.automatic);
      }
      if (mounted) _showMessage('本地 MOSS TTS 模型已删除。');
    } catch (error) {
      if (mounted) _showMessage('删除失败：$error');
    } finally {
      if (mounted) {
        setState(() => _localBusy = false);
        _refreshLocalStatus();
      }
    }
  }

  Future<void> _testLocalTts() async {
    if (_localBusy) return;
    setState(() => _localBusy = true);
    final tts = context.read<TtsProvider>();
    final previousMode = tts.backendMode;
    try {
      await tts.setBackendMode(TtsBackendMode.localOnly);
      await tts.speak('这是 Kelivo 的本地语音测试。', flush: true);
    } catch (error) {
      if (mounted) _showMessage('本地语音测试失败：$error');
    } finally {
      await tts.setBackendMode(previousMode);
      if (mounted) {
        setState(() => _localBusy = false);
        _refreshLocalStatus();
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final tts = context.watch<TtsProvider>();
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String tr(String zhText, String enText) => zh ? zhText : enText;

    return ListView(
      padding: widget.padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SettingsSection(
          title: tr('语音来源', 'Voice backend'),
          footer: tr(
            '自动模式：安装本地模型后只走本地；未安装时才回退到已启用的网络 TTS，再回退到系统 TTS。',
            'Automatic mode uses local-only once a local model is installed; without one it falls back to enabled network TTS, then system TTS.',
          ),
          children: [
            for (final mode in TtsBackendMode.values)
              _BackendModeRow(
                mode: mode,
                selected: tts.backendMode == mode,
                onTap: _localBusy
                    ? null
                    : () => context.read<TtsProvider>().setBackendMode(mode),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsSection(
          title: tr('本地 MOSS TTS', 'Local MOSS TTS'),
          footer: tr(
            '模型权重不打进 APK。选择包含 MOSS-TTS-Nano ONNX、Audio Tokenizer 与 browser_poc_manifest.json 的本地目录后，Kelivo 会先校验再复制到应用私有目录。朗读时按短分块连续合成并播放。',
            'Model weights are not bundled in the APK. Select a local folder containing MOSS-TTS-Nano ONNX, the Audio Tokenizer and browser_poc_manifest.json; Kelivo validates it before copying into app-private storage. Reading synthesizes and plays short chunks continuously.',
          ),
          children: [
            FutureBuilder<_LocalTtsStatus>(
              future: _localStatusFuture,
              builder: (context, snapshot) {
                final status = snapshot.data;
                final waiting =
                    snapshot.connectionState != ConnectionState.done ||
                    _localBusy;
                final installed = status?.validation.isValid == true;
                final ready = status?.ready == true;
                final subtitle = waiting
                    ? tr('正在检查…', 'Checking…')
                    : ready
                    ? tr(
                        '已安装，可在 Android 上离线使用。',
                        'Installed and ready for offline use on Android.',
                      )
                    : installed
                    ? tr(
                        '模型已安装，但当前设备上的本地运行时不可用。',
                        'Model installed, but the local runtime is unavailable on this device.',
                      )
                    : tr('未安装本地模型。', 'No local model installed.');
                return _SettingsRow(
                  title: tr('MOSS-TTS-Nano', 'MOSS-TTS-Nano'),
                  subtitle: subtitle,
                  trailing: Icon(
                    ready
                        ? Lucide.CircleCheck
                        : installed
                        ? Lucide.TriangleAlert
                        : Lucide.HardDriveDownload,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
            _ActionSettingsRow(
              title: tr('导入 / 替换本地模型', 'Import / replace local model'),
              subtitle: tr(
                '支持一次选择完整模型目录，不需要逐个选文件。',
                'Choose the complete model directory once; no per-file picking.',
              ),
              icon: Lucide.FolderInput,
              enabled: !_localBusy,
              onTap: _installLocalModel,
            ),
            FutureBuilder<_LocalTtsStatus>(
              future: _localStatusFuture,
              builder: (context, snapshot) {
                final ready = snapshot.data?.ready == true;
                return _ActionSettingsRow(
                  title: tr('测试本地语音', 'Test local voice'),
                  subtitle: tr(
                    '强制走本地 MOSS，不调用网络 TTS。',
                    'Forces local MOSS without calling network TTS.',
                  ),
                  icon: Lucide.Play,
                  enabled: !_localBusy && ready,
                  onTap: _testLocalTts,
                );
              },
            ),
            FutureBuilder<_LocalTtsStatus>(
              future: _localStatusFuture,
              builder: (context, snapshot) => _ActionSettingsRow(
                title: tr('删除本地模型', 'Remove local model'),
                subtitle: tr(
                  '释放模型占用的存储空间。',
                  'Free storage used by model files.',
                ),
                icon: Lucide.Trash2,
                enabled:
                    !_localBusy && snapshot.data?.validation.isValid == true,
                onTap: _removeLocalModel,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsSection(
          title: l10n.ttsSettingsPlaybackSection,
          children: [
            _SettingsRow(
              title: l10n.ttsSettingsAutoPlayTitle,
              subtitle: l10n.ttsSettingsAutoPlayDescription,
              trailing: IosSwitch(
                value: settings.ttsAutoPlayAssistantReplies,
                semanticLabel: l10n.ttsSettingsAutoPlayTitle,
                onChanged: (value) => context
                    .read<SettingsProvider>()
                    .setTtsAutoPlayAssistantReplies(value),
              ),
            ),
            _SettingsRow(
              title: l10n.ttsSettingsCacheReplayTitle,
              subtitle: l10n.ttsSettingsCacheReplayDescription,
              trailing: IosSwitch(
                value: tts.cacheNetworkAudioForReplay,
                semanticLabel: l10n.ttsSettingsCacheReplayTitle,
                onChanged: (value) => context
                    .read<TtsProvider>()
                    .setCacheNetworkAudioForReplay(value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsSection(
          title: l10n.ttsSettingsTextSelectionSection,
          footer: l10n.ttsSettingsTextSelectionFallbackDescription,
          children: [
            for (final mode in TtsTextSelectionMode.values)
              _TextSelectionRow(
                mode: mode,
                selected: settings.ttsTextSelectionMode == mode,
                onTap: () => context
                    .read<SettingsProvider>()
                    .setTtsTextSelectionMode(mode),
              ),
          ],
        ),
      ],
    );
  }
}

final class _LocalTtsStatus {
  const _LocalTtsStatus({required this.validation, required this.ready});

  final MossLocalModelValidation validation;
  final bool ready;
}

class _BackendModeRow extends StatelessWidget {
  const _BackendModeRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final TtsBackendMode mode;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    final title = switch (mode) {
      TtsBackendMode.automatic => zh ? '自动（本地优先）' : 'Automatic (local first)',
      TtsBackendMode.localOnly => zh ? '仅本地' : 'Local only',
      TtsBackendMode.cloudOnly => zh ? '仅网络' : 'Network only',
      TtsBackendMode.systemOnly => zh ? '系统 TTS' : 'System TTS',
    };
    final subtitle = switch (mode) {
      TtsBackendMode.automatic =>
        zh
            ? '安装本地模型后不把文本静默回退到云端。'
            : 'Once local is installed, text never silently falls back to cloud.',
      TtsBackendMode.localOnly =>
        zh
            ? '只允许 MOSS 本地模型；不可用时直接报错。'
            : 'Only the local MOSS model; fails rather than using the network.',
      TtsBackendMode.cloudOnly =>
        zh
            ? '只使用当前启用的网络语音服务。'
            : 'Only the currently enabled network voice service.',
      TtsBackendMode.systemOnly =>
        zh ? '只使用 Android / 系统自带 TTS。' : 'Only Android / OS-provided TTS.',
    };
    return IosCardPress(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      baseColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Row(
          children: [
            Expanded(
              child: _RowText(title: title, subtitle: subtitle),
            ),
            const SizedBox(width: 12),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Icon(Lucide.Check, size: 18, color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = context.appColors.surfaceCard;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
              width: 0.6,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) _SettingsDivider(),
              ],
            ],
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              footer!,
              style: TextStyle(
                fontSize: 12,
                height: 1.25,
                color: cs.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: _RowText(title: title, subtitle: subtitle),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _ActionSettingsRow extends StatelessWidget {
  const _ActionSettingsRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IosCardPress(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      baseColor: Colors.transparent,
      child: Opacity(
        opacity: enabled ? 1 : 0.48,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
          child: Row(
            children: [
              Expanded(
                child: _RowText(title: title, subtitle: subtitle),
              ),
              const SizedBox(width: 12),
              Icon(icon, size: 19, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextSelectionRow extends StatelessWidget {
  const _TextSelectionRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final TtsTextSelectionMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return IosCardPress(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      baseColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Row(
          children: [
            Expanded(
              child: _RowText(
                title: _modeTitle(mode, l10n),
                subtitle: _modeDescription(mode, l10n),
              ),
            ),
            const SizedBox(width: 12),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 160),
              child: Icon(Lucide.Check, size: 18, color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowText extends StatelessWidget {
  const _RowText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: AppFontWeights.semibold,
            color: cs.onSurface.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            height: 1.25,
            color: cs.onSurface.withValues(alpha: 0.62),
          ),
        ),
      ],
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 0.6,
      indent: 14,
      endIndent: 12,
      color: cs.outlineVariant.withValues(alpha: 0.18),
    );
  }
}

String _modeTitle(TtsTextSelectionMode mode, AppLocalizations l10n) {
  return switch (mode) {
    TtsTextSelectionMode.fullText => l10n.ttsSettingsTextSelectionFullTextTitle,
    TtsTextSelectionMode.quotedOnly =>
      l10n.ttsSettingsTextSelectionQuotedOnlyTitle,
    TtsTextSelectionMode.outsideParentheses =>
      l10n.ttsSettingsTextSelectionOutsideParenthesesTitle,
    TtsTextSelectionMode.italicOnly =>
      l10n.ttsSettingsTextSelectionItalicOnlyTitle,
    TtsTextSelectionMode.nonItalic =>
      l10n.ttsSettingsTextSelectionNonItalicTitle,
  };
}

String _modeDescription(TtsTextSelectionMode mode, AppLocalizations l10n) {
  return switch (mode) {
    TtsTextSelectionMode.fullText =>
      l10n.ttsSettingsTextSelectionFullTextDescription,
    TtsTextSelectionMode.quotedOnly =>
      l10n.ttsSettingsTextSelectionQuotedOnlyDescription,
    TtsTextSelectionMode.outsideParentheses =>
      l10n.ttsSettingsTextSelectionOutsideParenthesesDescription,
    TtsTextSelectionMode.italicOnly =>
      l10n.ttsSettingsTextSelectionItalicOnlyDescription,
    TtsTextSelectionMode.nonItalic =>
      l10n.ttsSettingsTextSelectionNonItalicDescription,
  };
}
