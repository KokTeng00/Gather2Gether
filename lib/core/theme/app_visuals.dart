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
              width: 34,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
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
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(
            color: filled ? colors.primary : colors.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
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
    super.key,
  });

  final String title;
  final Widget child;
  final String? footer;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
      Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
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
    final visual = CategoryVisual.forName(label);
    return Semantics(
      button: onTap != null,
      label: title,
      child: Material(
        color: visual.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
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
