import 'package:flutter/cupertino.dart';
import 'package:gather2gether/core/support/support_links.dart';
import 'package:gather2gether/core/theme/app_settings.dart';
import 'package:gather2gether/core/theme/app_settings_picker.dart';
import 'package:gather2gether/core/theme/appearance_controller.dart';
import 'package:gather2gether/features/profile/presentation/appearance_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';
import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/core/location/location_service.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/member_controls.dart';
import 'package:gather2gether/features/profile/domain/public_profile.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/edit_profile_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_change_password_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_widgets.dart';
import 'package:gather2gether/features/profile/presentation/notification_preferences_screen.dart';
import 'package:gather2gether/features/profile/presentation/recommendation_settings_screen.dart';
import 'package:gather2gether/features/profile/presentation/moderation_dashboard_screen.dart';
import 'package:gather2gether/features/profile/presentation/moderator_verification_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({
    required this.profile,
    required this.repository,
    required this.onAssistantEnabledChanged,
    this.onProfileChanged,
    this.locationService,
    this.emailOverride,
    this.hasPasswordSignInOverride,
    this.avatarUrlOverride,
    this.avatarHeadersOverride,
    this.onSignOut,
    super.key,
  });

  final UserProfile profile;
  final ProfileRepository repository;
  final ValueChanged<bool> onAssistantEnabledChanged;
  final ValueChanged<UserProfile>? onProfileChanged;
  final LocationService? locationService;
  final String? emailOverride;
  final bool? hasPasswordSignInOverride;
  final String? avatarUrlOverride;
  final Map<String, String>? avatarHeadersOverride;
  final Future<void> Function()? onSignOut;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late UserProfile _profile;
  bool _isModerator = false;
  bool _needsModeratorVerification = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _loadModeratorStatus();
  }

  Future<void> _loadModeratorStatus() async {
    try {
      final moderator = await widget.repository.isModerator();
      if (mounted) setState(() => _isModerator = moderator);
      if (!moderator) {
        final hasRole = widget.repository.hasModeratorRole;
        if (mounted) setState(() => _needsModeratorVerification = hasRole);
      }
    } catch (_) {}
  }

  void _profileChanged(UserProfile profile) {
    if (!mounted) return;
    setState(() => _profile = profile);
    widget.onProfileChanged?.call(profile);
  }

  String get _email =>
      widget.emailOverride ??
      Supabase.instance.client.auth.currentUser?.email ??
      '';

  bool get _hasPasswordSignIn {
    final override = widget.hasPasswordSignInOverride;
    if (override != null) return override;

    final user = Supabase.instance.client.auth.currentUser;
    final identities = user?.identities;
    if (identities != null && identities.isNotEmpty) {
      return identities.any((identity) => identity.provider == 'email');
    }
    return user?.appMetadata['provider'] != 'google';
  }

  Future<void> _openAccount() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _AccountProfileSettingsScreen(
        profile: _profile,
        email: _email,
        repository: widget.repository,
        onProfileChanged: _profileChanged,
        onSignOut: widget.onSignOut,
      ),
    ),
  );

  Future<void> _openPreferences() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _PreferencesSettingsScreen(
        profile: _profile,
        repository: widget.repository,
        locationService: widget.locationService ?? const LocationService(),
        onProfileChanged: _profileChanged,
        onAssistantEnabledChanged: widget.onAssistantEnabledChanged,
      ),
    ),
  );

  Future<void> _openSecurity() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _SecuritySettingsScreen(
        repository: widget.repository,
        hasPasswordSignIn: _hasPasswordSignIn,
      ),
    ),
  );

  Future<void> _openPrivacy() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _PrivacyScreen(
        profile: _profile,
        repository: widget.repository,
        onProfileChanged: _profileChanged,
      ),
    ),
  );

  Future<void> _openAbout() => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const _AboutScreen()));

  Future<void> _openNotifications() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          NotificationPreferencesScreen(repository: widget.repository),
    ),
  );

  Future<void> _openRecommendations() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          RecommendationSettingsScreen(repository: widget.repository),
    ),
  );

  Future<void> _openModeration() async {
    if (!_isModerator) {
      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              ModeratorVerificationScreen(repository: widget.repository),
        ),
      );
      if (!mounted || verified != true) return;
      await _loadModeratorStatus();
      if (!mounted || !_isModerator) return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ModerationDashboardScreen(repository: widget.repository),
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
    if (!profile.hasAvatar) return null;
    try {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      return token == null || token.isEmpty
          ? null
          : {'Authorization': 'Bearer $token'};
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayName = _profile.displayName.trim().isEmpty
        ? 'Community member'
        : _profile.displayName.trim();
    final username = _profile.username.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const Key('profile-settings-hub'),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(3, 4, 3, 24),
                      child: Row(
                        children: [
                          ProfileAvatar(
                            key: const Key('settings-profile-avatar'),
                            profile: _profile,
                            imageUrl: _avatarUrlFor(_profile),
                            headers: _avatarHeadersFor(_profile),
                            size: 48,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  username.isNotEmpty
                                      ? '@$username'
                                      : (_email.isEmpty
                                            ? 'Your account'
                                            : _email),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const AppSettingsHeading('Account'),
                    AppSettingsGroup(
                      children: [
                        AppSettingsRow(
                          key: const Key('settings-account-row'),
                          icon: CupertinoIcons.person_crop_circle,
                          title: 'Account & profile',
                          onTap: _openAccount,
                        ),
                        AppSettingsRow(
                          key: const Key('settings-security-row'),
                          icon: CupertinoIcons.lock_shield,
                          title: 'Security',
                          onTap: _openSecurity,
                        ),
                        AppSettingsRow(
                          key: const Key('settings-privacy-row'),
                          icon: CupertinoIcons.hand_raised,
                          title: 'Privacy',
                          onTap: _openPrivacy,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const AppSettingsHeading('Preferences'),
                    AppSettingsGroup(
                      children: [
                        ListenableBuilder(
                          listenable: AppearanceController.instance,
                          builder: (context, _) => AppSettingsRow(
                            key: const Key('settings-appearance-row'),
                            icon: CupertinoIcons.circle_lefthalf_fill,
                            title: 'Appearance',
                            value: AppearanceController.instance.label,
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const AppearanceSettingsScreen(),
                              ),
                            ),
                          ),
                        ),
                        AppSettingsRow(
                          key: const Key('settings-preferences-row'),
                          icon: CupertinoIcons.slider_horizontal_3,
                          title: 'Preferences & discovery',
                          onTap: _openPreferences,
                        ),
                        AppSettingsRow(
                          key: const Key('settings-notifications-row'),
                          icon: CupertinoIcons.bell,
                          title: 'Notifications',
                          onTap: _openNotifications,
                        ),
                        AppSettingsRow(
                          key: const Key('settings-recommendations-row'),
                          icon: CupertinoIcons.line_horizontal_3_decrease,
                          title: 'Recommendations',
                          onTap: _openRecommendations,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    AppSettingsGroup(
                      children: [
                        if (_isModerator || _needsModeratorVerification)
                          AppSettingsRow(
                            key: const Key('settings-moderation-row'),
                            icon: CupertinoIcons.shield,
                            title: _isModerator
                                ? 'Moderation dashboard'
                                : 'Verify moderator access',
                            onTap: _openModeration,
                          ),
                        AppSettingsRow(
                          key: const Key('settings-about-row'),
                          icon: CupertinoIcons.info_circle,
                          title: 'About Gather2Gether',
                          onTap: _openAbout,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountProfileSettingsScreen extends StatefulWidget {
  const _AccountProfileSettingsScreen({
    required this.profile,
    required this.email,
    required this.repository,
    required this.onProfileChanged,
    this.onSignOut,
  });

  final UserProfile profile;
  final String email;
  final ProfileRepository repository;
  final ValueChanged<UserProfile> onProfileChanged;
  final Future<void> Function()? onSignOut;

  @override
  State<_AccountProfileSettingsScreen> createState() =>
      _AccountProfileSettingsScreenState();
}

class _AccountProfileSettingsScreenState
    extends State<_AccountProfileSettingsScreen> {
  late UserProfile _profile;
  bool _signingOut = false;
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  Future<void> _editProfile() async {
    await showAppSheet<UserProfile>(
      context: context,
      builder: (_) => EditProfileScreen(
        asSheet: true,
        profile: _profile,
        repository: widget.repository,
        onProfileChanged: (profile) {
          if (!mounted) return;
          setState(() => _profile = profile);
          widget.onProfileChanged(profile);
        },
      ),
    );
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      final callback = widget.onSignOut;
      if (callback != null) {
        await callback();
      } else {
        await Supabase.instance.client.auth.signOut();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign out. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingAccount = true);
    try {
      await widget.repository.deleteAccount();
    } on ProfileApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete your account.')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = _profile.displayName.trim().isEmpty
        ? 'Community member'
        : _profile.displayName.trim();
    final username = _profile.username.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Account & profile')),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const Key('account-profile-settings-list'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SettingsPageIntro(
                      icon: CupertinoIcons.person_crop_circle,
                      title: 'Your public identity',
                      description:
                          'Keep your name, username, bio and home city current for the community.',
                    ),
                    const SizedBox(height: 24),
                    const AppSettingsHeading('Profile'),
                    AppSettingsGroup(
                      children: [
                        AppSettingsRow(
                          key: const Key('settings-edit-profile-row'),
                          icon: CupertinoIcons.pencil,
                          title: 'Edit public profile',
                          subtitle: username.isEmpty
                              ? name
                              : '$name · @$username',
                          onTap: _editProfile,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const AppSettingsHeading('Sign-in details'),
                    AppSettingsGroup(
                      children: [
                        _SettingsInformationRow(
                          icon: CupertinoIcons.mail,
                          title: 'Email',
                          value: widget.email.isEmpty
                              ? 'Unavailable'
                              : widget.email,
                        ),
                        _SettingsInformationRow(
                          icon: CupertinoIcons.at,
                          title: 'Username',
                          value: username.isEmpty ? 'Not set' : '@$username',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    AppSurface(
                      borderRadius: 18,
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            CupertinoIcons.eye,
                            color: colors.onSurfaceVariant,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your profile and community posts are public. Your email and approximate home coordinates are never shown.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    OutlinedButton.icon(
                      key: const Key('settings-sign-out-button'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                        side: BorderSide(
                          color: colors.error.withValues(alpha: 0.35),
                        ),
                      ),
                      onPressed: _signingOut ? null : _signOut,
                      icon: _signingOut
                          ? const CupertinoActivityIndicator()
                          : const Icon(CupertinoIcons.square_arrow_right),
                      label: Text(_signingOut ? 'Signing out…' : 'Sign out'),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      key: const Key('settings-delete-account-button'),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.error,
                      ),
                      onPressed: _signingOut || _deletingAccount
                          ? null
                          : _deleteAccount,
                      icon: _deletingAccount
                          ? const CupertinoActivityIndicator()
                          : const Icon(CupertinoIcons.delete),
                      label: Text(
                        _deletingAccount
                            ? 'Deleting account…'
                            : 'Delete account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delete your account?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'This permanently removes your profile, hosted events, RSVPs, posts, photos, conversations, and feedback. This cannot be undone.',
        ),
        const SizedBox(height: 16),
        const Text('Type DELETE to confirm.'),
        const SizedBox(height: 8),
        TextField(
          key: const Key('delete-account-confirmation-field'),
          controller: _controller,
          autofocus: true,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'DELETE'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Keep account'),
      ),
      FilledButton(
        key: const Key('confirm-delete-account-button'),
        onPressed: () =>
            Navigator.pop(context, _controller.text.trim() == 'DELETE'),
        child: const Text('Delete permanently'),
      ),
    ],
  );
}

class _PreferencesSettingsScreen extends StatefulWidget {
  const _PreferencesSettingsScreen({
    required this.profile,
    required this.repository,
    required this.locationService,
    required this.onProfileChanged,
    required this.onAssistantEnabledChanged,
  });

  final UserProfile profile;
  final ProfileRepository repository;
  final LocationService locationService;
  final ValueChanged<UserProfile> onProfileChanged;
  final ValueChanged<bool> onAssistantEnabledChanged;

  @override
  State<_PreferencesSettingsScreen> createState() =>
      _PreferencesSettingsScreenState();
}

class _PreferencesSettingsScreenState
    extends State<_PreferencesSettingsScreen> {
  static const _radiusOptions = [5.0, 10.0, 25.0, 50.0];

  late UserProfile _profile;
  late double _radiusKm;
  double? _latitude;
  double? _longitude;
  late double _savedRadiusKm;
  double? _savedLatitude;
  double? _savedLongitude;
  late bool _assistantEnabled;
  late Set<String> _interests;
  late Set<String> _savedInterests;
  late Set<String> _accessibilityPreferences;
  late Set<String> _savedAccessibilityPreferences;
  bool _saving = false;
  bool _locating = false;
  bool _assistantSaving = false;
  bool _locationPendingSave = false;

  bool get _hasChanges =>
      _radiusKm != _savedRadiusKm ||
      _latitude != _savedLatitude ||
      _longitude != _savedLongitude ||
      _personalizationHasChanges;

  bool get _personalizationHasChanges =>
      !_interests.containsAll(_savedInterests) ||
      !_savedInterests.containsAll(_interests) ||
      !_accessibilityPreferences.containsAll(_savedAccessibilityPreferences) ||
      !_savedAccessibilityPreferences.containsAll(_accessibilityPreferences);

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _resetFrom(_profile);
  }

  void _resetFrom(UserProfile profile) {
    _radiusKm = profile.preferredRadiusKm;
    _latitude = profile.approximateLatitude;
    _longitude = profile.approximateLongitude;
    _savedRadiusKm = profile.preferredRadiusKm;
    _savedLatitude = profile.approximateLatitude;
    _savedLongitude = profile.approximateLongitude;
    _assistantEnabled = profile.assistantEnabled;
    _interests = {...profile.interests};
    _savedInterests = {...profile.interests};
    _accessibilityPreferences = {...profile.accessibilityPreferences};
    _savedAccessibilityPreferences = {...profile.accessibilityPreferences};
    _locationPendingSave = false;
  }

  Future<void> _updateLocation() async {
    if (_locating || _saving) return;
    setState(() => _locating = true);
    try {
      final position = await widget.locationService.currentPosition();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationPendingSave = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Area ready. Tap Save to keep it.')),
      );
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          action: failure.canOpenSettings
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: widget.locationService.openSettings,
                )
              : null,
        ),
      );
    } catch (_) {
      _showError('Could not update your home area.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _savePreferences() async {
    if (_saving || _locating || !_hasChanges) return;
    setState(() => _saving = true);
    try {
      await widget.repository.completeOnboarding(
        interests: _interests.toList(growable: false),
        accessibilityPreferences: _accessibilityPreferences.toList(
          growable: false,
        ),
        radiusKm: _radiusKm,
        latitude: _latitude,
        longitude: _longitude,
      );
      if (!mounted) return;
      final updated = _profile.copyWith(
        preferredRadiusKm: _radiusKm,
        approximateLatitude: _latitude,
        approximateLongitude: _longitude,
        interests: _interests.toList(growable: false),
        accessibilityPreferences: _accessibilityPreferences.toList(
          growable: false,
        ),
      );
      setState(() {
        _profile = updated;
        _savedRadiusKm = _radiusKm;
        _savedLatitude = _latitude;
        _savedLongitude = _longitude;
        _savedInterests = {..._interests};
        _savedAccessibilityPreferences = {..._accessibilityPreferences};
        _locationPendingSave = false;
      });
      widget.onProfileChanged(updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preferences saved.')));
    } catch (_) {
      _showError('Could not save your preferences.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setAssistantEnabled(bool enabled) async {
    if (_assistantSaving) return;
    final previous = _assistantEnabled;
    setState(() {
      _assistantEnabled = enabled;
      _assistantSaving = true;
    });
    widget.onAssistantEnabledChanged(enabled);
    try {
      await widget.repository.updateAssistantEnabled(enabled);
      if (!mounted) return;
      final updated = _profile.copyWith(assistantEnabled: enabled);
      setState(() => _profile = updated);
      widget.onProfileChanged(updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _assistantEnabled = previous);
      widget.onAssistantEnabledChanged(previous);
      _showError('Could not update Gather Guide settings.');
    } finally {
      if (mounted) setState(() => _assistantSaving = false);
    }
  }

  Future<void> _chooseRadius() async {
    final selected = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => AppSettingsPicker(
          title: 'Search distance',
          multiple: false,
          selected: {_radiusKm.toString()},
          groups: [
            AppSettingsOptionGroup({
              for (final radius in _radiusOptions)
                radius.toString(): '${radius.toInt()} km',
            }),
          ],
        ),
      ),
    );
    if (mounted && selected != null) {
      setState(() => _radiusKm = double.parse(selected.single));
    }
  }

  Future<void> _chooseInterests() async {
    final selected = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => AppSettingsPicker(
          title: 'Interests',
          description: 'Choose the activities you enjoy.',
          selected: _interests,
          groups: [
            AppSettingsOptionGroup({
              for (final interest in memberInterestOptions) interest: interest,
            }),
          ],
        ),
      ),
    );
    if (mounted && selected != null) setState(() => _interests = selected);
  }

  Future<void> _chooseEventDetails() async {
    final selected = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => AppSettingsPicker(
          title: 'Event preferences',
          description: 'Choose details that matter when finding an event.',
          selected: _accessibilityPreferences,
          groups: const [AppSettingsOptionGroup(memberAccessibilityOptions)],
        ),
      ),
    );
    if (mounted && selected != null) {
      setState(() => _accessibilityPreferences = selected);
    }
  }

  String _selectionSummary(
    Set<String> selection,
    Map<String, String> options,
  ) => selection.isEmpty
      ? 'Not selected'
      : '${selection.take(2).map((value) => options[value] ?? value).join(', ')}'
            '${selection.length > 2 ? ' + ${selection.length - 2} more' : ''}';

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
        actions: [
          AppSaveAction(
            buttonKey: const Key('save-preferences-button'),
            saving: _saving,
            onPressed: _saving || _locating || !_hasChanges
                ? null
                : _savePreferences,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const Key('profile-preferences-list'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppSettingsHeading('Nearby'),
                    AppSettingsGroup(
                      children: [
                        AppSettingsRow(
                          key: const Key('preferences-distance'),
                          icon: CupertinoIcons.location,
                          title: 'Search distance',
                          value: '${_radiusKm.toInt()} km',
                          onTap: _saving ? null : _chooseRadius,
                        ),
                        AppSettingsRow(
                          icon: CupertinoIcons.map_pin_ellipse,
                          title: 'Home area',
                          subtitle: _locationPendingSave
                              ? 'New area ready to save'
                              : _latitude == null || _longitude == null
                              ? 'Use your current location'
                              : _profile.city.trim().isEmpty
                              ? 'Approximate location saved'
                              : _profile.city,
                          trailing: _locating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : null,
                          onTap: _saving || _locating ? null : _updateLocation,
                        ),
                      ],
                    ),
                    const AppSettingsCaption(
                      'Your home area is approximate. Tap it to update your location.',
                    ),
                    const SizedBox(height: 24),
                    const AppSettingsHeading('What you enjoy'),
                    AppSettingsGroup(
                      children: [
                        AppSettingsRow(
                          key: const Key('preferences-interests'),
                          icon: CupertinoIcons.heart,
                          title: 'Interests',
                          subtitle: _selectionSummary(_interests, {
                            for (final interest in memberInterestOptions)
                              interest: interest,
                          }),
                          onTap: _saving ? null : _chooseInterests,
                        ),
                        AppSettingsRow(
                          key: const Key('preferences-event-details'),
                          icon: CupertinoIcons.person_2,
                          title: 'Event preferences',
                          subtitle: _selectionSummary(
                            _accessibilityPreferences,
                            memberAccessibilityOptions,
                          ),
                          onTap: _saving ? null : _chooseEventDetails,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const AppSettingsHeading('In the app'),
                    AppSettingsGroup(
                      dividerIndent: 16,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 3,
                          ),
                          title: const Text('Gather Guide'),
                          value: _assistantEnabled,
                          onChanged: _assistantSaving
                              ? null
                              : _setAssistantEnabled,
                        ),
                      ],
                    ),
                    const AppSettingsCaption(
                      'Show the chat shortcut for nearby events and app help.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecuritySettingsScreen extends StatelessWidget {
  const _SecuritySettingsScreen({
    required this.repository,
    required this.hasPasswordSignIn,
  });

  final ProfileRepository repository;
  final bool hasPasswordSignIn;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: SafeArea(
        top: false,
        child: ListView(
          key: const Key('security-settings-list'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingsPageIntro(
                      icon: CupertinoIcons.lock_shield,
                      title: 'Keep your account secure',
                      description: hasPasswordSignIn
                          ? 'Manage your password and review how this device protects your session.'
                          : 'Review your account sign-in and how this device protects your session.',
                    ),
                    const SizedBox(height: 24),
                    const AppSettingsHeading('Sign-in security'),
                    AppSettingsGroup(
                      children: [
                        if (hasPasswordSignIn)
                          AppSettingsRow(
                            key: const Key('settings-change-password-row'),
                            icon: CupertinoIcons.lock_rotation,
                            title: 'Change password',
                            subtitle:
                                'Choose a strong, unique account password',
                            onTap: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => ProfileChangePasswordScreen(
                                  repository: repository,
                                ),
                              ),
                            ),
                          )
                        else
                          const _SettingsInformationRow(
                            icon: CupertinoIcons
                                .person_crop_circle_badge_checkmark,
                            title: 'Account sign-in',
                            value:
                                'Your sign-in provider manages your password. Gather2Gether does not receive it.',
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    AppSurface(
                      borderRadius: 18,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_shield,
                            color: colors.onSurfaceVariant,
                            size: 20,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Secure session',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Your signed-in session is stored securely on this device.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyScreen extends StatefulWidget {
  const _PrivacyScreen({
    required this.profile,
    required this.repository,
    required this.onProfileChanged,
  });

  final UserProfile profile;
  final ProfileRepository repository;
  final ValueChanged<UserProfile> onProfileChanged;

  @override
  State<_PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<_PrivacyScreen> {
  late bool _pastEventsPublic;
  bool _savingPastVisibility = false;

  @override
  void initState() {
    super.initState();
    _pastEventsPublic = widget.profile.showPastEventsPublic;
  }

  Future<void> _setPastEventsPublic(bool isPublic) async {
    if (_savingPastVisibility) return;
    final previous = _pastEventsPublic;
    setState(() {
      _pastEventsPublic = isPublic;
      _savingPastVisibility = true;
    });
    try {
      final updated = await widget.repository.updatePastEventsVisibility(
        isPublic,
      );
      if (!mounted) return;
      setState(() => _pastEventsPublic = updated.showPastEventsPublic);
      widget.onProfileChanged(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPublic
                ? 'Past events are now visible on your profile.'
                : 'Past events are now private.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _pastEventsPublic = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update event privacy.')),
      );
    } finally {
      if (mounted) setState(() => _savingPastVisibility = false);
    }
  }

  Future<void> _openBlockedUsers() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _BlockedProfilesScreen(repository: widget.repository),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy')),
    body: SafeArea(
      top: false,
      child: ListView(
        key: const Key('privacy-settings-list'),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SettingsPageIntro(
                    icon: CupertinoIcons.hand_raised,
                    title: 'Privacy',
                    description:
                        'See what stays private and what you choose to share with the community.',
                  ),
                  const SizedBox(height: 24),
                  const AppSettingsHeading('Profile activity'),
                  AppSettingsGroup(
                    children: [
                      SwitchListTile.adaptive(
                        key: const Key('past-events-visibility-toggle'),
                        contentPadding: const EdgeInsets.fromLTRB(14, 7, 12, 7),
                        secondary: const _SettingsIcon(
                          icon: CupertinoIcons.clock,
                        ),
                        title: const Text(
                          'Show past events',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Show events you hosted or confirmed attending. Upcoming events you host remain public.',
                        ),
                        value: _pastEventsPublic,
                        onChanged: _savingPastVisibility
                            ? null
                            : _setPastEventsPublic,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const AppSettingsHeading('Community safety'),
                  AppSettingsGroup(
                    children: [
                      AppSettingsRow(
                        key: const Key('blocked-users-settings-row'),
                        icon: CupertinoIcons.person_crop_circle_badge_xmark,
                        title: 'Blocked members',
                        subtitle: 'Review and unblock members',
                        onTap: _openBlockedUsers,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const AppSettingsHeading('Your information'),
                  const _InformationCard(
                    data: _InformationCardData(
                      icon: CupertinoIcons.location,
                      title: 'Approximate home area',
                      description:
                          'Coordinates are rounded to about 1 km before storage. Location history is not stored or shown on your profile.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _InformationCard(
                    data: _InformationCardData(
                      icon: CupertinoIcons.chat_bubble_2,
                      title: 'Gather Guide conversations',
                      description:
                          'Your assistant conversations stay private to your account and can be cleared from Gather Guide.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const _InformationCard(
                    data: _InformationCardData(
                      icon: CupertinoIcons.person_2,
                      title: 'Community sharing',
                      description:
                          'Your profile, posts and any place you tag are visible to the community. Your email is never displayed.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _BlockedProfilesScreen extends StatefulWidget {
  const _BlockedProfilesScreen({required this.repository});

  final ProfileRepository repository;

  @override
  State<_BlockedProfilesScreen> createState() => _BlockedProfilesScreenState();
}

class _BlockedProfilesScreenState extends State<_BlockedProfilesScreen> {
  List<BlockedProfile>? _profiles;
  String? _error;
  final Set<String> _updatingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _profiles = null;
      _error = null;
    });
    try {
      final profiles = await widget.repository.blockedProfiles();
      if (mounted) setState(() => _profiles = profiles);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load blocked members.');
    }
  }

  Future<void> _unblock(BlockedProfile profile) async {
    if (_updatingIds.contains(profile.id)) return;
    setState(() => _updatingIds.add(profile.id));
    try {
      await widget.repository.setBlocked(profile.id, false);
      if (!mounted) return;
      setState(() {
        _profiles = _profiles
            ?.where((item) => item.id != profile.id)
            .toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${profile.displayName} unblocked.')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not unblock this member.')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingIds.remove(profile.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Blocked members')),
    body: _profiles == null && _error == null
        ? const Center(child: CupertinoActivityIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                const SizedBox(height: 8),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        : _profiles!.isEmpty
        ? const Center(child: Text('You have not blocked anyone.'))
        : ListView.separated(
            key: const Key('blocked-users-list'),
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: _profiles!.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final profile = _profiles![index];
              final initial = profile.displayName.trim().isEmpty
                  ? '?'
                  : String.fromCharCode(
                      profile.displayName.trim().runes.first,
                    ).toUpperCase();
              return ListTile(
                leading: CircleAvatar(child: Text(initial)),
                title: Text(profile.displayName),
                subtitle: profile.username.isEmpty
                    ? null
                    : Text('@${profile.username}'),
                trailing: TextButton(
                  onPressed: _updatingIds.contains(profile.id)
                      ? null
                      : () => _unblock(profile),
                  child: Text(
                    _updatingIds.contains(profile.id)
                        ? 'Unblocking…'
                        : 'Unblock',
                  ),
                ),
              );
            },
          ),
  );
}

class _AboutScreen extends StatelessWidget {
  const _AboutScreen();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About Gather2Gether')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppBrandMark(size: 72)),
                    const SizedBox(height: 16),
                    Text(
                      'Gather2Gether',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Find activities and meet people nearby.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const SupportLinks(),
                    const SizedBox(height: 14),
                    AppSurface(
                      borderRadius: 18,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'About the app',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'Discover local events, make plans, and share recommendations with your community.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppSurface(
                      borderRadius: 18,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            CupertinoIcons.heart,
                            size: 19,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Be kind, protect personal information and meet in public places when connecting with someone new.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPageIntro extends StatelessWidget {
  const _SettingsPageIntro({
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title, description;
  @override
  Widget build(BuildContext context) => AppSettingsCaption(description);
}

class _SettingsInformationRow extends StatelessWidget {
  const _SettingsInformationRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) =>
      AppSettingsRow(icon: icon, title: title, subtitle: value);
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary);
}

class _InformationCardData {
  const _InformationCardData({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({required this.data});

  final _InformationCardData data;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsIcon(icon: data.icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 5),
                Text(
                  data.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
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
