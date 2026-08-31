import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/location/location_service.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/core/validation/validators.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/presentation/profile_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.assistantEnabled,
    required this.onAssistantEnabledChanged,
    this.repository,
    this.locationService,
    this.emailOverride,
    this.onSignOut,
    super.key,
  });

  final bool assistantEnabled;
  final ValueChanged<bool> onAssistantEnabledChanged;
  final ProfileRepository? repository;
  final LocationService? locationService;
  final String? emailOverride;
  final Future<void> Function()? onSignOut;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _radiusOptions = [5.0, 10.0, 25.0, 50.0];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cityController = TextEditingController();
  late final ProfileRepository _profiles;
  late final LocationService _location;

  double _radiusKm = 10;
  double? _latitude;
  double? _longitude;
  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  bool _assistantEnabled = true;
  bool _assistantSaving = false;
  bool _locationPendingSave = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _profiles = widget.repository ?? ProfileRepository();
    _location = widget.locationService ?? const LocationService();
    _assistantEnabled = widget.assistantEnabled;
    _load();
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assistantEnabled != widget.assistantEnabled &&
        !_assistantSaving) {
      _assistantEnabled = widget.assistantEnabled;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final profile = await _profiles.fetchOwnProfile();
      if (!mounted) return;
      _nameController.text = profile.displayName;
      _cityController.text = profile.city;
      _radiusKm = profile.preferredRadiusKm;
      _latitude = profile.approximateLatitude;
      _longitude = profile.approximateLongitude;
      _assistantEnabled = profile.assistantEnabled;
      _locationPendingSave = false;
      widget.onAssistantEnabledChanged(profile.assistantEnabled);
    } catch (_) {
      _loadError = 'We could not load your profile details.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateLocation() async {
    if (_locating || _saving) return;
    setState(() => _locating = true);
    try {
      final position = await _location.currentPosition();
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _locationPendingSave = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Area updated. Tap Save Changes to keep it.'),
          ),
        );
      }
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          action: failure.canOpenSettings
              ? SnackBarAction(
                  label: 'Settings',
                  onPressed: _location.openSettings,
                )
              : null,
        ),
      );
    } catch (_) {
      _showError('Could not update your home area. Please try again.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_locating) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await _profiles.updateProfile(
        displayName: _nameController.text,
        city: _cityController.text,
        preferredRadiusKm: _radiusKm,
        latitude: _latitude,
        longitude: _longitude,
      );
      if (mounted) {
        setState(() => _locationPendingSave = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile saved.')));
      }
    } catch (_) {
      _showError('Could not save your profile.');
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
      await _profiles.updateAssistantEnabled(enabled);
    } catch (_) {
      if (mounted) {
        setState(() => _assistantEnabled = previous);
        widget.onAssistantEnabledChanged(previous);
        _showError('Could not update Gather Guide settings.');
      }
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

  Future<void> _signOut() async {
    final callback = widget.onSignOut;
    if (callback != null) {
      await callback();
      return;
    }
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(
        child: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }
    if (_loadError != null) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          children: [
            const AppPageHeader(
              title: 'Profile',
              subtitle: 'Your local identity and preferences.',
            ),
            const SizedBox(height: 28),
            ProfileLoadError(message: _loadError!, onRetry: _load),
          ],
        ),
      );
    }
    final email =
        widget.emailOverride ??
        Supabase.instance.client.auth.currentUser?.email ??
        '';
    final initial = _nameController.text.trim().isEmpty
        ? '?'
        : String.fromCharCode(
            _nameController.text.trim().runes.first,
          ).toUpperCase();
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 360;

    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.zero,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 20,
                    24,
                    compact ? 16 : 20,
                    36,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppPageHeader(
                        title: 'Profile',
                        subtitle: 'Your local identity and preferences.',
                      ),
                      const SizedBox(height: 20),
                      ProfileIdentityCard(
                        initial: initial,
                        name: _nameController.text.trim(),
                        email: email,
                        city: _cityController.text.trim(),
                        radiusKm: _radiusKm,
                      ),
                      const SizedBox(height: 24),
                      const ProfileSectionHeader(
                        title: 'Personal details',
                        subtitle: 'How people in the community will know you.',
                      ),
                      const SizedBox(height: 11),
                      TextFormField(
                        controller: _nameController,
                        enabled: !_saving,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          prefixIcon: Icon(CupertinoIcons.person),
                        ),
                        validator: (value) =>
                            Validators.requiredText(value, maxLength: 80),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _cityController,
                        enabled: !_saving,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'City (optional)',
                          prefixIcon: Icon(CupertinoIcons.building_2_fill),
                        ),
                        validator: (value) {
                          if ((value?.trim().length ?? 0) > 120) {
                            return 'Use 120 characters or fewer.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      const ProfileSectionHeader(
                        title: 'Nearby preferences',
                        subtitle: 'Tune the area used to find local plans.',
                      ),
                      const SizedBox(height: 11),
                      ProfileNearbyPreferencesCard(
                        radiusKm: _radiusKm,
                        radiusOptions: _radiusOptions,
                        city: _cityController.text.trim(),
                        hasLocation: _latitude != null && _longitude != null,
                        locationPendingSave: _locationPendingSave,
                        locating: _locating,
                        disabled: _saving,
                        onRadiusChanged: (value) =>
                            setState(() => _radiusKm = value),
                        onLocationPressed: _updateLocation,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _saving || _locating ? null : _save,
                        icon: _saving
                            ? CupertinoActivityIndicator(
                                color: colors.onPrimary,
                              )
                            : const Icon(CupertinoIcons.checkmark_alt),
                        label: Text(_saving ? 'Saving…' : 'Save Changes'),
                      ),
                      const SizedBox(height: 26),
                      const ProfileSectionHeader(
                        title: 'App preferences',
                        subtitle: 'Settings that save immediately.',
                      ),
                      const SizedBox(height: 11),
                      ProfileGuidePreferenceCard(
                        enabled: _assistantEnabled,
                        saving: _assistantSaving,
                        onChanged: _setAssistantEnabled,
                      ),
                      const SizedBox(height: 20),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: colors.error,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _saving || _locating || _assistantSaving
                            ? null
                            : _signOut,
                        icon: const Icon(CupertinoIcons.square_arrow_right),
                        label: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
