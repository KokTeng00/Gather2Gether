import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            'Choose a password you do not use anywhere else.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Current password',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 9),
                        TextFormField(
                          key: const Key('current-password-field'),
                          controller: _currentPassword,
                          enabled: !_saving,
                          obscureText: !_showCurrent,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.next,
                          decoration: _passwordDecoration(
                            label: 'Enter current password',
                            visible: _showCurrent,
                            onToggle: () =>
                                setState(() => _showCurrent = !_showCurrent),
                          ),
                          validator: (value) => (value?.isEmpty ?? true)
                              ? 'Enter your current password.'
                              : null,
                        ),
                        const SizedBox(height: 26),
                        Text(
                          'New password',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 9),
                        TextFormField(
                          key: const Key('new-password-field'),
                          controller: _newPassword,
                          enabled: !_saving,
                          obscureText: !_showNew,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => setState(() {}),
                          decoration: _passwordDecoration(
                            label: 'Enter new password',
                            visible: _showNew,
                            onToggle: () =>
                                setState(() => _showNew = !_showNew),
                          ),
                          validator: _validateNewPassword,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _PasswordRule(
                              label: '10+ characters',
                              met: _newPassword.text.length >= 10,
                            ),
                            _PasswordRule(
                              label: 'One letter',
                              met: RegExp(
                                '[A-Za-z]',
                              ).hasMatch(_newPassword.text),
                            ),
                            _PasswordRule(
                              label: 'One number',
                              met: RegExp(r'\d').hasMatch(_newPassword.text),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          key: const Key('confirm-password-field'),
                          controller: _confirmation,
                          enabled: !_saving,
                          obscureText: !_showConfirmation,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _updatePassword(),
                          decoration: _passwordDecoration(
                            label: 'Confirm new password',
                            visible: _showConfirmation,
                            icon: CupertinoIcons.checkmark_shield,
                            onToggle: () => setState(
                              () => _showConfirmation = !_showConfirmation,
                            ),
                          ),
                          validator: (value) => value != _newPassword.text
                              ? 'Passwords do not match.'
                              : null,
                        ),
                        const SizedBox(height: 26),
                        FilledButton.icon(
                          key: const Key('update-password-button'),
                          onPressed: _saving ? null : _updatePassword,
                          icon: _saving
                              ? CupertinoActivityIndicator(
                                  color: colors.onPrimary,
                                )
                              : const Icon(CupertinoIcons.lock_rotation),
                          label: Text(
                            _saving ? 'Changing password…' : 'Change password',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              CupertinoIcons.info_circle,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'You may need to sign in again on your other devices.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
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
        ),
      ),
    );
  }
}

class _PasswordRule extends StatelessWidget {
  const _PasswordRule({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = met ? colors.primary : colors.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
