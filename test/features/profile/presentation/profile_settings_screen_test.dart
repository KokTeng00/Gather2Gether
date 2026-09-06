import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/public_profile.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/profile_settings_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_widgets.dart';

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
  int onboardingUpdates = 0;
  final assistantUpdates = <bool>[];
  final pastVisibilityUpdates = <bool>[];
  final passwordUpdates = <(String, String)>[];
  final blockUpdates = <(String, bool)>[];
  List<String>? savedInterests;
  List<String>? savedAccessibilityPreferences;
  var accountDeletions = 0;

  @override
  Future<void> completeOnboarding({
    required List<String> interests,
    required List<String> accessibilityPreferences,
    required double radiusKm,
    double? latitude,
    double? longitude,
  }) async {
    onboardingUpdates++;
    savedInterests = interests;
    savedAccessibilityPreferences = accessibilityPreferences;
    profile = profile.copyWith(
      preferredRadiusKm: radiusKm,
      approximateLatitude: latitude,
      approximateLongitude: longitude,
      interests: interests,
      accessibilityPreferences: accessibilityPreferences,
    );
  }

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
  Future<UserProfile> updatePastEventsVisibility(bool isPublic) async {
    pastVisibilityUpdates.add(isPublic);
    profile = profile.copyWith(showPastEventsPublic: isPublic);
    return profile;
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    passwordUpdates.add((currentPassword, newPassword));
  }

  @override
  Future<List<BlockedProfile>> blockedProfiles() async => [
    BlockedProfile(
      id: '11111111-1111-4111-8111-111111111111',
      displayName: 'Alex Morgan',
      username: 'alex_local',
      blockedAt: DateTime.utc(2026, 9, 4, 10),
    ),
  ];

  @override
  Future<bool> setBlocked(String profileId, bool blocked) async {
    blockUpdates.add((profileId, blocked));
    return blocked;
  }

  @override
  Future<void> deleteAccount() async {
    accountDeletions += 1;
  }
}

Future<
  ({
    _FakeProfileRepository repository,
    List<UserProfile> changed,
    ValueNotifier<int> signOuts,
  })
