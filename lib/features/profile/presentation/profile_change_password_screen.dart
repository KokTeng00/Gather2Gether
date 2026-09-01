import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/core/validation/validators.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';

class ProfileChangePasswordScreen extends StatefulWidget {
  const ProfileChangePasswordScreen({required this.repository, super.key});

  final ProfileRepository repository;

  @override
  State<ProfileChangePasswordScreen> createState() =>
      _ProfileChangePasswordScreenState();
}

class _ProfileChangePasswordScreenState
    extends State<ProfileChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirmation = false;
  bool _saving = false;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await widget.repository.updatePassword(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      _currentPassword.clear();
      _newPassword.clear();
      _confirmation.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not update your password. Check it and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _passwordDecoration({
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    IconData icon = CupertinoIcons.lock,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: IconButton(
        tooltip: visible ? 'Hide $label' : 'Show $label',
        onPressed: _saving ? null : onToggle,
        icon: Icon(visible ? CupertinoIcons.eye_slash : CupertinoIcons.eye),
      ),
    );
  }

  String? _validateNewPassword(String? value) {
    final validation = Validators.password(value);
    if (validation != null) return validation;
    if (value == _currentPassword.text) {
      return 'Choose a password different from your current one.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: ListView(
              key: const Key('change-password-form'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppSurface(
                          color: colors.primaryContainer.withValues(alpha: 0.7),
                          borderColor: colors.primary.withValues(alpha: 0.16),
                          borderRadius: 22,
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  CupertinoIcons.lock_shield_fill,
                                  color: colors.onPrimary,
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Protect your account',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: colors.onPrimaryContainer,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Use at least 10 characters with a letter and a number. A unique password is safest.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colors.onPrimaryContainer
                                                .withValues(alpha: 0.78),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        AppSurface(
                          borderRadius: 22,
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                key: const Key('current-password-field'),
                                controller: _currentPassword,
                                enabled: !_saving,
                                obscureText: !_showCurrent,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.next,
                                decoration: _passwordDecoration(
                                  label: 'Current password',
                                  visible: _showCurrent,
                                  onToggle: () => setState(
                                    () => _showCurrent = !_showCurrent,
                                  ),
                                ),
                                validator: (value) => (value?.isEmpty ?? true)
                                    ? 'Enter your current password.'
                                    : null,
                              ),
                              const SizedBox(height: 13),
                              TextFormField(
                                key: const Key('new-password-field'),
                                controller: _newPassword,
                                enabled: !_saving,
                                obscureText: !_showNew,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                textInputAction: TextInputAction.next,
                                decoration: _passwordDecoration(
                                  label: 'New password',
                                  visible: _showNew,
                                  onToggle: () =>
                                      setState(() => _showNew = !_showNew),
                                ),
                                validator: _validateNewPassword,
                              ),
                              const SizedBox(height: 13),
                              TextFormField(
                                key: const Key('confirm-password-field'),
                                controller: _confirmation,
                                enabled: !_saving,
                                obscureText: !_showConfirmation,
                                autofillHints: const [
                                  AutofillHints.newPassword,
                                ],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _updatePassword(),
                                decoration: _passwordDecoration(
                                  label: 'Confirm new password',
                                  visible: _showConfirmation,
                                  icon: CupertinoIcons.checkmark_shield,
                                  onToggle: () => setState(
                                    () =>
                                        _showConfirmation = !_showConfirmation,
                                  ),
                                ),
                                validator: (value) => value != _newPassword.text
                                    ? 'Passwords do not match.'
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          key: const Key('update-password-button'),
                          onPressed: _saving ? null : _updatePassword,
                          icon: _saving
                              ? CupertinoActivityIndicator(
                                  color: colors.onPrimary,
                                )
                              : const Icon(CupertinoIcons.lock_rotation),
                          label: Text(
                            _saving ? 'Updating password…' : 'Update password',
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Changing your password may require you to sign in again on other devices.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
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
