import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../icons/reasoning_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';
import 'composer_reasoning_level.dart';

typedef ComposerReasoningBudgetChanged = Future<void> Function(int budget);
typedef ComposerModelChanged =
    Future<void> Function(String providerKey, String modelId);

class ComposerModelOption {
  const ComposerModelOption({
    required this.providerKey,
    required this.providerName,
    required this.modelId,
    required this.displayName,
  });

  final String providerKey;
  final String providerName;
  final String modelId;
  final String displayName;
}

List<ComposerModelOption> buildComposerModelOptions(SettingsProvider settings) {
  final orderedKeys = <String>[
    ...settings.providersOrder.where((key) => key.trim().isNotEmpty),
  ];
  for (final key in settings.providerConfigs.keys) {
    if (key.trim().isNotEmpty && !orderedKeys.contains(key)) {
      orderedKeys.add(key);
    }
  }

  final result = <ComposerModelOption>[];
  for (final key in orderedKeys) {
    final config = settings.getProviderConfig(key, defaultName: key);
    if (!config.enabled || config.models.isEmpty) continue;
    final providerName = config.name.trim().isEmpty ? key : config.name.trim();
    for (final rawModelId in config.models) {
      final modelId = rawModelId.trim();
      if (modelId.isEmpty) continue;
      final override = config.modelOverrides[modelId];
      final overrideName = override is Map
          ? override['name']?.toString().trim()
          : null;
      result.add(
        ComposerModelOption(
          providerKey: key,
          providerName: providerName,
          modelId: modelId,
          displayName: overrideName != null && overrideName.isNotEmpty
              ? overrideName
              : modelId,
        ),
      );
    }
  }
  return result;
}

Future<void> showComposerReasoningPopover(
  BuildContext context, {
  required Rect anchorRect,
  required int? currentBudget,
  required bool supportsXhigh,
  required bool supportsMax,
  required String? currentProviderKey,
  required String? currentModelId,
  required List<ComposerModelOption> modelOptions,
  required ComposerReasoningBudgetChanged onBudgetChanged,
  ComposerModelChanged? onModelChanged,
}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, _, __) => _ComposerReasoningPopover(
      anchorRect: anchorRect,
      currentBudget: currentBudget,
      supportsXhigh: supportsXhigh,
      supportsMax: supportsMax,
      currentProviderKey: currentProviderKey,
      currentModelId: currentModelId,
      modelOptions: modelOptions,
      onBudgetChanged: onBudgetChanged,
      onModelChanged: onModelChanged,
    ),
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

enum _AdvancedPane { reasoning, model }

class _ComposerReasoningPopover extends StatefulWidget {
  const _ComposerReasoningPopover({
    required this.anchorRect,
    required this.currentBudget,
    required this.supportsXhigh,
    required this.supportsMax,
    required this.currentProviderKey,
    required this.currentModelId,
    required this.modelOptions,
    required this.onBudgetChanged,
    required this.onModelChanged,
  });

  final Rect anchorRect;
  final int? currentBudget;
  final bool supportsXhigh;
  final bool supportsMax;
  final String? currentProviderKey;
  final String? currentModelId;
  final List<ComposerModelOption> modelOptions;
  final ComposerReasoningBudgetChanged onBudgetChanged;
  final ComposerModelChanged? onModelChanged;

  @override
  State<_ComposerReasoningPopover> createState() =>
      _ComposerReasoningPopoverState();
}

class _ComposerReasoningPopoverState extends State<_ComposerReasoningPopover> {
  late ComposerReasoningLevel _selectedLevel;
  late double _manualSliderValue;
  bool _advanced = false;
  bool _busy = false;
  _AdvancedPane _advancedPane = _AdvancedPane.reasoning;

  @override
  void initState() {
    super.initState();
    _selectedLevel = composerReasoningLevelForBudget(widget.currentBudget);
    _manualSliderValue = _sliderValueFor(_selectedLevel);
  }

