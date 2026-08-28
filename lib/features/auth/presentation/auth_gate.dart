import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gather2gether/features/auth/presentation/sign_in_screen.dart';
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

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _session = auth.currentSession;
    _subscription = auth.onAuthStateChange.listen((state) {
      if (mounted) setState(() => _session = state.session);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _session == null
          ? const SignInScreen(key: ValueKey('signed-out'))
          : const AppShell(key: ValueKey('signed-in')),
    );
  }
}
