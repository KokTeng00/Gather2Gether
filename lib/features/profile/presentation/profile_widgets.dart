import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/profile/domain/profile_stats.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/profile_photo_screen.dart';

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
    return Row(
      key: const Key('profile-page-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Semantics(
            label: username.trim().isEmpty
                ? 'Profile'
                : 'Profile for ${username.trim()}',
            header: true,
            child: Text(
              'Profile',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: 'Profile settings',
          onPressed: onSettings,
          color: colors.onSurfaceVariant,
          icon: const Icon(CupertinoIcons.gear, size: 21),
        ),
      ],
    );
  }
}

/// A compact profile summary with identity, editing, and social stats.
class ProfileBalancedOverview extends StatelessWidget {
  const ProfileBalancedOverview({
    required this.profile,
    required this.stats,
    required this.onEdit,
    this.onFollowers,
    this.onFollowing,
    this.avatarUrl,
    this.avatarHeaders,
    super.key,
  });

  final UserProfile profile;
  final ProfileStats? stats;
  final VoidCallback onEdit;
  final VoidCallback? onFollowers;
  final VoidCallback? onFollowing;
  final String? avatarUrl;
  final Map<String, String>? avatarHeaders;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final username = profile.username.trim();
    final city = profile.city.trim();
    final bio = profile.bio.trim();
    final displayName = profile.displayName.trim().isEmpty
        ? 'Community member'
        : profile.displayName.trim();

