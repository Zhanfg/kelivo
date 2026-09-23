import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../theme/app_font_weights.dart';
import '../../settings/widgets/voice_service_widgets.dart';

class StoryNativeBackButton extends StatelessWidget {
  const StoryNativeBackButton({super.key, required this.tooltip});

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IosIconButton(
        icon: Lucide.ArrowLeft,
        color: Theme.of(context).colorScheme.onSurface,
        size: 22,
        minSize: 44,
        semanticLabel: tooltip,
        onTap: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class StoryNativeSection extends StatelessWidget {
  const StoryNativeSection({
    super.key,
    required this.title,
    required this.children,
    this.footer,
    this.first = false,
  });

  final String title;
  final List<Widget> children;
  final String? footer;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, first ? 2 : 0, 12, 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
        VoiceServiceMobileCard(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1)
                voiceServiceMobileDivider(context),
            ],
          ],
        ),
        if (footer != null && footer!.trim().isNotEmpty) ...[
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              footer!,
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: cs.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class StoryNativeRow extends StatelessWidget {
  const StoryNativeRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final interactive = onTap != null && enabled;
    return IosCardPress(
      onTap: interactive ? onTap : null,
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      baseColor: Colors.transparent,
      haptics: interactive,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            if (icon != null) ...[
              SizedBox(
                width: 36,
                child: Icon(
                  icon,
                  size: 20,
                  color: cs.onSurface.withValues(alpha: enabled ? 0.9 : 0.35),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: AppFontWeights.medium,
                      color: cs.onSurface.withValues(
                        alpha: enabled ? 0.9 : 0.42,
                      ),
                    ),
                  ),
                  if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: cs.onSurface.withValues(
                          alpha: enabled ? 0.6 : 0.34,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ] else if (interactive) ...[
              const SizedBox(width: 8),
              Icon(
                Lucide.ChevronRight,
                size: 16,
                color: cs.onSurface.withValues(alpha: 0.82),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StoryNativeSwitchRow extends StatelessWidget {
  const StoryNativeSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return StoryNativeRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      enabled: onChanged != null,
      trailing: IosSwitch(
        value: value,
        semanticLabel: title,
        onChanged: onChanged,
      ),
    );
  }
}

class StoryNativeSelectRow<T> extends StatelessWidget {
  const StoryNativeSelectRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.labelFor,
    required this.onSelected,
    this.subtitle,
    this.icon,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T value) labelFor;
  final ValueChanged<T>? onSelected;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StoryNativeRow(
      title: label,
      subtitle: subtitle,
      icon: icon,
      enabled: onSelected != null && options.isNotEmpty,
      onTap: onSelected == null || options.isEmpty
          ? null
          : () async {
              final selected = await _showOptions<T>(
                context,
                current: value,
                options: options,
                labelFor: labelFor,
              );
              if (selected != null) onSelected!(selected);
            },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              labelFor(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          if (onSelected != null && options.isNotEmpty) ...[
            const SizedBox(width: 6),
            Icon(
              Lucide.ChevronRight,
              size: 16,
              color: cs.onSurface.withValues(alpha: 0.82),
            ),
          ],
        ],
      ),
    );
  }
}

class StoryNativeTextFieldRow extends StatelessWidget {
  const StoryNativeTextFieldRow({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.enabled = true,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool enabled;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      child: TextField(
        controller: controller,
        enabled: enabled,
        minLines: minLines,
        maxLines: maxLines,
        style: TextStyle(
          fontSize: 15,
          color: cs.onSurface.withValues(alpha: 0.9),
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 7),
          labelStyle: TextStyle(
            fontSize: 13,
            color: cs.onSurface.withValues(alpha: 0.62),
          ),
          hintStyle: TextStyle(
            fontSize: 13,
            color: cs.onSurface.withValues(alpha: 0.38),
          ),
        ),
      ),
    );
  }
}

class StoryNativeButton extends StatelessWidget {
  const StoryNativeButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return IosTileButton(
      label: label,
      icon: icon,
      onTap: onTap,
      enabled: enabled,
      backgroundColor: primary ? Theme.of(context).colorScheme.primary : null,
    );
  }
}

Future<T?> _showOptions<T>(
  BuildContext context, {
  required T current,
  required List<T> options,
  required String Function(T value) labelFor,
}) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < options.length; index++) ...[
                VoiceServiceTactileRow(
                  onTap: () => Navigator.of(sheetContext).pop(options[index]),
                  haptics: true,
                  builder: (pressed) {
                    final selected = options[index] == current;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              labelFor(options[index]),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: selected
                                    ? AppFontWeights.semibold
                                    : AppFontWeights.regular,
                                color: cs.onSurface.withValues(
                                  alpha: pressed ? 0.68 : 0.9,
                                ),
                              ),
                            ),
                          ),
                          if (selected)
                            Icon(Lucide.Check, size: 18, color: cs.primary),
                        ],
                      ),
                    );
                  },
                ),
                if (index != options.length - 1)
                  Divider(
                    height: 1,
                    thickness: 0.6,
                    indent: 16,
                    endIndent: 16,
                    color: cs.outlineVariant.withValues(alpha: 0.18),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
