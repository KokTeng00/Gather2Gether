import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/core/validation/validators.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (_isSignUp) {
        final response = await auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {'display_name': _nameController.text.trim()},
        );
        if (response.session == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Check your email to confirm your account.'),
            ),
          );
        }
      } else {
        await auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on AuthException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _setSignUp(bool value) {
    if (_isLoading || value == _isSignUp) return;
    setState(() => _isSignUp = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Theme.of(context).scaffoldBackgroundColor,
                    Color.alphaBlend(
                      colors.primaryContainer.withValues(alpha: 0.32),
                      Theme.of(context).scaffoldBackgroundColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -84,
            top: -92,
            child: Container(
              width: 238,
              height: 238,
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.62),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -102,
            top: 212,
            child: Container(
              width: 188,
              height: 188,
              decoration: BoxDecoration(
                color: colors.secondaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const AppBrandMark(size: 58),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Gather2Gether',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: colors.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Nearby plans, made together',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 34),
                          Text(
                            'Make nearby feel closer.',
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  color: colors.onSurface,
                                  fontSize: 40,
                                  height: 1.02,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Find free events, meet your neighbours, and turn a good idea into a real plan.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  height: 1.42,
                                ),
                          ),
                          const SizedBox(height: 28),
                          AppSurface(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: SegmentedButton<bool>(
                                    showSelectedIcon: false,
                                    expandedInsets: EdgeInsets.zero,
                                    segments: const [
                                      ButtonSegment(
                                        value: false,
                                        label: Text('Sign in'),
                                      ),
                                      ButtonSegment(
                                        value: true,
                                        label: Text('Create account'),
                                      ),
                                    ],
                                    selected: {_isSignUp},
                                    onSelectionChanged: _isLoading
                                        ? null
                                        : (selection) =>
                                              _setSignUp(selection.first),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  _isSignUp
                                      ? 'Join your local community'
                                      : 'Welcome back',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _isSignUp
                                      ? 'Create your account in less than a minute.'
                                      : 'Sign in to see what is happening nearby.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 20),
                                if (_isSignUp) ...[
                                  TextFormField(
                                    controller: _nameController,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [AutofillHints.name],
                                    decoration: const InputDecoration(
                                      labelText: 'Name',
                                      prefixIcon: Icon(CupertinoIcons.person),
                                    ),
                                    validator: (value) =>
                                        Validators.requiredText(
                                          value,
                                          maxLength: 80,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: Icon(CupertinoIcons.mail),
                                  ),
                                  validator: Validators.email,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: _isSignUp
                                      ? const [AutofillHints.newPassword]
                                      : const [AutofillHints.password],
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(CupertinoIcons.lock),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? CupertinoIcons.eye
                                            : CupertinoIcons.eye_slash,
                                      ),
                                    ),
                                  ),
                                  validator: _isSignUp
                                      ? Validators.password
                                      : Validators.requiredText,
                                ),
                                const SizedBox(height: 18),
                                FilledButton(
                                  onPressed: _isLoading ? null : _submit,
                                  child: _isLoading
                                      ? CupertinoActivityIndicator(
                                          color: colors.onPrimary,
                                        )
                                      : Text(
                                          _isSignUp
                                              ? 'Create Account'
                                              : 'Continue',
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: colors.secondaryContainer.withValues(
                                alpha: 0.72,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: colors.secondary.withValues(alpha: 0.38),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  CupertinoIcons.checkmark_shield_fill,
                                  color: colors.onSecondaryContainer,
                                  size: 21,
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Text(
                                    'Always free. Your precise location is never stored.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colors.onSecondaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
