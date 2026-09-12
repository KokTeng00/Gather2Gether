import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({this.googleSignIn, super.key});

  final Future<bool> Function()? googleSignIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _isSigningIn = false;

  Future<void> _signInWithGoogle() async {
    if (_isSigningIn) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSigningIn = true);

    try {
      final launched =
          await (widget.googleSignIn?.call() ??
              Supabase.instance.client.auth.signInWithOAuth(
                OAuthProvider.google,
                redirectTo: AppConfig.authCallbackUrl,
                authScreenLaunchMode: LaunchMode.externalApplication,
                queryParams: const {'prompt': 'select_account'},
              ));
      if (!launched) {
        _showError('Could not open Google sign-in. Please try again.');
      }
    } on AuthException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not start Google sign-in. Please try again.');
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  minHeight: (constraints.maxHeight - 52).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const AppBrandMark(size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Gather2Gether',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(flex: 2),
                      const SizedBox(height: 64),
                      Text(
                        'Meet people.\nMake plans.',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontSize: 42,
                          height: 1.12,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Find free events nearby, or bring people together with a plan of your own.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 64),
                      const Spacer(flex: 2),
                      OutlinedButton.icon(
                        key: const Key('google-sign-in-button'),
                        onPressed: _isSigningIn ? null : _signInWithGoogle,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: colors.surface,
                          foregroundColor: colors.onSurface,
                        ),
                        icon: _isSigningIn
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CupertinoActivityIndicator(),
                              )
                            : const _GoogleMark(),
                        label: Text(
                          _isSigningIn
                              ? 'Opening Google…'
                              : 'Continue with Google',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sign in or create an account.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Free to join · Precise location stays private',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
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
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontSize: 15,
          height: 1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
