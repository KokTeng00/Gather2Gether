import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/location/location_service.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/edit_profile_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_change_password_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _formatRadius(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({
    required this.profile,
    required this.repository,
    required this.onAssistantEnabledChanged,
    this.onProfileChanged,
    this.locationService,
    this.emailOverride,
    this.hasPasswordSignInOverride,
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
  final Future<void> Function()? onSignOut;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late UserProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
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

  Future<void> _openPrivacy() => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const _PrivacyScreen()));

  Future<void> _openAbout() => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const _AboutScreen()));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayName = _profile.displayName.trim().isEmpty
        ? 'Community member'
        : _profile.displayName.trim();
    final username = _profile.username.trim();
    final initial = displayName.characters.first.toUpperCase();
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
                    AppSurface(
                      color: colors.primaryContainer.withValues(alpha: 0.68),
                      borderColor: colors.primary.withValues(alpha: 0.16),
                      borderRadius: 24,
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              initial,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: colors.onPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
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
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: colors.onPrimaryContainer,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  username.isNotEmpty
                                      ? '@$username'
                                      : (_email.isEmpty
                                            ? 'Your account'
                                            : _email),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onPrimaryContainer
                                            .withValues(alpha: 0.74),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    const _SettingsSectionLabel('Your account'),
                    const SizedBox(height: 8),
                    _SettingsGroup(
                      children: [
                        _SettingsRow(
                          key: const Key('settings-account-row'),
                          icon: CupertinoIcons.person_crop_circle_fill,
                          title: 'Account & profile',
                          description: 'Public identity, email and sign out',
                          onTap: _openAccount,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const _SettingsSectionLabel('Experience'),
                    const SizedBox(height: 8),
                    _SettingsGroup(
                      children: [
                        _SettingsRow(
                          key: const Key('settings-preferences-row'),
                          icon: CupertinoIcons.slider_horizontal_3,
                          title: 'Preferences & discovery',
                          description:
                              'Nearby radius, home area and Gather Guide',
                          value:
                              '${_formatRadius(_profile.preferredRadiusKm)} km',
                          onTap: _openPreferences,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const _SettingsSectionLabel('Safety & information'),
                    const SizedBox(height: 8),
                    _SettingsGroup(
                      children: [
                        _SettingsRow(
                          key: const Key('settings-security-row'),
                          icon: CupertinoIcons.lock_shield_fill,
                          title: 'Security',
                          description: _hasPasswordSignIn
                              ? 'Password and session protection'
                              : 'Google sign-in and session protection',
                          onTap: _openSecurity,
                        ),
                        _SettingsRow(
                          key: const Key('settings-privacy-row'),
                          icon: CupertinoIcons.hand_raised_fill,
                          title: 'Privacy',
                          description:
                              'Location, conversations and public posts',
                          onTap: _openPrivacy,
                        ),
                        _SettingsRow(
                          key: const Key('settings-about-row'),
                          icon: CupertinoIcons.info_circle_fill,
                          title: 'About Gather2Gether',
                          description: 'Our community-first approach',
                          onTap: _openAbout,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Settings are private to your account unless a page says otherwise.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
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

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  Future<void> _editProfile() async {
    await Navigator.of(context).push<UserProfile>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => EditProfileScreen(
          profile: _profile,
          repository: widget.repository,
          onProfileChanged: (profile) {
            if (!mounted) return;
            setState(() => _profile = profile);
            widget.onProfileChanged(profile);
          },
        ),
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
                      icon: CupertinoIcons.person_crop_circle_fill,
                      title: 'Your public identity',
                      description:
                          'Keep your name, username, bio and home city current for the community.',
                    ),
                    const SizedBox(height: 24),
                    const _SettingsSectionLabel('Profile'),
                    const SizedBox(height: 8),
                    _SettingsGroup(
                      children: [
                        _SettingsRow(
                          key: const Key('settings-edit-profile-row'),
                          icon: CupertinoIcons.pencil_circle_fill,
                          title: 'Edit public profile',
                          description: username.isEmpty
                              ? name
                              : '$name · @$username',
                          onTap: _editProfile,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const _SettingsSectionLabel('Sign-in details'),
                    const SizedBox(height: 8),
                    _SettingsGroup(
                      children: [
                        _SettingsInformationRow(
                          icon: CupertinoIcons.mail_solid,
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
                      color: colors.primaryContainer.withValues(alpha: 0.52),
                      borderColor: colors.primary.withValues(alpha: 0.13),
                      borderRadius: 18,
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            CupertinoIcons.eye_fill,
                            color: colors.onPrimaryContainer,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your profile and community posts are public. Your email and approximate home coordinates are never shown.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onPrimaryContainer),
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
  bool _saving = false;
  bool _locating = false;
  bool _assistantSaving = false;
  bool _locationPendingSave = false;

  bool get _hasChanges =>
      _radiusKm != _savedRadiusKm ||
      _latitude != _savedLatitude ||
      _longitude != _savedLongitude;

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
        const SnackBar(content: Text('Area ready. Save it below to keep it.')),
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
      final updated = await widget.repository.updateDiscoveryPreferences(
        preferredRadiusKm: _radiusKm,
        latitude: _latitude,
        longitude: _longitude,
      );
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _savedRadiusKm = updated.preferredRadiusKm;
        _savedLatitude = updated.approximateLatitude;
        _savedLongitude = updated.approximateLongitude;
        _radiusKm = updated.preferredRadiusKm;
        _latitude = updated.approximateLatitude;
        _longitude = updated.approximateLongitude;
        _locationPendingSave = false;
      });
      widget.onProfileChanged(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Discovery preferences saved.')),
      );
    } catch (_) {
      _showError('Could not save your discovery preferences.');
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
          TextButton(
            key: const Key('save-preferences-button'),
            onPressed: _saving || _locating || !_hasChanges
                ? null
                : _savePreferences,
            child: Text(_saving ? 'Saving…' : 'Save'),
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
                    const ProfileSectionHeader(
                      title: 'Discovery',
                      subtitle: 'Choose the area used for nearby events.',
                    ),
                    const SizedBox(height: 11),
                    ProfileNearbyPreferencesCard(
                      radiusKm: _radiusKm,
                      radiusOptions: _radiusOptions,
                      city: _profile.city,
                      hasLocation: _latitude != null && _longitude != null,
                      locationPendingSave: _locationPendingSave,
                      locating: _locating,
                      disabled: _saving,
                      onRadiusChanged: (value) =>
                          setState(() => _radiusKm = value),
                      onLocationPressed: _updateLocation,
                    ),
                    const SizedBox(height: 26),
                    const ProfileSectionHeader(
                      title: 'Gather Guide',
                      subtitle:
                          'Choose whether the private assistant is available.',
                    ),
                    const SizedBox(height: 11),
                    ProfileGuidePreferenceCard(
                      enabled: _assistantEnabled,
                      saving: _assistantSaving,
                      onChanged: _setAssistantEnabled,
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
                      icon: CupertinoIcons.lock_shield_fill,
                      title: 'Keep your account secure',
                      description: hasPasswordSignIn
                          ? 'Manage your password and review how this device protects your session.'
                          : 'Review your Google sign-in and how this device protects your session.',
                    ),
                    const SizedBox(height: 24),
                    const _SettingsSectionLabel('Sign-in security'),
                    const SizedBox(height: 8),
                    _SettingsGroup(
                      children: [
                        if (hasPasswordSignIn)
                          _SettingsRow(
                            key: const Key('settings-change-password-row'),
                            icon: CupertinoIcons.lock_rotation,
                            title: 'Change password',
                            description:
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
                            title: 'Google sign-in',
                            value:
                                'Your sign-in password is managed by your Google Account.',
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    AppSurface(
                      color: colors.secondaryContainer.withValues(alpha: 0.58),
                      borderColor: colors.secondary.withValues(alpha: 0.2),
                      borderRadius: 20,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_shield_fill,
                            color: colors.onSecondaryContainer,
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
                                        color: colors.onSecondaryContainer,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Your signed-in session is stored securely on this device.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSecondaryContainer,
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

class _PrivacyScreen extends StatelessWidget {
  const _PrivacyScreen();

  @override
  Widget build(BuildContext context) => _InformationalSettingsScreen(
    title: 'Privacy',
    introIcon: CupertinoIcons.hand_raised_fill,
    introTitle: 'Privacy by design',
    introDescription:
        'See what stays private and what you choose to share with the community.',
    sectionTitle: 'Your information',
    cards: const [
      _InformationCardData(
        icon: CupertinoIcons.location_fill,
        title: 'Approximate home area',
        description:
            'Coordinates are rounded to about 1 km before storage. Location history is not stored or shown on your profile.',
      ),
      _InformationCardData(
        icon: CupertinoIcons.chat_bubble_2_fill,
        title: 'Gather Guide conversations',
        description:
            'Your assistant conversations stay private to your account and can be cleared from Gather Guide.',
      ),
      _InformationCardData(
        icon: CupertinoIcons.person_2_fill,
        title: 'Community sharing',
        description:
            'Your profile, posts and any place you tag are visible to the community. Your email is never displayed.',
      ),
    ],
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
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Real plans. Nearby people. A stronger local community.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    AppSurface(
                      borderRadius: 22,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Built for belonging',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'Gather2Gether helps people discover activities, share local knowledge and turn online connections into welcoming real-world moments.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppSurface(
                      color: colors.primaryContainer.withValues(alpha: 0.5),
                      borderColor: colors.primary.withValues(alpha: 0.14),
                      borderRadius: 20,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            CupertinoIcons.heart_fill,
                            size: 19,
                            color: colors.onPrimaryContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Be kind, protect personal information and meet in public places when connecting with someone new.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onPrimaryContainer),
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

class _InformationalSettingsScreen extends StatelessWidget {
  const _InformationalSettingsScreen({
    required this.title,
    required this.introIcon,
    required this.introTitle,
    required this.introDescription,
    required this.sectionTitle,
    required this.cards,
  });

  final String title;
  final IconData introIcon;
  final String introTitle;
  final String introDescription;
  final String sectionTitle;
  final List<_InformationCardData> cards;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SettingsPageIntro(
                    icon: introIcon,
                    title: introTitle,
                    description: introDescription,
                  ),
                  const SizedBox(height: 24),
                  _SettingsSectionLabel(sectionTitle),
                  const SizedBox(height: 8),
                  for (var index = 0; index < cards.length; index++) ...[
                    _InformationCard(data: cards[index]),
                    if (index != cards.length - 1) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingsPageIntro extends StatelessWidget {
  const _SettingsPageIntro({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      color: colors.primaryContainer.withValues(alpha: 0.68),
      borderColor: colors.primary.withValues(alpha: 0.16),
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: colors.onPrimary, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onPrimaryContainer.withValues(alpha: 0.78),
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

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
      ),
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppSurface(
    borderRadius: 22,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index != children.length - 1)
            const Divider(height: 1, indent: 68),
        ],
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.value,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$title. $description',
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 7, 12, 7),
        leading: _SettingsIcon(icon: icon),
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null) ...[
              Text(
                value!,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 7),
            ],
            Icon(
              CupertinoIcons.chevron_forward,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
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
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
    leading: _SettingsIcon(icon: icon),
    title: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
    ),
  );
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon});

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
      child: Icon(icon, color: colors.onPrimaryContainer, size: 20),
    );
  }
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
      borderRadius: 20,
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
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
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