  double _sliderValueFor(ComposerReasoningLevel level) {
    return switch (level) {
      ComposerReasoningLevel.off => 0,
      ComposerReasoningLevel.low => 1,
      ComposerReasoningLevel.medium => 2,
      ComposerReasoningLevel.high => 3,
      ComposerReasoningLevel.max => 4,
      ComposerReasoningLevel.auto => 2,
    };
  }

  ComposerReasoningLevel _levelForSlider(double value) {
    return switch (value.round().clamp(0, 4)) {
      0 => ComposerReasoningLevel.off,
      1 => ComposerReasoningLevel.low,
      2 => ComposerReasoningLevel.medium,
      3 => ComposerReasoningLevel.high,
      _ => ComposerReasoningLevel.max,
    };
  }

  String _labelFor(AppLocalizations l10n, ComposerReasoningLevel level) {
    return switch (level) {
      ComposerReasoningLevel.auto => l10n.reasoningBudgetSheetAuto,
      ComposerReasoningLevel.off => l10n.reasoningBudgetSheetOff,
      ComposerReasoningLevel.low => l10n.reasoningBudgetSheetLight,
      ComposerReasoningLevel.medium => l10n.reasoningBudgetSheetMedium,
      ComposerReasoningLevel.high => l10n.reasoningBudgetSheetHeavy,
      ComposerReasoningLevel.max => l10n.reasoningBudgetSheetMax,
    };
  }

  Future<void> _selectLevel(ComposerReasoningLevel level) async {
    if (_busy) return;
    final budget = budgetForComposerReasoningLevel(
      level,
      supportsXhigh: widget.supportsXhigh,
      supportsMax: widget.supportsMax,
    );
    setState(() {
      _busy = true;
      _selectedLevel = level;
      if (level != ComposerReasoningLevel.auto) {
        _manualSliderValue = _sliderValueFor(level);
      }
    });
    try {
      await widget.onBudgetChanged(budget);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectModel(ComposerModelOption option) async {
    final callback = widget.onModelChanged;
    if (_busy || callback == null) return;
    setState(() => _busy = true);
    try {
      await callback(option.providerKey, option.modelId);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final totalWidth = _advanced
        ? math.min(364.0, size.width - 24)
        : math.min(312.0, size.width - 24);
    final maxHeight = math.max(
      180.0,
      math.min(430.0, widget.anchorRect.top - 20),
    );
    final bottom = math.max(12.0, size.height - widget.anchorRect.top + 8);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            right: 12,
            bottom: bottom,
            child: SizedBox(
              width: totalWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: _advanced
                    ? _buildAdvanced(context)
                    : _buildPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _surface(BuildContext context, Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 8,
      shadowColor: cs.shadow.withValues(alpha: 0.20),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildPrimary(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final auto = _selectedLevel == ComposerReasoningLevel.auto;
    final labels = <ComposerReasoningLevel>[
      ComposerReasoningLevel.off,
      ComposerReasoningLevel.low,
      ComposerReasoningLevel.medium,
      ComposerReasoningLevel.high,
      ComposerReasoningLevel.max,
    ];

    return _surface(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _selectionTile(
              context,
              icon: Lucide.Sparkles,
              label: l10n.reasoningBudgetSheetAuto,
              selected: auto,
              onTap: _busy
                  ? null
                  : () => _selectLevel(ComposerReasoningLevel.auto),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: cs.primary,
                  inactiveTrackColor: cs.surfaceContainerHighest,
                  thumbColor: cs.primary,
                  overlayColor: cs.primary.withValues(alpha: 0.10),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                ),
                child: Slider(
                  key: const ValueKey('composer-reasoning-slider'),
                  value: _manualSliderValue,
                  min: 0,
                  max: 4,
                  divisions: 4,
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() {
                            _manualSliderValue = value;
                            _selectedLevel = _levelForSlider(value);
                          });
                        },
                  onChangeEnd: _busy
                      ? null
                      : (value) => _selectLevel(_levelForSlider(value)),
                ),
              ),
            ),
            Row(
              children: [
                for (var index = 0; index < labels.length; index++)
                  Expanded(
                    child: Text(
                      _labelFor(l10n, labels[index]),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      textAlign: index == 0
                          ? TextAlign.left
                          : index == labels.length - 1
                          ? TextAlign.right
                          : TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              key: const ValueKey('composer-reasoning-advanced'),
              onPressed: _busy ? null : () => setState(() => _advanced = true),
              icon: const Icon(Lucide.Settings2, size: 18),
              label: Text(l10n.modelDetailSheetAdvancedTab),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvanced(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: _surface(
            context,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _rootTile(
                    context,
                    icon: Lucide.Boxes,
                    label: l10n.chatInputBarSelectModelTooltip,
                    selected: _advancedPane == _AdvancedPane.model,
                    onTap: () =>
                        setState(() => _advancedPane = _AdvancedPane.model),
                  ),
                  _rootTile(
                    context,
                    icon: Lucide.Brain,
                    label: l10n.chatInputBarReasoningStrengthTooltip,
                    selected: _advancedPane == _AdvancedPane.reasoning,
                    onTap: () =>
                        setState(() => _advancedPane = _AdvancedPane.reasoning),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _surface(
            context,
            _advancedPane == _AdvancedPane.model
                ? _buildModelList(context)
                : _buildReasoningList(context),
          ),
        ),
      ],
    );
  }

  Widget _buildReasoningList(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const levels = <ComposerReasoningLevel>[
      ComposerReasoningLevel.auto,
      ComposerReasoningLevel.off,
      ComposerReasoningLevel.low,
      ComposerReasoningLevel.medium,
      ComposerReasoningLevel.high,
      ComposerReasoningLevel.max,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final level in levels)
            _selectionTile(
              context,
              icon: level == ComposerReasoningLevel.auto
                  ? Lucide.Sparkles
                  : Lucide.Brain,
              leading: level == ComposerReasoningLevel.auto
                  ? null
                  : ReasoningIcons.budgetIcon(
                      budgetForComposerReasoningLevel(
                        level,
                        supportsXhigh: widget.supportsXhigh,
                        supportsMax: widget.supportsMax,
                      ),
                      size: 18,
                      color: _selectedLevel == level
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.68),
                    ),
              label: _labelFor(l10n, level),
              selected: _selectedLevel == level,
              onTap: _busy ? null : () => _selectLevel(level),
            ),
        ],
      ),
    );
  }

  Widget _buildModelList(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    if (widget.modelOptions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          l10n.homePagePleaseSelectModel,
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65)),
        ),
      );
    }

