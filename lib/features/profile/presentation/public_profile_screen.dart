import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/public_profile.dart';

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({
    required this.profileId,
    this.repository,
    super.key,
  });

  final String profileId;
  final ProfileRepository? repository;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late final ProfileRepository _repository;
  PublicProfile? _profile;
  bool _loading = true;
  bool _updatingFollow = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ProfileRepository();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final profile = await _repository.fetchPublicProfile(widget.profileId);
      if (mounted) {
        setState(() {
          _profile = profile;
          _error = null;
        });
      }
    } on ProfileApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'This profile is temporarily unavailable.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null || profile.viewerIsSelf || _updatingFollow) return;
    final following = !profile.viewerIsFollowing;
    setState(() => _updatingFollow = true);
    try {
      final saved = await _repository.setFollowing(profile.id, following);
      if (!mounted) return;
      setState(() {
        _profile = profile.copyWith(
          viewerIsFollowing: saved,
          followersCount: (profile.followersCount + (saved ? 1 : -1)).clamp(
            0,
            1 << 31,
          ),
        );
      });
    } on ProfileApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _updatingFollow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          profile?.username.isNotEmpty == true
              ? '@${profile!.username}'
              : 'Profile',
        ),
      ),
      body: _loading && profile == null
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          : _error != null && profile == null
          ? _ProfileError(message: _error!, onRetry: _load)
          : RefreshIndicator.adaptive(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
                children: [
                  _PublicProfileHero(
                    profile: profile!,
                    repository: _repository,
                    updatingFollow: _updatingFollow,
                    onFollow: _toggleFollow,
                  ),
                ],
              ),
            ),
    );
  }
}

class _PublicProfileHero extends StatelessWidget {
  const _PublicProfileHero({
    required this.profile,
    required this.repository,
    required this.updatingFollow,
    required this.onFollow,
  });

  final PublicProfile profile;
  final ProfileRepository repository;
  final bool updatingFollow;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initial = profile.displayName.trim().isEmpty
        ? '?'
        : String.fromCharCode(
            profile.displayName.trim().runes.first,
          ).toUpperCase();
    return AppSurface(
      borderRadius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            key: const Key('public-profile-avatar'),
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
              border: Border.all(color: colors.primary, width: 2.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: profile.hasAvatar
                ? Image.network(
                    repository.publicAvatarUrl(profile),
                    headers: repository.publicMediaHeaders(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Text(initial, style: _initialStyle(colors)),
                    ),
                  )
                : Center(child: Text(initial, style: _initialStyle(colors))),
          ),
          const SizedBox(height: 14),
          Text(
            profile.displayName,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (profile.username.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '@${profile.username}',
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (profile.bio.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              profile.bio,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
            ),
          ],
          if (profile.city.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.location_fill,
                  size: 15,
                  color: colors.primary,
                ),
                const SizedBox(width: 5),
                Flexible(child: Text(profile.city)),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _SocialCount(
                  value: profile.followersCount,
                  label: 'Followers',
                ),
              ),
              const SizedBox(height: 40, child: VerticalDivider()),
              Expanded(
                child: _SocialCount(
                  value: profile.followingCount,
                  label: 'Following',
                ),
              ),
            ],
          ),
          if (!profile.viewerIsSelf) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: profile.viewerIsFollowing
                  ? OutlinedButton(
                      key: const Key('profile-follow-button'),
                      onPressed: updatingFollow ? null : onFollow,
                      child: Text(updatingFollow ? 'Saving…' : 'Following'),
                    )
                  : FilledButton(
                      key: const Key('profile-follow-button'),
                      onPressed: updatingFollow ? null : onFollow,
                      child: Text(updatingFollow ? 'Saving…' : 'Follow'),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  TextStyle _initialStyle(ColorScheme colors) => TextStyle(
    color: colors.onPrimaryContainer,
    fontSize: 34,
    fontWeight: FontWeight.w800,
  );
}

class _SocialCount extends StatelessWidget {
  const _SocialCount({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$value',
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.person_crop_circle_badge_exclam, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
