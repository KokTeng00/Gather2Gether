import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/auth/presentation/sign_in_screen.dart';

Future<void> _pumpSignIn(
  WidgetTester tester, {
  ThemeData? theme,
  double textScale = 1,
  Future<bool> Function()? googleSignIn,
  Future<bool> Function()? appleSignIn,
  bool appleEnabled = false,
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
        child: SignInScreen(
          googleSignIn: googleSignIn,
          appleSignIn: appleSignIn,
          appleEnabled: appleEnabled,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Apple is offered on iOS only after provider setup is enabled',
    (tester) async {
      await _pumpSignIn(tester);
      expect(find.byKey(const Key('apple-sign-in-button')), findsNothing);
      await _pumpSignIn(tester, appleEnabled: true);
      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Apple flow prevents a competing Google sign-in and recovers from failure',
    (tester) async {
      final pending = Completer<bool>();
      await _pumpSignIn(
        tester,
        appleEnabled: true,
        appleSignIn: () => pending.future,
      );
      await tester.ensureVisible(find.byKey(const Key('apple-sign-in-button')));
      await tester.tap(find.byKey(const Key('apple-sign-in-button')));
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('google-sign-in-button')),
            )
            .onPressed,
        isNull,
      );
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not open Apple sign-in. Please try again.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('google-sign-in-button')),
            )
            .onPressed,
        isNotNull,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('policy and support links are available before sign-in', (
    tester,
  ) async {
    await _pumpSignIn(tester);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Community rules'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.text('Help & feedback'), findsOneWidget);
  });

  testWidgets('shows Google as the only authentication option', (tester) async {
    await _pumpSignIn(tester);

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byKey(const Key('google-sign-in-button')), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Create account'), findsNothing);
    expect(find.text('Name'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Password'), findsNothing);
    expect(find.text('or use email'), findsNothing);
  });

  testWidgets('starts Google sign-in from the provider button', (tester) async {
    var signInCalls = 0;
    await _pumpSignIn(
      tester,
      googleSignIn: () async {
        signInCalls++;
        return true;
      },
    );

    await tester.ensureVisible(find.byKey(const Key('google-sign-in-button')));
    await tester.tap(find.byKey(const Key('google-sign-in-button')));
    await tester.pump();

    expect(signInCalls, 1);
  });

  testWidgets('reports when the Google flow cannot be opened', (tester) async {
    await _pumpSignIn(tester, googleSignIn: () async => false);

    await tester.ensureVisible(find.byKey(const Key('google-sign-in-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('google-sign-in-button')));
    await tester.pump();

    expect(
      find.text('Could not open Google sign-in. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('google-sign-in-button')),
          )
          .onPressed,
      isNotNull,
    );
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
      find.text('Free to join · Precise location stays private'),
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
