import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';

String _formatRadius(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

class ProfileIdentityCard extends StatelessWidget {
  const ProfileIdentityCard({
    required this.initial,
    required this.name,
    required this.email,
    required this.city,
    required this.radiusKm,
    super.key,
  });

  final String initial;
  final String name;
  final String email;
  final String city;
  final double radiusKm;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      color: colors.primary,
      borderColor: colors.onPrimary.withValues(alpha: 0.14),
      borderRadius: 28,
      child: Stack(
        alignment: Alignment.bottomLeft,
        clipBehavior: Clip.antiAlias,
        children: [
          Positioned(
            right: -28,
            top: -34,
            child: Icon(
              CupertinoIcons.person_crop_circle_fill,
              size: 170,
              color: colors.onPrimary.withValues(alpha: 0.065),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.onPrimary.withValues(alpha: 0.13),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.onPrimary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: colors.onPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? 'Your profile' : name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: colors.onPrimary,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.onPrimary.withValues(
                                    alpha: 0.72,
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ProfileHeroChip(
                      icon: CupertinoIcons.location_fill,
                      label: city.isEmpty ? 'City not added' : city,
                    ),
                    _ProfileHeroChip(
                      icon: CupertinoIcons.compass_fill,
                      label: '${_formatRadius(radiusKm)} km radius',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeroChip extends StatelessWidget {
  const _ProfileHeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.onPrimary.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colors.onPrimary.withValues(alpha: 0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.onPrimary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class ProfileLoadError extends StatelessWidget {
  const ProfileLoadError({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: colors.tertiaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              color: colors.onTertiaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Couldn’t load your profile',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(CupertinoIcons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}

class ProfileNearbyPreferencesCard extends StatelessWidget {
  const ProfileNearbyPreferencesCard({
    required this.radiusKm,
    required this.radiusOptions,
    required this.city,
    required this.hasLocation,
    required this.locationPendingSave,
    required this.locating,
    required this.disabled,
    required this.onRadiusChanged,
    required this.onLocationPressed,
    super.key,
  });

  final double radiusKm;
  final List<double> radiusOptions;
  final String city;
  final bool hasLocation;
  final bool locationPendingSave;
  final bool locating;
  final bool disabled;
  final ValueChanged<double> onRadiusChanged;
  final VoidCallback onLocationPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final locationTitle = !hasLocation
        ? 'Set your home area'
        : locationPendingSave
        ? 'Area ready to save'
        : 'Home area';
    final locationSubtitle = !hasLocation
        ? 'Use your location for more relevant nearby results.'
        : locationPendingSave
        ? (city.isEmpty
              ? 'Tap Save Changes below to keep it.'
              : '$city · Ready to save')
        : (city.isEmpty ? 'Approximate area saved' : city);

    return AppSurface(
      borderRadius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _PreferenceIcon(icon: CupertinoIcons.compass_fill),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Discovery radius',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Default distance for event results',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${_formatRadius(radiusKm)} km',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in radiusOptions)
                      ChoiceChip(
                        label: Text('${_formatRadius(option)} km'),
                        selected: radiusKm == option,
                        showCheckmark: false,
                        selectedColor: colors.primary,
                        backgroundColor: colors.surfaceContainerLow,
                        side: BorderSide(
                          color: radiusKm == option
                              ? colors.primary
                              : colors.outlineVariant,
                        ),
                        shape: const StadiumBorder(),
                        labelStyle: TextStyle(
                          color: radiusKm == option
                              ? colors.onPrimary
                              : colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: disabled
                            ? null
                            : (selected) {
                                if (selected) onRadiusChanged(option);
                              },
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                const _PreferenceIcon(icon: CupertinoIcons.location_fill),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        locationTitle,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        locationSubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: locationPendingSave
                              ? colors.primary
                              : colors.onSurfaceVariant,
                          fontWeight: locationPendingSave
                              ? FontWeight.w700
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (locating)
                  const SizedBox.square(
                    dimension: 44,
                    child: Center(child: CupertinoActivityIndicator()),
                  )
                else
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: disabled ? null : onLocationPressed,
                    child: Text(hasLocation ? 'Update' : 'Set'),
                  ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.secondaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.checkmark_shield_fill,
                  size: 16,
                  color: colors.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Coordinates are rounded to about 1 km. Location history is never stored.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileGuidePreferenceCard extends StatelessWidget {
  const ProfileGuidePreferenceCard({
    required this.enabled,
    required this.saving,
    required this.onChanged,
    super.key,
  });

  final bool enabled;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      borderRadius: 22,
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            value: enabled,
            onChanged: saving ? null : onChanged,
            secondary: const _PreferenceIcon(
              icon: CupertinoIcons.chat_bubble_2_fill,
            ),
            title: Text(
              'Gather Guide',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              saving
                  ? 'Saving preference…'
                  : 'Nearby event recommendations and app help',
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 13, 18, 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.lock_shield_fill,
                  size: 16,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chat stays private to your account and can be cleared anytime.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceIcon extends StatelessWidget {
  const _PreferenceIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 20, color: colors.onPrimaryContainer),
    );
  }
}