>
_pumpSettings(WidgetTester tester, {bool hasPasswordSignIn = true}) async {
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
        hasPasswordSignInOverride: hasPasswordSignIn,
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
  testWidgets('event interests remain editable after onboarding', (
    tester,
  ) async {
    final setup = await _pumpSettings(tester);

    await tester.tap(find.text('Preferences & discovery'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preferences-interests')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-option-Coffee')));
    await tester.tap(find.byKey(const Key('settings-picker-done')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('save-event-preferences-button')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('save-preferences-button')));
    await tester.pumpAndSettle();

    expect(setup.repository.savedInterests, contains('Coffee'));
    expect(setup.repository.onboardingUpdates, 1);
  });

  testWidgets('settings header uses the authenticated profile photo', (
    tester,
  ) async {
    final repository = _FakeProfileRepository();
    final profile = repository.profile.copyWith(
      avatarImageKey: 'avatars/member/avatar-v2.jpg',
    );
    const headers = {'Authorization': 'Bearer test-token'};

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProfileSettingsScreen(
          profile: profile,
          repository: repository,
          emailOverride: 'maya@example.com',
          hasPasswordSignInOverride: true,
          avatarUrlOverride: 'https://example.test/profile/avatar-v2.jpg',
          avatarHeadersOverride: headers,
          onAssistantEnabledChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    final avatar = tester.widget<ProfileAvatar>(
      find.byKey(const Key('settings-profile-avatar')),
    );
    expect(avatar.profile.avatarImageKey, 'avatars/member/avatar-v2.jpg');
    expect(avatar.imageUrl, 'https://example.test/profile/avatar-v2.jpg');
    expect(avatar.headers, headers);
  });

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
    expect(find.text('Your reports'), findsNothing);
    expect(find.text('Export your data'), findsNothing);
    expect(find.text('Community & data'), findsNothing);

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
            hasPasswordSignInOverride: true,
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

  testWidgets('edit public profile includes profile photo controls', (
    tester,
  ) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Account & profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit public profile'));
    await tester.pumpAndSettle();

    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.byKey(const Key('app-sheet')), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing);
    expect(find.byKey(const Key('profile-photo-action')), findsOneWidget);
    expect(find.byTooltip('Add profile photo'), findsOneWidget);
    expect(find.text('Add photo'), findsNothing);
    expect(find.text('Remove photo'), findsNothing);
    expect(find.byKey(const Key('profile-username-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preferences page saves discovery and Gather Guide separately', (
    tester,
  ) async {
    final setup = await _pumpSettings(tester);

    await tester.tap(find.text('Preferences & discovery'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-preferences-list')), findsOneWidget);
    expect(find.text('Shape your experience'), findsNothing);
    expect(find.byKey(const Key('preferences-distance')), findsOneWidget);

    final initialButton = tester.widget<TextButton>(
      find.byKey(const Key('save-preferences-button')),
    );
    expect(initialButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('preferences-distance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('25 km'));
    await tester.pumpAndSettle();
    final changedButton = tester.widget<TextButton>(
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

    expect(setup.repository.onboardingUpdates, 1);
    expect(setup.repository.preferenceUpdates, 0);
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
    expect(find.text('Protect your account'), findsNothing);
    expect(find.text('10+ characters'), findsOneWidget);
    expect(find.text('One letter'), findsOneWidget);
    expect(find.text('One number'), findsOneWidget);

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

  testWidgets('security reflects a Google-only sign-in account', (
    tester,
  ) async {
    await _pumpSettings(tester, hasPasswordSignIn: false);

    expect(find.byKey(const Key('settings-security-row')), findsOneWidget);
    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();

    expect(find.text('Google sign-in'), findsOneWidget);
    expect(
      find.text('Your sign-in password is managed by your Google Account.'),
      findsOneWidget,
    );
    expect(find.text('Change password'), findsNothing);
    expect(find.byKey(const Key('settings-change-password-row')), findsNothing);
  });

  testWidgets('privacy information is reachable from the hub', (tester) async {
    final setup = await _pumpSettings(tester);

    await tester.ensureVisible(find.text('Privacy'));
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Approximate home area'), findsOneWidget);
    expect(find.text('Community sharing'), findsOneWidget);
    expect(find.text('Show past events'), findsOneWidget);

    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('past-events-visibility-toggle')),
    );
    expect(toggle.value, isFalse);
    toggle.onChanged!(true);
    await tester.pumpAndSettle();

    expect(setup.repository.pastVisibilityUpdates, [true]);
    expect(setup.changed.last.showPastEventsPublic, isTrue);
    expect(
      find.text('Past events are now visible on your profile.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy lets members review and unblock people', (tester) async {
    final setup = await _pumpSettings(tester);

    await tester.ensureVisible(find.text('Privacy'));
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('blocked-users-settings-row')));
    await tester.pumpAndSettle();

    expect(find.text('Alex Morgan'), findsOneWidget);
    expect(find.text('@alex_local'), findsOneWidget);
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();

    expect(setup.repository.blockUpdates, [
      ('11111111-1111-4111-8111-111111111111', false),
    ]);
    expect(find.text('You have not blocked anyone.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account deletion requires typing the exact confirmation', (
    tester,
  ) async {
    final setup = await _pumpSettings(tester);

    await tester.tap(find.text('Account & profile'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-delete-account-button')),
      220,
      scrollable: find.descendant(
        of: find.byKey(const Key('account-profile-settings-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.drag(
      find.byKey(const Key('account-profile-settings-list')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-delete-account-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('delete-account-confirmation-field')),
      'delete',
    );
    await tester.tap(find.byKey(const Key('confirm-delete-account-button')));
    await tester.pumpAndSettle();
    expect(setup.repository.accountDeletions, 0);

    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('settings-delete-account-button')),
    );
    await tester.drag(
      find.byKey(const Key('account-profile-settings-list')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-delete-account-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('delete-account-confirmation-field')),
      'DELETE',
    );
    await tester.tap(find.byKey(const Key('confirm-delete-account-button')));
    await tester.pumpAndSettle();

    expect(setup.repository.accountDeletions, 1);
    expect(tester.takeException(), isNull);
  });
}
