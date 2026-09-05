import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CategoryVisual {
  const CategoryVisual(this.background, this.ink, this.icon);

  final Color background;
  final Color ink;
  final IconData icon;

  static CategoryVisual forName(String value) => switch (value.toLowerCase()) {
    'badminton' => const CategoryVisual(
      Color(0xFFDDEDD5),
      Color(0xFF245841),
      CupertinoIcons.sportscourt,
    ),
    'running' => const CategoryVisual(
      Color(0xFFF3D3B6),
      Color(0xFF934724),
      CupertinoIcons.flame_fill,
    ),
    'padel' => const CategoryVisual(
      Color(0xFFD9E7B7),
      Color(0xFF48602A),
      CupertinoIcons.circle_grid_hex_fill,
    ),
    'hiking' => const CategoryVisual(
      Color(0xFFD9E1C8),
      Color(0xFF405534),
      CupertinoIcons.map_fill,
    ),
    'coffee' => const CategoryVisual(
      Color(0xFFE9D8C6),
      Color(0xFF6B4932),
      Icons.coffee_rounded,
    ),
    'board games' => const CategoryVisual(
      Color(0xFFE3D8EC),
      Color(0xFF654B77),
      CupertinoIcons.game_controller_solid,
    ),
    'language exchange' => const CategoryVisual(
      Color(0xFFD3E5E8),
      Color(0xFF315F68),
      CupertinoIcons.chat_bubble_2_fill,
    ),
    'photography' => const CategoryVisual(
      Color(0xFFF0D7D8),
      Color(0xFF7A4347),
      CupertinoIcons.camera_fill,
    ),
    'startup' => const CategoryVisual(
      Color(0xFFD8DDED),
      Color(0xFF414F79),
      CupertinoIcons.rocket_fill,
    ),
    'cycling' => const CategoryVisual(
      Color(0xFFD1E5E2),
      Color(0xFF2C625C),
      Icons.directions_bike_rounded,
    ),
    'safety' => const CategoryVisual(
      Color(0xFFF0E0B7),
      Color(0xFF7A5A1E),
      CupertinoIcons.shield_fill,
    ),
    'event ideas' => const CategoryVisual(
      Color(0xFFECD9C7),
      Color(0xFF785237),
      CupertinoIcons.lightbulb_fill,
    ),
    'local tips' => const CategoryVisual(
      Color(0xFFD4E5DE),
      Color(0xFF315F50),
      CupertinoIcons.location_fill,
    ),
    'looking for group' => const CategoryVisual(
      Color(0xFFD9E3D4),
      Color(0xFF3B5B43),
      CupertinoIcons.person_2_fill,
    ),
    _ => const CategoryVisual(
      Color(0xFFE1DED5),
      Color(0xFF555B55),
      CupertinoIcons.star_fill,
    ),
  };

  static CategoryVisual resolve(BuildContext context, String value) {
    final visual = forName(value);
    final colors = Theme.of(context).colorScheme;
    if (Theme.of(context).brightness == Brightness.light) return visual;
    return CategoryVisual(
      Color.alphaBlend(visual.ink.withValues(alpha: 0.3), colors.surface),
      Color.lerp(visual.ink, colors.onSurface, 0.7)!,
      visual.icon,
    );
  }
}

class AppChoiceField extends StatelessWidget {
  const AppChoiceField({
    required this.value,
    required this.options,
    required this.onChanged,
    this.label = 'Category',
    this.icon = CupertinoIcons.tag,
    this.enabled = true,
    super.key,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String label;
  final IconData icon;
  final bool enabled;

  Future<void> _showChoices(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) =>
          _AppChoiceSheet(title: label, value: value, options: options),
    );
    if (selected != null && selected != value) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label, $value',
      hint: 'Double tap to choose',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('app-choice-field'),
          onTap: enabled ? () => _showChoices(context) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: enabled
                      ? colors.primary
                      : colors.onSurface.withValues(alpha: 0.38),
                  size: 21,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: enabled
                          ? colors.onSurface
                          : colors.onSurface.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: enabled
                          ? colors.onSurfaceVariant
                          : colors.onSurface.withValues(alpha: 0.38),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.72),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppChoiceSheet extends StatelessWidget {
  const _AppChoiceSheet({
    required this.title,
    required this.value,
    required this.options,
  });

  final String title;
  final String value;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.68;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    key: const Key('app-choice-sheet-title'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(CupertinoIcons.xmark, size: 19),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.72),
          ),
          Flexible(
            child: ListView.separated(
              key: const Key('app-choice-options'),
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              itemCount: options.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.56),
              ),
              itemBuilder: (context, index) {
                final option = options[index];
                final selected = option == value;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('app-choice-$option'),
                    onTap: () => Navigator.pop(context, option),
                    child: SizedBox(
                      height: 52,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              option,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: selected
                                        ? colors.primary
                                        : colors.onSurface,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                            ),
                          ),
                          if (selected)
                            Icon(
                              CupertinoIcons.checkmark,
                              color: colors.primary,
                              size: 19,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AppInterestSearch extends StatelessWidget {
  const AppInterestSearch({
    required this.controller,
    required this.onSubmitted,
    required this.onClear,
    this.enabled = true,
    this.hintText = 'What are you interested in?',
    this.trailing,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool enabled;
  final String hintText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      borderRadius: 16,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          key: const Key('interest-search-field'),
          controller: controller,
          enabled: enabled,
          textInputAction: TextInputAction.search,
          maxLength: 240,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            counterText: '',
            prefixIcon: IconButton(
              key: const Key('interest-search-submit'),
              tooltip: 'Search',
              onPressed: enabled ? () => onSubmitted(controller.text) : null,
              icon: Icon(
                CupertinoIcons.search,
                color: colors.onSurfaceVariant,
                size: 20,
              ),
            ),
            suffixIcon: value.text.trim().isEmpty && trailing == null
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (value.text.trim().isNotEmpty)
                        IconButton(
                          key: const Key('clear-interest-search'),
                          tooltip: 'Clear search',
                          onPressed: enabled ? onClear : null,
                          icon: const Icon(CupertinoIcons.xmark_circle_fill),
                        ),
                      ?trailing,
                    ],
                  ),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    );
  }
}

