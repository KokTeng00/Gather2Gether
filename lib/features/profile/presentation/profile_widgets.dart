import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/profile/domain/profile_stats.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';

String _formatRadius(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

class ProfileSocialAppBar extends StatelessWidget {
  const ProfileSocialAppBar({
    required this.username,
    required this.onSettings,
    super.key,
  });

  final String username;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('profile-social-header'),
      constraints: const BoxConstraints(minHeight: 54),
      alignment: Alignment.center,
      child: Row(
        children: [
          Expanded(
            child: Text(
              username.trim().isEmpty ? 'Your profile' : username.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Profile settings',
            onPressed: onSettings,
            icon: const Icon(CupertinoIcons.gear_alt_fill),
          ),
        ],
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.profile,
    this.imageUrl,
    this.headers,
    this.size = 88,
    super.key,
  });

  final UserProfile profile;
  final String? imageUrl;
  final Map<String, String>? headers;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = profile.displayName.trim();
    final initial = name.isEmpty
        ? '?'
        : String.fromCharCode(name.runes.first).toUpperCase();
    final fallback = ColoredBox(
      color: colors.primaryContainer,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: colors.onPrimaryContainer,
            fontSize: size * 0.34,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
    return Semantics(
      image: true,
      label: name.isEmpty ? 'Profile photo' : '$name profile photo',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.09),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.72),
            width: 2.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: profile.hasAvatar && imageUrl != null
            ? Image.network(
                imageUrl!,
                key: ValueKey(profile.avatarImageKey),
                headers: headers,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class ProfileOverviewHero extends StatelessWidget {
  const ProfileOverviewHero({
    required this.profile,
    required this.stats,
    required this.onEdit,
    this.avatarUrl,
    this.avatarHeaders,
    super.key,
  });

  final UserProfile profile;
  final ProfileStats? stats;
  final VoidCallback onEdit;
  final String? avatarUrl;
  final Map<String, String>? avatarHeaders;

  @override
  Widget build(BuildContext context) {
    final username = profile.username.trim();
    final city = profile.city.trim();
    final bio = profile.bio.trim();
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: const Key('profile-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ProfileAvatar(
              key: const Key('profile-avatar'),
              profile: profile,
              imageUrl: avatarUrl,
              headers: avatarHeaders,
              size: 86,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Row(
                key: const Key('profile-inline-stats'),
                children: [
                  Expanded(
                    child: _ProfileStat(
                      value: stats?.postsCount,
                      label: 'Posts',
                    ),
                  ),
                  Expanded(
                    child: _ProfileStat(
                      value: stats?.hostedCount,
                      label: 'Hosted',
                    ),
                  ),
                  Expanded(
                    child: _ProfileStat(
                      value: stats?.goingCount,
                      label: 'Going',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        Text(
          profile.displayName.trim().isEmpty
              ? 'Community member'
              : profile.displayName.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (username.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '@$username',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 9),
          Text(
            bio,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurface,
              height: 1.35,
            ),
          ),
        ],
        if (city.isNotEmpty) ...[
          const SizedBox(height: 9),
          Row(
            children: [
              Icon(
                CupertinoIcons.location_fill,
                size: 15,
                color: colors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  city,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('profile-edit-action'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          onPressed: onEdit,
          icon: const Icon(CupertinoIcons.pencil, size: 17),
          label: const Text('Edit profile'),
        ),
      ],
    );
  }
}

class ProfilePostsTabHeader extends StatelessWidget {
  const ProfilePostsTabHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: true,
      label: 'Community posts grid',
      child: Container(
        key: const Key('profile-posts-tab'),
        height: 48,
        decoration: BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.7),
              width: 0.7,
            ),
          ),
        ),
        child: Center(
          child: SizedBox(
            width: 74,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  CupertinoIcons.square_grid_3x2_fill,
                  size: 21,
                  color: colors.primary,
                ),
                const SizedBox(height: 10),
                Container(
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
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
}

class ProfileStatsCard extends StatelessWidget {
  const ProfileStatsCard({required this.stats, super.key});

  final ProfileStats? stats;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: _ProfileStat(value: stats?.postsCount, label: 'Posts'),
          ),
          const SizedBox(height: 42, child: VerticalDivider()),
          Expanded(
            child: _ProfileStat(value: stats?.hostedCount, label: 'Hosted'),
          ),
          const SizedBox(height: 42, child: VerticalDivider()),
          Expanded(
            child: _ProfileStat(value: stats?.goingCount, label: 'Going'),
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.value, required this.label});

  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value?.toString() ?? '—',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class ProfileActivityPlaceholder extends StatelessWidget {
  const ProfileActivityPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      borderRadius: 22,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Icon(
              CupertinoIcons.photo_on_rectangle,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Your community moments',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            'Posts you share with the community will appear here.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

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
