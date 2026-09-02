import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/core/media/app_image_picker.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/core/validation/validators.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/profile_widgets.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ProfileAvatarPicker = Future<PreparedImage?> Function();

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    required this.profile,
    required this.repository,
    this.avatarPicker,
    this.avatarUrlBuilder,
    this.avatarHeaders,
    this.onProfileChanged,
    super.key,
  });

  final UserProfile profile;
  final ProfileRepository repository;
  final ProfileAvatarPicker? avatarPicker;
  final String? Function(UserProfile profile)? avatarUrlBuilder;
  final Map<String, String>? avatarHeaders;
  final ValueChanged<UserProfile>? onProfileChanged;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late final TextEditingController _city;
  late final AppImagePicker _imagePicker;
  late UserProfile _profile;
  bool _saving = false;
  bool _updatingAvatar = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _name = TextEditingController(text: _profile.displayName);
    _username = TextEditingController(text: _profile.username);
    _bio = TextEditingController(text: _profile.bio);
    _city = TextEditingController(text: _profile.city);
    _imagePicker = AppImagePicker();
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _updatingAvatar) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final updated = await widget.repository.updateIdentity(
        displayName: _name.text,
        username: _username.text,
        bio: _bio.text,
        city: _city.text,
      );
      if (!mounted) return;
      widget.onProfileChanged?.call(updated);
      Navigator.of(context).pop(updated);
    } catch (error) {
      _showError(
        error is ProfileApiException
            ? error.message
            : 'Could not save your profile. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeAvatar() async {
    if (_updatingAvatar || _saving) return;
    try {
      final image = await (widget.avatarPicker ?? _pickAvatar)();
      if (image == null || !mounted) return;
      setState(() => _updatingAvatar = true);
      await widget.repository.uploadAvatar(image);
      final updated = await widget.repository.fetchOwnProfile();
      if (!mounted) return;
      setState(() => _profile = updated);
      widget.onProfileChanged?.call(updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
    } catch (error) {
      _showError(
        error is AppImagePickException
            ? error.message
            : 'Profile photos are temporarily unavailable. Please try again soon.',
      );
    } finally {
      if (mounted) setState(() => _updatingAvatar = false);
    }
  }

  Future<PreparedImage?> _pickAvatar() async {
    final source = await showModalBottomSheet<AppImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.photo_on_rectangle),
              title: const Text('Choose from photos'),
              onTap: () => Navigator.pop(context, AppImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, AppImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return null;
    return _imagePicker.pickImage(source);
  }

  String? _avatarUrlFor(UserProfile profile) {
    final builder = widget.avatarUrlBuilder;
    if (builder != null) return builder(profile);
    if (!profile.hasAvatar) return null;
    final base = AppConfig.edgeApiUrl.endsWith('/')
        ? AppConfig.edgeApiUrl.substring(0, AppConfig.edgeApiUrl.length - 1)
        : AppConfig.edgeApiUrl;
    final version = Uri.encodeQueryComponent(profile.avatarImageKey!);
    return '$base/profile/avatar?v=$version';
  }

  Map<String, String>? _avatarHeaders() {
    final override = widget.avatarHeaders;
    if (override != null) return override;
    if (!_profile.hasAvatar) return null;
    try {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) return null;
      return {'Authorization': 'Bearer $token'};
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeAvatar() async {
    if (_updatingAvatar || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove profile photo?'),
        content: const Text('Your initials will be shown instead.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _updatingAvatar = true);
    try {
      await widget.repository.deleteAvatar();
      final updated = await widget.repository.fetchOwnProfile();
      if (!mounted) return;
      setState(() => _profile = updated);
      widget.onProfileChanged?.call(updated);
    } catch (_) {
      _showError('Could not remove your profile photo.');
    } finally {
      if (mounted) setState(() => _updatingAvatar = false);
    }
  }

  String? _validateUsername(String? value) {
    final text = value?.trim() ?? '';
    if (text.length < 3 || text.length > 30) {
      return 'Use 3 to 30 characters.';
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(text)) {
      return 'Use lowercase letters, numbers, or underscores.';
    }
    return null;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final avatarUrl = _avatarUrlFor(_profile);
    final nextUsernameChange = _profile.nextUsernameChangeAt;
    final usernameLocked = !_profile.canChangeUsernameAt(DateTime.now());
    final usernameGuidance = usernameLocked && nextUsernameChange != null
        ? 'You can change it again on '
              '${DateFormat.yMMMMd().format(nextUsernameChange)}.'
        : 'Usernames can be changed once every 3 months.';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit public profile'),
        actions: [
          TextButton(
            key: const Key('save-profile-button'),
            onPressed: _saving || _updatingAvatar ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppSurface(
                        borderRadius: 22,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                ProfileAvatar(
                                  profile: _profile,
                                  imageUrl: avatarUrl,
                                  headers: _avatarHeaders(),
                                  size: 96,
                                ),
                                if (_updatingAvatar)
                                  Container(
                                    width: 96,
                                    height: 96,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.45,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const CupertinoActivityIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              key: const Key('profile-photo-action'),
                              onPressed: _updatingAvatar || _saving
                                  ? null
                                  : _changeAvatar,
                              icon: const Icon(CupertinoIcons.camera_fill),
                              label: Text(
                                _profile.hasAvatar
                                    ? 'Change photo'
                                    : 'Add photo',
                              ),
                            ),
                            if (_profile.hasAvatar) ...[
                              const SizedBox(height: 2),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.error,
                                ),
                                onPressed: _updatingAvatar || _saving
                                    ? null
                                    : _removeAvatar,
                                child: const Text('Remove photo'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const ProfileSectionHeader(
                        title: 'Your identity',
                        subtitle: 'This is how you appear in the community.',
                      ),
                      const SizedBox(height: 11),
                      TextFormField(
                        controller: _name,
                        enabled: !_saving,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        maxLength: 80,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          counterText: '',
                          prefixIcon: Icon(CupertinoIcons.person),
                        ),
                        validator: (value) =>
                            Validators.requiredText(value, maxLength: 80),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('profile-username-field'),
                        controller: _username,
                        enabled: !_saving && !usernameLocked,
                        readOnly: usernameLocked,
                        showCursor: !usernameLocked,
                        style: TextStyle(
                          color: usernameLocked
                              ? colors.onSurfaceVariant
                              : colors.onSurface,
                        ),
                        autocorrect: false,
                        textCapitalization: TextCapitalization.none,
                        textInputAction: TextInputAction.next,
                        maxLength: 30,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          hintText: 'maya_chen',
                          prefixText: '@',
                          prefixIcon: Icon(
                            CupertinoIcons.at,
                            color: usernameLocked
                                ? colors.onSurfaceVariant
                                : null,
                          ),
                          suffixIcon: usernameLocked
                              ? Icon(
                                  CupertinoIcons.lock_fill,
                                  size: 18,
                                  color: colors.onSurfaceVariant,
                                )
                              : null,
                          filled: usernameLocked,
                          fillColor: usernameLocked
                              ? colors.surfaceContainerHighest.withValues(
                                  alpha: 0.48,
                                )
                              : null,
                          counterText: '',
                          helperText: usernameGuidance,
                          helperMaxLines: 2,
                        ),
                        validator: _validateUsername,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _bio,
                        enabled: !_saving,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 500,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          labelText: 'Bio',
                          hintText: 'A little about you and what you enjoy…',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(CupertinoIcons.text_alignleft),
                        ),
                        validator: (value) => (value?.length ?? 0) > 500
                            ? 'Use 500 characters or fewer.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _city,
                        enabled: !_saving,
                        maxLength: 120,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'City (optional)',
                          counterText: '',
                          prefixIcon: Icon(CupertinoIcons.building_2_fill),
                        ),
                        validator: (value) => (value?.trim().length ?? 0) > 120
                            ? 'Use 120 characters or fewer.'
                            : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