class AppSaveAction extends StatelessWidget {
  const AppSaveAction({
    required this.saving,
    required this.onPressed,
    this.buttonKey,
    super.key,
  });

  final bool saving;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => Semantics(
    label: saving ? 'Saving' : 'Save',
    button: true,
    child: TextButton(
      key: buttonKey,
      onPressed: saving ? null : onPressed,
      child: SizedBox(
        width: 48,
        height: 28,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: saving
                ? const CupertinoActivityIndicator(
                    key: ValueKey('saving'),
                    radius: 8,
                  )
                : const Text('Save', key: ValueKey('save')),
          ),
        ),
      ),
    ),
  );
}

class AppBrandMark extends StatelessWidget {
  const AppBrandMark({this.size = 58, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: 'Gather2Gether',
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(size * 0.3),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.2),
                      blurRadius: size * 0.28,
                      offset: Offset(0, size * 0.12),
                    ),
                  ],
                ),
                child: Icon(
                  CupertinoIcons.person_2_fill,
                  size: size * 0.46,
                  color: colors.onPrimary,
                ),
              ),
            ),
            Positioned(
              right: size * 0.08,
              top: size * 0.08,
              child: Container(
                width: size * 0.2,
                height: size * 0.2,
                decoration: BoxDecoration(
                  color: colors.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.primary, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppSurface extends StatelessWidget {
  const AppSurface({
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.borderColor,
    this.borderRadius = 20,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius);
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return Material(
      color: color ?? colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: borderColor ?? colors.outlineVariant.withValues(alpha: 0.82),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(borderRadius: radius, onTap: onTap, child: content),
    );
  }
}

class AppMaintenanceState extends StatelessWidget {
  const AppMaintenanceState({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: AppSurface(
          color: colors.primaryContainer.withValues(alpha: 0.56),
          borderColor: colors.primary.withValues(alpha: 0.16),
          borderRadius: 28,
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              Positioned(
                right: -30,
                top: -34,
                child: Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.07),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                left: -24,
                bottom: -46,
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.09),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 28, 26, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: colors.secondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'MAINTENANCE',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.65,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.2),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        CupertinoIcons.wrench_fill,
                        size: 31,
                        color: colors.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'We’ll be back soon',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We’re making a few improvements to Gather2Gether. '
                      'Please check back in a moment.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: onRetry,
                        icon: const Icon(CupertinoIcons.refresh),
                        label: const Text('Check again'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppFeatureBanner extends StatelessWidget {
  const AppFeatureBanner({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.icon,
    super.key,
  });

  final String label;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      color: colors.primaryContainer,
      borderColor: colors.primary.withValues(alpha: 0.18),
      borderRadius: 24,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 158),
        child: Stack(
          alignment: Alignment.bottomLeft,
          clipBehavior: Clip.antiAlias,
          children: [
            Positioned(
              right: -12,
              bottom: -26,
              child: Icon(
                icon,
                size: 132,
                color: colors.onPrimaryContainer.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icon, color: colors.onPrimary, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.onPrimaryContainer,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.9,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onPrimaryContainer.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 5,
              margin: const EdgeInsets.only(bottom: 11),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(title, style: Theme.of(context).textTheme.displaySmall),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      if (actions.isNotEmpty) ...[
        const SizedBox(width: 12),
        ...actions.map(
          (item) =>
              Padding(padding: const EdgeInsets.only(left: 8), child: item),
        ),
      ],
    ],
  );
}

class AppCircleButton extends StatelessWidget {
  const AppCircleButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.filled = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: filled ? colors.primary : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: BorderSide(
            color: filled ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              icon,
              size: 21,
              color: filled ? colors.onPrimary : colors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class AppSection extends StatelessWidget {
  const AppSection({
    required this.title,
    required this.child,
    this.footer,
    this.action,
    super.key,
  });

  final String title;
  final Widget child;
  final String? footer;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 9),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
            ?action,
          ],
        ),
      ),
      AppSurface(borderRadius: 18, child: child),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
          child: Text(
            footer!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
    ],
  );
}

class AppHeroArt extends StatelessWidget {
  const AppHeroArt({
    required this.label,
    required this.title,
    this.subtitle,
    this.height = 220,
    this.onTap,
    super.key,
  });

  final String label;
  final String title;
  final String? subtitle;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visual = CategoryVisual.resolve(context, label);
    return Semantics(
      button: onTap != null,
      label: title,
      child: Material(
        color: visual.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: visual.ink.withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                Positioned(
                  right: -18,
                  top: -16,
                  child: Icon(
                    visual.icon,
                    size: height * 0.73,
                    color: visual.ink.withValues(alpha: 0.11),
                  ),
                ),
                Positioned(
                  left: 18,
                  top: 18,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: visual.ink,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        color: visual.background,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: visual.ink,
                          fontSize: 26,
                          height: 1.04,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 7),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: visual.ink.withValues(alpha: 0.78),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FrostedContainer extends StatelessWidget {
  const FrostedContainer({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: child,
  );
}
