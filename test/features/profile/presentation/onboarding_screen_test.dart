import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/onboarding_screen.dart';

class _FakeProfileRepository extends ProfileRepository {
  List<String>? interests;
  List<String>? accessibilityPreferences;
  double? radiusKm;

  @override
  Future<void> completeOnboarding({
    required List<String> interests,
    required List<String> accessibilityPreferences,
    required double radiusKm,
    double? latitude,
    double? longitude,
  }) async {
    this.interests = interests;
    this.accessibilityPreferences = accessibilityPreferences;
    this.radiusKm = radiusKm;
  }
}

const _profile = UserProfile(
  displayName: 'Maya Chen',
  city: 'Berlin',
  preferredRadiusKm: 5,
  approximateLatitude: 52.52,
  approximateLongitude: 13.4,
  assistantEnabled: true,
);

Future<({UserProfile? completed, _FakeProfileRepository repository})>
_pumpOnboarding(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = _FakeProfileRepository();
  UserProfile? completed;

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: OnboardingScreen(
          profile: _profile,
          repository: repository,
          onCompleted: (profile) => completed = profile,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (completed: completed, repository: repository);
}

void main() {
  testWidgets('onboarding uses a deliberate visual hierarchy', (tester) async {
    await _pumpOnboarding(tester);

    expect(find.byType(AppBrandMark), findsOneWidget);
    expect(find.byKey(const Key('onboarding-headline')), findsOneWidget);
    expect(find.text('What gets you out\nof the house?'), findsOneWidget);
    expect(find.text('I’m up for…'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byKey(const Key('complete-onboarding')), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('interest and practical preferences are still saved', (
    tester,
  ) async {
    final setup = await _pumpOnboarding(tester);

    await tester.tap(find.byKey(const ValueKey('onboarding-interest-Coffee')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('onboarding-preference-wheelchair_accessible')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('onboarding-preference-wheelchair_accessible')),
    );
    await tester.tap(find.byKey(const Key('complete-onboarding')));
    await tester.pumpAndSettle();

    expect(setup.repository.interests, contains('Coffee'));
    expect(
      setup.repository.accessibilityPreferences,
      contains('wheelchair_accessible'),
    );
    expect(setup.repository.radiusKm, 5);
  });

  testWidgets('compact enlarged text remains scrollable with a fixed action', (
    tester,
  ) async {
    await _pumpOnboarding(tester, size: const Size(320, 568), textScale: 1.5);

    expect(find.byKey(const Key('complete-onboarding')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('onboarding-location-button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('onboarding-location-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