    return Column(
      key: const Key('profile-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.center,
          child: ProfileAvatar(
            key: const Key('profile-avatar'),
            profile: profile,
            imageUrl: avatarUrl,
            headers: avatarHeaders,
            size: 84,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.4 + 44,
                ),
                child: Semantics(
                  button: true,
                  child: Tooltip(
                    message: 'Edit profile',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const Key('profile-edit-action'),
                        onTap: onEdit,
                        borderRadius: BorderRadius.circular(12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (username.isNotEmpty)
                              Flexible(
                                child: Text(
                                  '@$username',
                                  key: const Key('profile-username-action'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            SizedBox(
                              key: const Key('profile-edit-icon'),
                              width: 44,
                              height: 44,
                              child: Icon(
                                CupertinoIcons.pencil,
                                color: colors.primary,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (city.isNotEmpty) ...[
                Icon(
                  CupertinoIcons.location,
                  size: 13,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            bio,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          key: const Key('profile-activity-summary'),
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ProfileStat(value: stats?.postsCount, label: 'Posts'),
              ),
              _ProfileStatSeparator(color: colors.outlineVariant),
              Expanded(
                child: _ProfileStat(
                  value: stats?.followersCount,
                  label: 'Followers',
                  onTap: onFollowers,
                ),
              ),
              _ProfileStatSeparator(color: colors.outlineVariant),
              Expanded(
                child: _ProfileStat(
                  value: stats?.followingCount,
                  label: 'Following',
                  onTap: onFollowing,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileStatSeparator extends StatelessWidget {
  const _ProfileStatSeparator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class ProfileCommunityOverview extends StatelessWidget {
  const ProfileCommunityOverview({
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
    final displayName = profile.displayName.trim().isEmpty
        ? 'Community member'
        : profile.displayName.trim();
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: const Key('profile-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSurface(
          color: colors.primaryContainer.withValues(alpha: 0.42),
          borderColor: colors.primary.withValues(alpha: 0.14),
          borderRadius: 24,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProfileAvatar(
                    key: const Key('profile-avatar'),
                    profile: profile,
                    imageUrl: avatarUrl,
                    headers: avatarHeaders,
                    size: 74,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (username.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '@$username',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                        if (city.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              Icon(
                                CupertinoIcons.location,
                                size: 14,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  city,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  bio,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('profile-edit-action'),
                onPressed: onEdit,
                icon: const Icon(CupertinoIcons.pencil, size: 16),
                label: const Text('Edit profile'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppSurface(
          key: const Key('profile-activity-summary'),
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 11),
                child: Text(
                  'Community footprint',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Divider(height: 1),
              _ProfileMetricRow(
                icon: CupertinoIcons.chat_bubble_2,
                label: 'Community posts',
                value: stats?.postsCount,
              ),
              const Divider(height: 1, indent: 58),
              _ProfileMetricRow(
                icon: CupertinoIcons.person_2,
                label: 'People following you',
                value: stats?.followersCount,
              ),
              const Divider(height: 1, indent: 58),
              _ProfileMetricRow(
                icon: CupertinoIcons.person_crop_circle_badge_checkmark,
                label: 'People you follow',
                value: stats?.followingCount,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileMetricRow extends StatelessWidget {
  const _ProfileMetricRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(icon, color: colors.primary, size: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value?.toString() ?? '—',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
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
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    final canView = profile.hasAvatar && imageUrl != null;
    return Semantics(
      image: true,
      button: canView,
      label: name.isEmpty ? 'Profile photo' : '$name profile photo',
      child: GestureDetector(
        onTap: canView
            ? () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => ProfilePhotoScreen(
                    imageUrl: imageUrl!,
                    headers: headers,
                    name: name,
                  ),
                ),
              )
            : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle),
          foregroundDecoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.outlineVariant, width: 1),
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
                      value: stats?.followersCount,
                      label: 'Followers',
                    ),
                  ),
                  Expanded(
                    child: _ProfileStat(
                      value: stats?.followingCount,
                      label: 'Following',
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
            fontWeight: FontWeight.w600,
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

class ProfileContributionsHeader extends StatelessWidget {
  const ProfileContributionsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('profile-contributions-header'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Posts',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
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
  const _ProfileStat({required this.value, required this.label, this.onTap});

  final int? value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value?.toString() ?? '—',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
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
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('profile-${label.toLowerCase()}-action'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: content,
            ),
          ),
        ),
      ),
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
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
                          fontWeight: FontWeight.w600,
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
                                  fontWeight: FontWeight.w600,
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
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
    final locationSubtitle = !hasLocation
        ? 'Not set'
        : locationPendingSave
        ? 'Ready to save'
        : (city.isEmpty ? 'Approximate location saved' : city);

    return AppSurface(
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Distance',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  'Show events within ${_formatRadius(radiusKm)} km',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: IgnorePointer(
                    ignoring: disabled,
                    child: CupertinoSlidingSegmentedControl<double>(
                      groupValue: radiusKm,
                      padding: const EdgeInsets.all(3),
                      backgroundColor: colors.surfaceContainerLow,
                      thumbColor: colors.primary,
                      children: {
                        for (final option in radiusOptions)
                          option: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Text(
                              '${_formatRadius(option)} km',
                              style: TextStyle(
                                color: radiusKm == option
                                    ? colors.onPrimary
                                    : colors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      },
                      onValueChanged: (value) {
                        if (!disabled && value != null) {
                          onRadiusChanged(value);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 7, 10, 7),
            leading: Icon(CupertinoIcons.location, color: colors.primary),
            title: Text(
              'Home area',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              locationSubtitle,
              style: TextStyle(
                color: locationPendingSave
                    ? colors.primary
                    : colors.onSurfaceVariant,
                fontWeight: locationPendingSave ? FontWeight.w600 : null,
              ),
            ),
            trailing: locating
                ? const SizedBox.square(
                    dimension: 40,
                    child: Center(child: CupertinoActivityIndicator()),
                  )
                : TextButton(
                    onPressed: disabled ? null : onLocationPressed,
                    child: Text(hasLocation ? 'Update' : 'Set'),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.lock_fill,
                  size: 13,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Saved approximately. Location history is never stored.',
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
      borderRadius: 18,
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            value: enabled,
            onChanged: saving ? null : onChanged,
            secondary: Icon(
              CupertinoIcons.chat_bubble_2,
              color: colors.primary,
            ),
            title: Text(
              'Gather Guide',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              saving ? 'Saving preference…' : 'Nearby events and app help',
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  CupertinoIcons.lock_fill,
                  size: 13,
                  color: colors.onSurfaceVariant,
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
