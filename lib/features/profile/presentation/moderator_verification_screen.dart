import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/moderator_verification.dart';

class ModeratorVerificationScreen extends StatefulWidget {
  const ModeratorVerificationScreen({required this.repository, super.key});
  final ProfileRepository repository;

  @override
  State<ModeratorVerificationScreen> createState() =>
      _ModeratorVerificationScreenState();
}

class _ModeratorVerificationScreenState
    extends State<ModeratorVerificationScreen> {
  final _code = TextEditingController();
  ModeratorVerification? _verification;
  bool _busy = true;
  bool _showSecret = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final verification = await widget.repository.startModeratorVerification();
      if (mounted) setState(() => _verification = verification);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not set up verification. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(
        () => _error = 'Enter the six-digit code from your authenticator.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.verifyModeratorCode(
        _verification!.factorId,
        code,
      );
      _code.clear();
      final allowed = await widget.repository.isModerator();
      if (!mounted) return;
      if (allowed) {
        Navigator.of(context).pop(true);
      } else {
        setState(
          () => _error =
              'Moderator access could not be confirmed. Please sign in again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Verification failed. Check the code and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secret = _verification?.setupSecret;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Verify moderator access')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  secret == null
                      ? 'Enter a code from your authenticator to access moderation tools.'
                      : 'Add a time-based account named Gather2Gether in your authenticator, then enter its six-digit code. Keep access to your authenticator for future sign-ins.',
                ),
                if (secret != null) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => _showSecret = !_showSecret),
                    child: Text(
                      _showSecret ? 'Hide setup key' : 'Show setup key',
                    ),
                  ),
                  if (_showSecret) SelectableText(secret),
                  const Text(
                    'Keep this key private. Do not send it to support.',
                  ),
                ],
                const SizedBox(height: 24),
                if (_verification != null) ...[
                  TextField(
                    key: const Key('moderator-verification-code'),
                    controller: _code,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Authenticator code',
                    ),
                    onSubmitted: (_) {
                      if (!_busy) _verify();
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: const Text('Verify'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (_verification == null)
                    TextButton(
                      onPressed: _busy ? null : _prepare,
                      child: const Text('Try again'),
                    ),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
