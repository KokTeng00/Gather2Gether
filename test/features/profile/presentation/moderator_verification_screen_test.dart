import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/moderator_verification.dart';
import 'package:gather2gether/features/profile/presentation/moderator_verification_screen.dart';

class _Repository extends ProfileRepository {
  String? secret;
  bool rejectCode = false;
  bool authorized = true;
  int verifications = 0;

  @override
  Future<ModeratorVerification> startModeratorVerification() async =>
      ModeratorVerification(factorId: 'test-factor', setupSecret: secret);

  @override
  Future<void> verifyModeratorCode(String factorId, String code) async {
    verifications++;
    expect(factorId, 'test-factor');
    expect(code, '123456');
    if (rejectCode) throw StateError('Rejected');
  }

  @override
  Future<bool> isModerator() async => authorized;
}

Future<void> _open(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        ModeratorVerificationScreen(repository: repository),
                  ),
                );
                if (context.mounted && result == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Access verified')),
                  );
                }
              },
              child: const Text('Open verification'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open verification'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('setup key is hidden until requested', (tester) async {
    final repository = _Repository()..secret = 'TEST-SETUP-KEY';
    await _open(tester, repository);
    expect(find.text('TEST-SETUP-KEY'), findsNothing);
    await tester.tap(find.text('Show setup key'));
    await tester.pump();
    expect(find.text('TEST-SETUP-KEY'), findsOneWidget);
    await tester.tap(find.text('Hide setup key'));
    await tester.pump();
    expect(find.text('TEST-SETUP-KEY'), findsNothing);
  });

  testWidgets('invalid code is rejected before calling authentication', (
    tester,
  ) async {
    final repository = _Repository();
    await _open(tester, repository);
    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Verify'));
    await tester.pump();
    expect(repository.verifications, 0);
    expect(
      find.text('Enter the six-digit code from your authenticator.'),
      findsOneWidget,
    );
  });

  testWidgets('rejected code keeps moderation closed and permits retry', (
    tester,
  ) async {
    final repository = _Repository()..rejectCode = true;
    await _open(tester, repository);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.text('Access verified'), findsNothing);
    expect(
      find.text('Verification failed. Check the code and try again.'),
      findsOneWidget,
    );
    repository.rejectCode = false;
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.text('Access verified'), findsOneWidget);
  });

  testWidgets('successful MFA still requires server moderator authorization', (
    tester,
  ) async {
    final repository = _Repository()..authorized = false;
    await _open(tester, repository);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.text('Access verified'), findsNothing);
    expect(
      find.text(
        'Moderator access could not be confirmed. Please sign in again.',
      ),
      findsOneWidget,
    );
  });
}
