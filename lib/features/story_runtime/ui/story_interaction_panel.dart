import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/database/business_preferences.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../theme/app_font_weights.dart';
import '../context/story_context_resource_store.dart';
import '../context/story_context_resources.dart';
import '../models/story_runtime_models.dart';
import '../parsing/story_message_event_store.dart';
import '../state/story_scene_runtime_state.dart';

class StoryInteractionPanel extends StatefulWidget {
  const StoryInteractionPanel({
    super.key,
    required this.conversationId,
    required this.latestAssistantMessageId,
    required this.onSubmitIntent,
    required this.onFreeAction,
    required this.disabled,
    this.pendingUserAction,
  });

  final String conversationId;
  final String? latestAssistantMessageId;
  final Future<void> Function(String text) onSubmitIntent;
  final VoidCallback onFreeAction;
  final bool disabled;
  final String? pendingUserAction;

  @override
  State<StoryInteractionPanel> createState() => _StoryInteractionPanelState();
}

class _StoryInteractionPanelState extends State<StoryInteractionPanel> {
  Future<_StoryInteractionSnapshot>? _snapshot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _snapshot ??= _load();
  }

  @override
  void didUpdateWidget(covariant StoryInteractionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId ||
        oldWidget.latestAssistantMessageId != widget.latestAssistantMessageId) {
      _snapshot = _load();
    }
  }

  Future<_StoryInteractionSnapshot> _load() async {
    BusinessPreferences preferences;
    try {
      preferences = context.read<BusinessPreferences>();
    } on ProviderNotFoundException {
      return const _StoryInteractionSnapshot();
    }

    final scene = await StorySceneRuntimeStore(
      preferences,
    ).readOrDefault(widget.conversationId);
    final resources = await StoryContextResourceStore(
      preferences,
    ).readOrDefault(widget.conversationId);
    final quickReplies =
        resources.quickReplies.where((item) => item.enabled).toList()
          ..sort((a, b) {
            final byOrder = a.order.compareTo(b.order);
            return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
          });
    final messageId = widget.latestAssistantMessageId;
    final record = messageId == null
        ? null
        : await StoryMessageEventStore(preferences).readForMessage(messageId);

    StoryEvent? choiceEvent;
    if (record != null) {
      for (final event in record.turn.events.reversed) {
        if (event.type == StoryEventType.choiceSet &&
            event.choices.isNotEmpty) {
          choiceEvent = event;
          break;
        }
      }
    }

    return _StoryInteractionSnapshot(
      location: scene.location,
      timeLabel: scene.timeLabel,
      participantCount: scene.participantCharacterIds.length,
      choices: choiceEvent?.choices ?? const <StoryChoice>[],
      quickReplies: quickReplies.take(4).toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<_StoryInteractionSnapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const _StoryInteractionSnapshot();
        final pending = widget.pendingUserAction?.trim();
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainer.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.48),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Lucide.Compass, size: 17, color: cs.primary),
                    const SizedBox(width: 7),
                    Text(
                      zh ? '互动' : 'Interact',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: AppFontWeights.semibold,
                      ),
                    ),
                    const Spacer(),
                    if (data.location?.trim().isNotEmpty == true)
                      _MetaChip(
                        icon: Lucide.MapPin,
                        text: data.location!.trim(),
                      ),
                    if (data.timeLabel?.trim().isNotEmpty == true) ...[
                      const SizedBox(width: 6),
                      _MetaChip(
                        icon: Lucide.clock,
                        text: data.timeLabel!.trim(),
                      ),
                    ],
                  ],
                ),
                if (pending?.isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    zh ? '你刚刚的行动' : 'Your latest action',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    pending!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      height: 1.35,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                ],
                if (data.choices.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    zh ? '你要怎么做？' : 'What do you do?',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                      fontWeight: AppFontWeights.emphasis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final choice in data.choices)
                        FilledButton.tonal(
                          onPressed: widget.disabled
                              ? null
                              : () => widget.onSubmitIntent(
                                  (choice.submitText?.trim().isNotEmpty == true)
                                      ? choice.submitText!.trim()
                                      : choice.label,
                                ),
                          child: Text(choice.label),
                        ),
                    ],
                  ),
                ],
                if (data.quickReplies.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    zh ? '快捷行动' : 'Quick actions',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final reply in data.quickReplies)
                        ActionChip(
                          label: Text(reply.label),
                          onPressed: widget.disabled
                              ? null
                              : () => widget.onSubmitIntent(reply.submitText),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.disabled ? null : widget.onFreeAction,
                        icon: const Icon(Lucide.Pencil, size: 16),
                        label: Text(zh ? '自由行动…' : 'Free action…'),
                      ),
                    ),
                    if (data.participantCount > 0) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: zh
                            ? '当前场景角色：${data.participantCount}'
                            : 'Characters in scene: ${data.participantCount}',
                        child: _MetaChip(
                          icon: Lucide.Users,
                          text: data.participantCount.toString(),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryInteractionSnapshot {
  const _StoryInteractionSnapshot({
    this.location,
    this.timeLabel,
    this.participantCount = 0,
    this.choices = const <StoryChoice>[],
    this.quickReplies = const <StoryQuickReply>[],
  });

  final String? location;
  final String? timeLabel;
  final int participantCount;
  final List<StoryChoice> choices;
  final List<StoryQuickReply> quickReplies;
}
