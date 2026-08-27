import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../state/story_runtime_state.dart';
import '../state/story_runtime_store.dart';
import 'story_studio_page.dart';

/// Compact, conversation-scoped Story Mode control shown with the chat input.
///
/// It intentionally uses one-shot provider reads instead of listening to the
/// provider tree so route transitions cannot leave inherited dependencies
/// attached during deactivation.
class StoryModeChatChip extends StatefulWidget {
  const StoryModeChatChip({super.key, required this.conversationId});

  final String? conversationId;

  @override
  State<StoryModeChatChip> createState() => _StoryModeChatChipState();
}

class _StoryModeChatChipState extends State<StoryModeChatChip> {
  StoryRuntimeStore? _store;
  StoryRuntimeSessionState? _session;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant StoryModeChatChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final id = widget.conversationId?.trim();
    if (id == null || id.isEmpty) {
      if (mounted) {
        setState(() {
          _session = null;
          _loading = false;
        });
      }
      return;
    }
    try {
      final store = _store ??= StoryRuntimeStore(
        context.read<BusinessPreferences>(),
      );
      final session = await store.readOrDefault(id);
      if (!mounted || widget.conversationId?.trim() != id) return;
      setState(() {
        _session = session;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool enabled) async {
    final id = widget.conversationId?.trim();
    final store = _store;
    if (id == null || id.isEmpty || store == null || _busy) return;
    setState(() => _busy = true);
    try {
      await store.setEnabled(id, enabled);
      final session = await store.readOrDefault(id);
      if (!mounted) return;
      setState(() => _session = session);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openSettings() {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => const StoryStudioPage(),
          ),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.conversationId?.trim();
    if (id == null || id.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final enabled = _session?.enabled ?? false;
    final label = zh ? '故事模式' : 'Story Mode';
    final status = enabled
        ? (zh ? '已启用' : 'On')
        : (zh ? '普通聊天' : 'Normal chat');

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: IosCardPress(
        onTap: _loading ? null : _openSettings,
        borderRadius: BorderRadius.circular(12),
        padding: EdgeInsets.zero,
        haptics: !_loading,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(
            children: [
              Icon(
                Lucide.Compass,
                size: 18,
                color: enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _loading ? '…' : status,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.52),
                      ),
                    ),
                  ],
                ),
              ),
              IosSwitch(
                value: enabled,
                semanticLabel: label,
                onChanged: _loading || _busy ? null : _toggle,
              ),
              const SizedBox(width: 5),
              Icon(
                Lucide.ChevronRight,
                size: 15,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