    String? previousProvider;
    final rows = <Widget>[];
    for (final option in widget.modelOptions) {
      if (previousProvider != option.providerKey) {
        if (rows.isNotEmpty) rows.add(const SizedBox(height: 4));
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              option.providerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        );
        previousProvider = option.providerKey;
      }
      final selected =
          option.providerKey == widget.currentProviderKey &&
          option.modelId == widget.currentModelId;
      rows.add(
        _selectionTile(
          context,
          icon: Lucide.Box,
          label: option.displayName,
          selected: selected,
          onTap: _busy || widget.onModelChanged == null
              ? null
              : () => _selectModel(option),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }

  Widget _rootTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? cs.onSecondaryContainer : cs.onSurface,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected
                          ? AppFontWeights.semibold
                          : AppFontWeights.medium,
                      color: selected ? cs.onSecondaryContainer : cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionTile(
    BuildContext context, {
    required IconData icon,
    Widget? leading,
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Material(
        color: selected
            ? cs.primaryContainer.withValues(alpha: 0.72)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                leading ??
                    Icon(
                      icon,
                      size: 18,
                      color: selected
                          ? cs.onPrimaryContainer
                          : cs.onSurface.withValues(alpha: 0.68),
                    ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected
                          ? AppFontWeights.semibold
                          : AppFontWeights.medium,
                      color: selected ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Lucide.Check, size: 17, color: cs.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
