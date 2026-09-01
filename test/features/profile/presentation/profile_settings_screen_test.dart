import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/profile_settings_screen.dart';

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository()
    : profile = const UserProfile(
        displayName: 'Maya Chen',
        username: 'maya_chen',
        bio: 'Coffee walks and local art.',
        city: 'Berlin',
        preferredRadiusKm: 10,
        approximateLatitude: 52.52,
        approximateLongitude: 13.4,
        assistantEnabled: true,
      );

  UserProfile profile;
  int preferenceUpdates = 0;
  final assistantUpdates = <bool>[];
  final passwordUpdates = <(String, String)>[];

  @override
  Future<UserProfile> updateDiscoveryPreferences({
    required double preferredRadiusKm,
    double? latitude,
    double? longitude,
  }) async {
    preferenceUpdates++;
    profile = profile.copyWith(
      preferredRadiusKm: preferredRadiusKm,
      approximateLatitude: latitude,
      approximateLongitude: longitude,
    );
    return profile;
  }

  @override
  Future<void> updateAssistantEnabled(bool enabled) async {
    assistantUpdates.add(enabled);
    profile = profile.copyWith(assistantEnabled: enabled);
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    passwordUpdates.add((currentPassword, newPassword));
  }
}

Future<
  ({
    _FakeProfileRepository repository,
    List<UserProfile> changed,
    ValueNotifier<int> signOuts,
  })
>
_pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = _FakeProfileRepository();
  final changed = <UserProfile>[];
  final signOuts = ValueNotifier(0);
  addTearDown(signOuts.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProfileSettingsScreen(
        profile: repository.profile,
        repository: repository,
        emailOverride: 'maya@example.com',
        onProfileChanged: changed.add,
        onAssistantEnabledChanged: (_) {},
        onSignOut: () async => signOuts.value++,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repository: repository, changed: changed, signOuts: signOuts);
}

void main() {
  testWidgets('settings uses a grouped navigation hub instead of tabs', (
    tester,
  ) async {
    final setup = await _pumpSettings(tester);

    expect(find.byKey(const Key('profile-settings-hub')), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Account & profile'), findsOneWidget);
    expect(find.text('Preferences & discovery'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);

    await tester.tap(find.text('Account & profile'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('account-profile-settings-list')),
      findsOneWidget,
    );
    expect(find.text('Edit public profile'), findsOneWidget);
    expect(find.text('maya@example.com'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('settings-sign-out-button')),
    );
    await tester.tap(find.byKey(const Key('settings-sign-out-button')));
    await tester.pumpAndSettle();
    expect(setup.signOuts.value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings hub stays usable with compact enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeProfileRepository();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.6),
          ),
          child: ProfileSettingsScreen(
            profile: repository.profile,
            repository: repository,
            emailOverride: 'maya@example.com',
            onAssistantEnabledChanged: (_) {},
            onSignOut: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account & profile'), findsOneWidget);
    await tester.ensureVisible(find.text('Privacy'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preferences page saves discovery and Gather Guide separately', (
    tester,
  ) async {
    final setup = await _pumpSettings(tester);

    await tester.tap(find.text('Preferences & discovery'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-preferences-list')), findsOneWidget);

    final initialButton = tester.widget<FilledButton>(
      find.byKey(const Key('save-preferences-button')),
    );
    expect(initialButton.onPressed, isNull);

    await tester.tap(find.text('25 km'));
    await tester.pump();
    final changedButton = tester.widget<FilledButton>(
      find.byKey(const Key('save-preferences-button')),
    );
    expect(changedButton.onPressed, isNotNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-preferences-button')),
      220,
      scrollable: find.descendant(
        of: find.byKey(const Key('profile-preferences-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-preferences-button')));
    await tester.pumpAndSettle();

    expect(setup.repository.preferenceUpdates, 1);
    expect(setup.repository.profile.preferredRadiusKm, 25);
    expect(setup.changed.last.preferredRadiusKm, 25);

    await tester.ensureVisible(find.byType(SwitchListTile));
    final guideToggle = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    guideToggle.onChanged!(false);
    await tester.pumpAndSettle();
    expect(setup.repository.assistantUpdates, [false]);
  });

  testWidgets('security opens a dedicated validated password flow', (
    tester,
  ) async {
    final setup = await _pumpSettings(tester);

    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('security-settings-list')), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('change-password-form')), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));

    await tester.enterText(
      find.byKey(const Key('current-password-field')),
      'CurrentPassword1',
    );
    await tester.enterText(
      find.byKey(const Key('new-password-field')),
      'NewPassword123',
    );
    await tester.enterText(
      find.byKey(const Key('confirm-password-field')),
      'DifferentPassword123',
    );
    await tester.tap(find.byKey(const Key('update-password-button')));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(setup.repository.passwordUpdates, isEmpty);

    await tester.enterText(
      find.byKey(const Key('confirm-password-field')),
      'NewPassword123',
    );
    await tester.tap(find.byKey(const Key('update-password-button')));
    await tester.pumpAndSettle();
    expect(setup.repository.passwordUpdates, [
      ('CurrentPassword1', 'NewPassword123'),
    ]);
    expect(find.text('Password updated.'), findsOneWidget);
  });

  testWidgets('privacy information is reachable from the hub', (tester) async {
    await _pumpSettings(tester);

    await tester.ensureVisible(find.text('Privacy'));
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy by design'), findsOneWidget);
    expect(find.text('Approximate home area'), findsOneWidget);
    expect(find.text('Community sharing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
