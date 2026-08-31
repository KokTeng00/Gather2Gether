import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/auth/presentation/sign_in_screen.dart';

Future<void> _pumpSignIn(
  WidgetTester tester, {
  ThemeData? theme,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(320, 568),
          textScaler: TextScaler.linear(textScale),
        ),
        child: const SignInScreen(),
      ),
    ),
  );
}

void main() {
  testWidgets('switches cleanly between sign-in and account creation', (
    tester,
  ) async {
    await _pumpSignIn(tester);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Name'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Join your local community'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
  });

  testWidgets('keeps password visibility accessible', (tester) async {
    await _pumpSignIn(tester);

    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('scrolls without overflow on a compact large-text screen', (
    tester,
  ) async {
    await _pumpSignIn(tester, theme: AppTheme.dark, textScale: 1.35);

    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -500),
    );
    await tester.pump();

    expect(
      find.text('Always free. Your precise location is never stored.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared feature banner grows for large text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.6),
          ),
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: AppFeatureBanner(
                label: 'Neighbourhood notes',
                title: 'A space for good neighbours',
                subtitle: 'Be kind · Keep personal details private',
                icon: Icons.groups_rounded,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
