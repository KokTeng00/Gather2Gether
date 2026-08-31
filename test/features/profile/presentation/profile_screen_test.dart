import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/profile_screen.dart';

class _FakeProfileRepository implements ProfileRepository {
  bool profileUpdated = false;
  final assistantUpdates = <bool>[];

  @override
  Future<UserProfile> fetchOwnProfile() async => const UserProfile(
    displayName: 'Maya Chen',
    city: 'Berlin',
    preferredRadiusKm: 12,
    approximateLatitude: 52.52,
    approximateLongitude: 13.4,
    assistantEnabled: true,
  );

  @override
  Future<void> updateProfile({
    required String displayName,
    required String city,
    required double preferredRadiusKm,
    double? latitude,
    double? longitude,
  }) async {
    profileUpdated = true;
  }

  @override
  Future<void> updateAssistantEnabled(bool enabled) async {
    assistantUpdates.add(enabled);
  }
}

Future<_FakeProfileRepository> _pumpProfile(
  WidgetTester tester, {
  ThemeData? theme,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = _FakeProfileRepository();

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(320, 568),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: ProfileScreen(
            assistantEnabled: true,
            onAssistantEnabledChanged: (_) {},
            repository: repository,
            emailOverride: 'maya@example.com',
            onSignOut: () async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('profile stays usable on a compact large-text screen', (
    tester,
  ) async {
    await _pumpProfile(tester, theme: AppTheme.dark, textScale: 1.6);

    expect(find.text('Maya Chen'), findsNWidgets(2));
    expect(find.text('12 km'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign Out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('city length is validated before saving', (tester) async {
    final repository = await _pumpProfile(tester);
    await tester.enterText(
      find.byType(TextFormField).at(1),
      List.filled(121, 'x').join(),
    );
    final form = tester.state<FormState>(find.byType(Form));
    expect(form.validate(), isFalse);
    await tester.pump();

    expect(find.text('Use 120 characters or fewer.'), findsOneWidget);
    expect(repository.profileUpdated, isFalse);
  });

  testWidgets('Gather Guide exposes one accessible toggle action', (
    tester,
  ) async {
    final repository = await _pumpProfile(tester);
    await tester.ensureVisible(find.text('Gather Guide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gather Guide'));
    await tester.pumpAndSettle();

    expect(repository.assistantUpdates, [false]);
  });
}
