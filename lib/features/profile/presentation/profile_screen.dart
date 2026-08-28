import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/location/location_service.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/core/validation/validators.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cityController = TextEditingController();
  final _profiles = ProfileRepository();
  final _location = const LocationService();

  double _radiusKm = 10;
  double? _latitude;
  double? _longitude;
  bool _loading = true;
  bool _saving = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await _profiles.fetchOwnProfile();
      _nameController.text = profile.displayName;
      _cityController.text = profile.city;
      _radiusKm = profile.preferredRadiusKm;
      _latitude = profile.approximateLatitude;
      _longitude = profile.approximateLongitude;
    } catch (_) {
      _showError('Could not load your profile.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateLocation() async {
    setState(() => _locating = true);
    try {
      final position = await _location.currentPosition();
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Area updated. Tap Save Changes to keep it.'),
          ),
        );
      }
    } on LocationFailure catch (failure) {
      _showError(failure.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
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

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final initial = _nameController.text.trim().isEmpty
        ? '?'
        : _nameController.text.trim().substring(0, 1).toUpperCase();
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          children: [
            const AppPageHeader(
              title: 'You',
              subtitle: 'Your profile and preferences.',
            ),
            const SizedBox(height: 24),
            Column(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _nameController.text,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 3),
                Text(email, style: TextStyle(color: colors.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 28),
            AppSection(
              title: 'Account',
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Display name',
                      prefixIcon: Icon(CupertinoIcons.person),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                    ),
                    validator: (value) =>
                        Validators.requiredText(value, maxLength: 80),
                  ),
                  const Divider(indent: 52),
                  TextFormField(
                    controller: _cityController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'City (optional)',
                      prefixIcon: Icon(CupertinoIcons.building_2_fill),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AppSection(
              title: 'Discovery distance',
              footer:
                  'This controls the default area used when finding nearby events.',
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: CupertinoSlidingSegmentedControl<double>(
                  groupValue: _radiusKm,
                  children: {
                    5.0: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: Text('5 km'),
                    ),
                    10.0: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: Text('10 km'),
                    ),
                    25.0: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: Text('25 km'),
                    ),
                    50.0: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: Text('50 km'),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value != null) setState(() => _radiusKm = value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            AppSection(
              title: 'Approximate home area',
              footer:
                  'Saved coordinates are rounded to about 1 km. We never store a location history.',
              child: _SettingsRow(
                icon: CupertinoIcons.location_fill,
                title: _latitude == null ? 'Set home area' : 'Update home area',
                subtitle: _latitude == null
                    ? 'No area saved'
                    : (_cityController.text.trim().isEmpty
                          ? 'Approximate location saved'
                          : _cityController.text.trim()),
                trailing: _locating
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.chevron_forward, size: 16),
                onTap: _locating ? null : _updateLocation,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text('Save Changes'),
            ),
            const SizedBox(height: 24),
            AppSection(
              title: 'Session',
              child: _SettingsRow(
                icon: CupertinoIcons.square_arrow_right,
                title: 'Sign Out',
                titleColor: colors.error,
                onTap: _saving
                    ? null
                    : () => Supabase.instance.client.auth.signOut(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? titleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            icon,
            size: 21,
            color: titleColor ?? Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: titleColor, fontSize: 16)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}
