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
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.scaffoldBackgroundColor,
                    Color.alphaBlend(
                      colors.primaryContainer.withValues(alpha: 0.38),
                      theme.scaffoldBackgroundColor,
                    ),
                    theme.scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -82,
            top: -74,
            child: _BackdropOrb(
              size: 238,
              color: colors.primary.withValues(alpha: 0.06),
            ),
          ),
          Positioned(
            left: -104,
            top: 288,
            child: _BackdropOrb(
              size: 196,
              color: colors.secondary.withValues(alpha: 0.07),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final minimumHeight = (constraints.maxHeight - 48)
                    .clamp(0.0, double.infinity)
                    .toDouble();
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 460,
                        minHeight: minimumHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _BrandHeader(),
                            const Spacer(),
                            const SizedBox(height: 48),
                            Text(
                              'Make nearby\nfeel closer.',
                              style: theme.textTheme.displaySmall?.copyWith(
                                color: colors.onSurface,
                                fontSize: 40,
                                height: 1.01,
                                letterSpacing: -1.45,
                              ),
                            ),
                            const SizedBox(height: 13),
                            Text(
                              'Discover free events, meet your neighbours, and turn a good idea into a real plan.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(height: 42),
                            _SignInPanel(
                              isSigningIn: _isSigningIn,
                              onPressed: _signInWithGoogle,
                            ),
                            const SizedBox(height: 16),
                            const _PrivacyNote(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        const AppBrandMark(size: 50),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gather2Gether',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Good plans start close to home',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignInPanel extends StatelessWidget {
  const _SignInPanel({required this.isSigningIn, required this.onPressed});

  final bool isSigningIn;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ready when you are',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Use your Google account to continue securely.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            key: const Key('google-sign-in-button'),
            onPressed: isSigningIn ? null : onPressed,
            style: OutlinedButton.styleFrom(
              backgroundColor: colors.surfaceContainerLowest,
              foregroundColor: colors.onSurface,
              side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.95),
              ),
            ),
            icon: isSigningIn
                ? const SizedBox.square(
                    dimension: 20,
                    child: CupertinoActivityIndicator(),
                  )
                : const _GoogleMark(),
            label: Text(
              isSigningIn ? 'Opening Google…' : 'Continue with Google',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'New here? Your profile is created automatically.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          CupertinoIcons.checkmark_shield_fill,
          color: colors.primary,
          size: 17,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Free to join · Precise location stays private',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _BackdropOrb extends StatelessWidget {
  const _BackdropOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
