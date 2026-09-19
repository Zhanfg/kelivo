import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';
import '../models/workspace_mode.dart';
import '../providers/workspace_mode_provider.dart';

class WorkspaceModeTitle extends StatelessWidget {
  const WorkspaceModeTitle({
    super.key,
    this.availableModes = const <WorkspaceMode>[
      WorkspaceMode.chat,
      WorkspaceMode.agent,
    ],
  });

  final List<WorkspaceMode> availableModes;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkspaceModeProvider>();
    final selected = availableModes.contains(provider.mode)
        ? provider.mode
        : WorkspaceMode.chat;
    final width = availableModes.length >= 3 ? 188.0 : 124.0;

    return _ScreenCenteredSlot(
      controlWidth: width,
      child: _WorkspaceModeSelector(
        modes: availableModes,
        selected: selected,
        busy: provider.busy,
        onSelected: (mode) async {
          await provider.setMode(mode);
          Haptics.light();
        },
      ),
    );
  }
}

class _WorkspaceModeSelector extends StatelessWidget {
  const _WorkspaceModeSelector({
    required this.modes,
    required this.selected,
    required this.busy,
    required this.onSelected,
  });

  final List<WorkspaceMode> modes;
  final WorkspaceMode selected;
  final bool busy;
  final ValueChanged<WorkspaceMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rawSelectedIndex = modes.indexOf(selected);
    final selectedIndex = rawSelectedIndex < 0 ? 0 : rawSelectedIndex;

    return Semantics(
      container: true,
      label: zh ? '应用模式' : 'App mode',
      child: SizedBox(
        height: 36,
        child: Material(
          color: cs.surfaceContainerHighest.withValues(
            alpha: isDark ? 0.54 : 0.72,
          ),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment(
                      modes.length == 1
                          ? 0
                          : -1 + (2 * selectedIndex / (modes.length - 1)),
                      0,
                    ),
                    child: FractionallySizedBox(
                      widthFactor: 1 / modes.length,
                      heightFactor: 1,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.14),
                            width: 0.6,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow.withValues(alpha: 0.06),
                              blurRadius: 5,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final mode in modes)
                    Expanded(
                      child: _ModeTapTarget(
                        label: _label(mode, zh),
                        selected: mode == selected,
                        enabled: !busy,
                        onTap: () => onSelected(mode),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _label(WorkspaceMode mode, bool zh) => switch (mode) {
    WorkspaceMode.chat => zh ? '聊天' : 'Chat',
    WorkspaceMode.story => zh ? '故事' : 'Story',
    WorkspaceMode.agent => zh ? '代理' : 'Agent',
  };
}

class _ModeTapTarget extends StatelessWidget {
  const _ModeTapTarget({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: 13,
              height: 1.05,
              fontWeight: selected
                  ? AppFontWeights.semibold
                  : AppFontWeights.medium,
              color: cs.onSurface.withValues(alpha: selected ? 0.94 : 0.58),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _ScreenCenteredSlot extends StatefulWidget {
  const _ScreenCenteredSlot({
    required this.controlWidth,
    required this.child,
  });

  final double controlWidth;
  final Widget child;

  @override
  State<_ScreenCenteredSlot> createState() => _ScreenCenteredSlotState();
}

class _ScreenCenteredSlotState extends State<_ScreenCenteredSlot> {
  final GlobalKey _slotKey = GlobalKey();
  double? _left;
  bool _measurementScheduled = false;

  void _scheduleMeasurement() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final renderObject = _slotKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;

      final slotWidth = renderObject.size.width;
      final globalLeft = renderObject.localToGlobal(Offset.zero).dx;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final maxLeft = (slotWidth - widget.controlWidth)
          .clamp(0.0, double.infinity)
          .toDouble();
      final nextLeft =
          (screenWidth / 2 - globalLeft - widget.controlWidth / 2)
              .clamp(0.0, maxLeft)
              .toDouble();
      if (_left == null || (_left! - nextLeft).abs() >= 0.5) {
        setState(() => _left = nextLeft);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ScreenCenteredSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controlWidth != widget.controlWidth) {
      _left = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : widget.controlWidth;
        final fallbackLeft = ((slotWidth - widget.controlWidth) / 2)
            .clamp(0.0, double.infinity)
            .toDouble();
        _scheduleMeasurement();
        return SizedBox(
          key: _slotKey,
          width: double.infinity,
          height: 36,
          child: Stack(
            children: [
              Positioned(
                left: _left ?? fallbackLeft,
                top: 0,
                width: widget.controlWidth,
                height: 36,
                child: widget.child,
              ),
            ],
          ),
        );
      },
    );
  }
}
