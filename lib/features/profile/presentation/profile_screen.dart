import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';
import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/core/location/location_service.dart';
import 'package:gather2gether/core/media/app_image_picker.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/profile_stats.dart';
import 'package:gather2gether/features/profile/domain/profile_connection.dart';
import 'package:gather2gether/features/profile/presentation/profile_connections_sheet.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/edit_profile_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_community_activity.dart';
import 'package:gather2gether/features/profile/presentation/profile_settings_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ProfileActivityBuilder =
    Widget Function(BuildContext context, UserProfile profile);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.assistantEnabled,
    required this.onAssistantEnabledChanged,
    this.repository,
    this.locationService,
    this.emailOverride,
    this.hasPasswordSignInOverride,
    this.onSignOut,
    this.onProfileChanged,
    this.avatarPicker,
    this.activityBuilder,
    this.avatarUrlOverride,
    this.avatarHeadersOverride,
    this.forumRepository,
    super.key,
  });

  final bool assistantEnabled;
  final ValueChanged<bool> onAssistantEnabledChanged;
  final ProfileRepository? repository;
  final LocationService? locationService;
  final String? emailOverride;
  final bool? hasPasswordSignInOverride;
  final Future<void> Function()? onSignOut;
  final ValueChanged<UserProfile>? onProfileChanged;
  final ProfileAvatarPicker? avatarPicker;
  final ProfileActivityBuilder? activityBuilder;
  final String? avatarUrlOverride;
  final Map<String, String>? avatarHeadersOverride;
  final ForumRepository? forumRepository;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileRepository _profiles;
  late final AppImagePicker _imagePicker;
  UserProfile? _profile;
  ProfileStats? _stats;
  int _activityRevision = 0;
  bool _loading = true;
  bool _maintenance = false;

  @override
  void initState() {
    super.initState();
    _profiles = widget.repository ?? ProfileRepository();
    _imagePicker = AppImagePicker();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        if (_profile == null) _loading = true;
        _maintenance = false;
      });
    }
    try {
      final profile = await _profiles.fetchOwnProfile();
      ProfileStats? stats;
      try {
        stats = await _profiles.fetchStats();
      } catch (_) {
        // Identity remains useful when aggregate activity is unavailable.
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _stats = stats;
        _activityRevision++;
      });
      widget.onAssistantEnabledChanged(profile.assistantEnabled);
    } catch (_) {
      if (mounted) {
        setState(() => _maintenance = true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _profileChanged(UserProfile profile) {
    if (!mounted) return;
    setState(() => _profile = profile);
    widget.onAssistantEnabledChanged(profile.assistantEnabled);
    widget.onProfileChanged?.call(profile);
  }

  Future<void> _openConnections(ProfileConnectionKind kind) async {
    await showProfileConnectionsSheet(
      context: context,
      kind: kind,
      repository: _profiles,
      initialCount: kind == ProfileConnectionKind.followers
          ? _stats?.followersCount
          : _stats?.followingCount,
    );
    if (mounted) await _load();
  }

  Future<void> _openEdit() async {
    final profile = _profile;
    if (profile == null) return;
    await showAppSheet<UserProfile>(
      context: context,
      builder: (_) => EditProfileScreen(
        asSheet: true,
        profile: profile,
        repository: _profiles,
        avatarPicker: widget.avatarPicker ?? _pickAvatar,
        avatarUrlBuilder: _avatarUrlFor,
        avatarHeaders: _avatarHeadersFor(profile),
        onProfileChanged: _profileChanged,
      ),
    );
  }

  Future<void> _openSettings() async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfileSettingsScreen(
          profile: profile,
          repository: _profiles,
          locationService: widget.locationService,
          emailOverride: widget.emailOverride,
          hasPasswordSignInOverride: widget.hasPasswordSignInOverride,
          avatarUrlOverride: widget.avatarUrlOverride,
          avatarHeadersOverride: widget.avatarHeadersOverride,
          onSignOut: widget.onSignOut,
          onAssistantEnabledChanged: widget.onAssistantEnabledChanged,
          onProfileChanged: _profileChanged,
        ),
      ),
    );
  }

  String? _avatarUrlFor(UserProfile profile) {
    if (!profile.hasAvatar) return null;
    final override = widget.avatarUrlOverride;
    if (override != null) return override;
    final base = AppConfig.edgeApiUrl.endsWith('/')
        ? AppConfig.edgeApiUrl.substring(0, AppConfig.edgeApiUrl.length - 1)
        : AppConfig.edgeApiUrl;
    final version = Uri.encodeQueryComponent(profile.avatarImageKey!);
    return '$base/profile/avatar?v=$version';
  }

  Map<String, String>? _avatarHeadersFor(UserProfile profile) {
    final override = widget.avatarHeadersOverride;
    if (override != null) return override;
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return token == null || token.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};
  }

  Future<PreparedImage?> _pickAvatar() async {
    final source = await showModalBottomSheet<AppImageSource>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.photo_fill_on_rectangle_fill),
              title: const Text('Choose from photos'),
              onTap: () => Navigator.pop(context, AppImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.camera_fill),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, AppImageSource.camera),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.xmark),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    return source == null ? null : _imagePicker.pickImage(source);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(
        child: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }
    if (_maintenance || _profile == null) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          children: [
            const AppPageHeader(title: 'You'),
            const SizedBox(height: 28),
            AppMaintenanceState(
              key: const Key('profile-maintenance-state'),
              onRetry: _load,
            ),
          ],
        ),
      );
    }

    final profile = _profile!;
    final activity = widget.activityBuilder?.call(context, profile);
    return SafeArea(
      child: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 16, 0),
                        child: ProfileSocialAppBar(
                          username: profile.username,
                          onSettings: _openSettings,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
                        child: ProfileBalancedOverview(
                          profile: profile,
                          stats: _stats,
                          avatarUrl: _avatarUrlFor(profile),
                          avatarHeaders: _avatarHeadersFor(profile),
                          onEdit: _openEdit,
                          onFollowers: () =>
                              _openConnections(ProfileConnectionKind.followers),
                          onFollowing: () =>
                              _openConnections(ProfileConnectionKind.following),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: ProfileContributionsHeader(),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child:
                        activity ??
                        ProfileCommunityActivity(
                          key: ValueKey('profile-activity-$_activityRevision'),
                          repository: widget.forumRepository,
                        ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }
}
