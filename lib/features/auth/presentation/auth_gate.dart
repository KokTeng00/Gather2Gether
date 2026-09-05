import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/features/auth/presentation/sign_in_screen.dart';
import 'package:gather2gether/features/notifications/data/push_notification_service.dart';
import 'package:gather2gether/features/shell/presentation/app_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Session? _session;
  late final StreamSubscription<AuthState> _subscription;
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<Uri>? _pushLinkSubscription;
  StreamSubscription<ForegroundPushNotification>? _foregroundPushSubscription;
  late final PushNotificationService _pushNotifications;
  Uri? _inviteLink;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _session = auth.currentSession;
    _pushNotifications = PushNotificationService();
    _pushLinkSubscription = _pushNotifications.eventLinks.listen(
      _captureEventLink,
    );
    _foregroundPushSubscription = _pushNotifications.foregroundNotifications
        .listen(_showForegroundPush);
    _subscription = auth.onAuthStateChange.listen((state) {
      if (mounted) setState(() => _session = state.session);
      if (state.session != null) {
        unawaited(
          _pushNotifications.registerCurrentDevice().catchError((_) {}),
        );
      } else {
        unawaited(
          _pushNotifications.unregisterCurrentDevice().catchError((_) {}),
        );
      }
    }, onError: _handleAuthError);
    _listenForInvites();
    unawaited(_configurePush());
  }

  Future<void> _configurePush() async {
    try {
      final initialLink = await _pushNotifications.initialize();
      if (initialLink != null) _captureEventLink(initialLink);
      if (_session != null) {
        await _pushNotifications.registerCurrentDevice();
      } else {
        await _pushNotifications.unregisterCurrentDevice();
      }
    } catch (_) {
      // The private in-app inbox remains available when push setup fails.
    }
  }

  Future<void> _listenForInvites() async {
    final links = AppLinks();
    _linkSubscription = links.uriLinkStream.listen(_captureEventLink);
    final initial = await links.getInitialLink();
    if (initial != null) _captureEventLink(initial);
  }

  void _captureEventLink(Uri uri) {
    if (uri.scheme == 'gather2gether' && uri.host == 'event' && mounted) {
      setState(() => _inviteLink = uri);
    }
  }

  void _showForegroundPush(ForegroundPushNotification notification) {
    if (!mounted) return;
    final body = notification.body.trim();
    final message = body.isEmpty
        ? notification.title
        : '${notification.title}\n$body';
    final eventLink = notification.eventLink;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        action: eventLink == null
            ? null
            : SnackBarAction(
                label: 'View',
                onPressed: () => _captureEventLink(eventLink),
              ),
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      await _pushNotifications.unregisterCurrentDevice();
    } catch (_) {
      // Signing out must still succeed if notification cleanup is unavailable.
    }
    await Supabase.instance.client.auth.signOut();
  }

  void _handleAuthError(Object error, StackTrace stackTrace) {
    if (!mounted) return;
    final message = error is AuthException
        ? error.message
        : 'Sign-in could not be completed. Please try again.';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _linkSubscription?.cancel();
    _pushLinkSubscription?.cancel();
    _foregroundPushSubscription?.cancel();
    unawaited(_pushNotifications.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _session == null
          ? const SignInScreen(key: ValueKey('signed-out'))
          : AppShell(
              key: const ValueKey('signed-in'),
              inviteLink: _inviteLink,
              onInviteConsumed: () {
                if (mounted) setState(() => _inviteLink = null);
              },
              onSignOut: _signOut,
            ),
    );
  }
}
