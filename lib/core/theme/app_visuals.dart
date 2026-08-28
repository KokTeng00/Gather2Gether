import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CategoryVisual {
  const CategoryVisual(this.start, this.end, this.icon);

  final Color start;
  final Color end;
  final IconData icon;

  static CategoryVisual forName(String value) => switch (value.toLowerCase()) {
    'badminton' => const CategoryVisual(
      Color(0xFF12B886),
      Color(0xFF087F5B),
      CupertinoIcons.sportscourt,
    ),
    'running' => const CategoryVisual(
      Color(0xFFFF7A45),
      Color(0xFFFF3B30),
      CupertinoIcons.flame_fill,
    ),
    'padel' => const CategoryVisual(
      Color(0xFF34C759),
      Color(0xFF008F3C),
      CupertinoIcons.circle_grid_hex_fill,
    ),
    'hiking' => const CategoryVisual(
      Color(0xFF6A994E),
      Color(0xFF386641),
      CupertinoIcons.map_fill,
    ),
    'coffee' => const CategoryVisual(
      Color(0xFFB08968),
      Color(0xFF7F5539),
      Icons.coffee_rounded,
    ),
    'board games' => const CategoryVisual(
      Color(0xFF9B5DE5),
      Color(0xFF5A189A),
      CupertinoIcons.game_controller_solid,
    ),
    'language exchange' => const CategoryVisual(
      Color(0xFF00A8E8),
      Color(0xFF006494),
      CupertinoIcons.chat_bubble_2_fill,
    ),
    'photography' => const CategoryVisual(
      Color(0xFFFF5D8F),
      Color(0xFFB5174B),
      CupertinoIcons.camera_fill,
    ),
    'startup' => const CategoryVisual(
      Color(0xFF5E5CE6),
      Color(0xFF3634A3),
      CupertinoIcons.rocket_fill,
    ),
    'cycling' => const CategoryVisual(
      Color(0xFF00B4D8),
      Color(0xFF0077B6),
      Icons.directions_bike_rounded,
    ),
    'safety' => const CategoryVisual(
      Color(0xFFFF9F0A),
      Color(0xFFFF6B00),
      CupertinoIcons.shield_fill,
    ),
    'event ideas' => const CategoryVisual(
      Color(0xFFFF375F),
      Color(0xFFC9184A),
      CupertinoIcons.sparkles,
    ),
    'local tips' => const CategoryVisual(
      Color(0xFF30B0C7),
      Color(0xFF007A8A),
      CupertinoIcons.location_fill,
    ),
    'looking for group' => const CategoryVisual(
      Color(0xFF0A84FF),
      Color(0xFF0055C7),
      CupertinoIcons.person_2_fill,
    ),
    _ => const CategoryVisual(
      Color(0xFF8E8E93),
      Color(0xFF48484A),
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
            Text(title, style: Theme.of(context).textTheme.displaySmall),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
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
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 42,
            child: Icon(
              icon,
              size: 21,
              color: filled ? Colors.white : colors.primary,
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
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.35,
          ),
        ),
      ),
      Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 7, 4, 0),
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
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [visual.start, visual.end],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -20,
                  top: -14,
                  child: Icon(
                    visual.icon,
                    size: height * 0.72,
                    color: Colors.white.withValues(alpha: 0.13),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.48),
                        ],
                        stops: const [0.35, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          height: 1.08,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.88),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
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
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
        child: child,
      ),
    ),
  );
}
