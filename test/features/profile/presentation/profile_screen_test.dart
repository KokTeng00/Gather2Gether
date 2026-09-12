import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/profile_stats.dart';
import 'package:gather2gether/features/profile/domain/profile_connection.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/profile_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_photo_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_widgets.dart';
import 'package:intl/intl.dart';

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository({UserProfile? initialProfile, this.failFetch = false})
    : profile =
          initialProfile ??
          const UserProfile(
            displayName: 'Maya Chen',
            username: 'maya_chen',
            bio: 'Coffee walks, local art, and welcoming new neighbours.',
            city: 'Berlin',
            preferredRadiusKm: 10,
            approximateLatitude: 52.52,
            approximateLongitude: 13.4,
            assistantEnabled: true,
          );

  UserProfile profile;
  final bool failFetch;
  int identityUpdates = 0;

  @override
  Future<UserProfile> fetchOwnProfile() async {
    if (failFetch) throw StateError('database detail hidden from UI');
    return profile;
  }

  @override
  Future<ProfileConnectionPage> fetchConnections({
    String? profileId,
    required ProfileConnectionKind kind,
    String query = '',
    String? cursor,
  }) async => const ProfileConnectionPage(members: [], canSearch: true);

  @override
  Future<ProfileStats> fetchStats() async => const ProfileStats(
    postsCount: 12,
    hostedCount: 4,
    goingCount: 7,
    followersCount: 31,
    followingCount: 18,
  );

  @override
  Future<UserProfile> updateIdentity({
    required String displayName,
    required String username,
    required String bio,
    required String city,
  }) async {
    identityUpdates++;
    profile = profile.copyWith(
      displayName: displayName.trim(),
      username: username.trim(),
      bio: bio.trim(),
      city: city.trim(),
    );
    return profile;
  }
}

class _EmptyForumRepository extends ForumRepository {
  _EmptyForumRepository()
    : super(
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: 'https://example.test/api/v1',
      );

  @override
  Future<List<ForumPost>> listOwnPosts() async => const [];
}

Future<_FakeProfileRepository> _pumpProfile(
  WidgetTester tester, {
  ThemeData? theme,
  double textScale = 1,
  UserProfile? initialProfile,
  bool failFetch = false,
  ValueChanged<UserProfile>? onProfileChanged,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = _FakeProfileRepository(
    initialProfile: initialProfile,
    failFetch: failFetch,
  );

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
            onProfileChanged: onProfileChanged,
            repository: repository,
            emailOverride: 'maya@example.com',
            hasPasswordSignInOverride: true,
            avatarHeadersOverride: const {},
            forumRepository: _EmptyForumRepository(),
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
  testWidgets('professional overview stays usable with compact large text', (
    tester,
  ) async {
    await _pumpProfile(tester, theme: AppTheme.dark, textScale: 1.6);

    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.text('@maya_chen'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.byTooltip('Profile settings'), findsOneWidget);
    expect(find.byKey(const Key('profile-page-header')), findsOneWidget);
    expect(find.byKey(const Key('profile-avatar')), findsOneWidget);
    expect(find.byKey(const Key('profile-activity-summary')), findsOneWidget);
    expect(find.byKey(const Key('profile-edit-action')), findsOneWidget);

    final header = tester.getRect(find.byKey(const Key('profile-page-header')));
    final avatar = tester.getRect(find.byKey(const Key('profile-avatar')));
    final stats = tester.getRect(
      find.byKey(const Key('profile-activity-summary')),
    );
    final edit = tester.getRect(find.byKey(const Key('profile-edit-action')));
    expect(header.top, greaterThanOrEqualTo(0));
    expect(avatar.top, greaterThan(header.top));
    expect(edit.top, greaterThan(avatar.bottom));
    expect(stats.top, greaterThan(edit.bottom));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('profile-contributions-header')),
      findsOneWidget,
    );
    expect(find.text('No community posts yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile keeps identity on one line and opens both owner lists', (
    tester,
  ) async {
    await _pumpProfile(tester);
    expect(
      (tester.getCenter(find.text('@maya_chen')).dy -
              tester.getCenter(find.text('Berlin')).dy)
          .abs(),
      lessThan(1),
    );
    for (final kind in ['followers', 'following']) {
      await tester.tap(find.byKey(Key('profile-$kind-action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('connections-search')), findsOneWidget);
      expect(find.byTooltip('Close'), findsNothing);
      await tester.drag(
        find.byKey(const Key('app-sheet-header')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'profile editing opens as a sheet from ${dark ? 'the pencil' : 'the username'}',
      (tester) async {
        final repository = await _pumpProfile(
          tester,
          theme: dark ? AppTheme.dark : AppTheme.light,
        );
        await tester.tap(
          find.byKey(
            Key(dark ? 'profile-edit-icon' : 'profile-username-action'),
          ),
        );
        await tester.pumpAndSettle();
        final sheet = find.byKey(const Key('app-sheet'));
        final header = find.byKey(const Key('app-sheet-header'));
        expect(tester.getTopLeft(sheet).dy, closeTo(568 * 0.4, 1));
        expect(find.byKey(const Key('profile-overview')), findsOneWidget);
        expect(find.text('Edit profile'), findsOneWidget);
        expect(find.byTooltip('Close'), findsNothing);
        expect(
          tester.widget<Material>(sheet).color,
          (dark ? AppTheme.dark : AppTheme.light).colorScheme.surface,
        );
        final name = find.byType(TextFormField).first;
        await tester.ensureVisible(name);
        await tester.enterText(name, 'Maya edited');
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(sheet).dy, closeTo(0, 1));
        await tester.drag(header, const Offset(0, 180));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(sheet).dy, closeTo(568 * 0.4, 1));
        expect(
          tester.widget<TextFormField>(name).controller!.text,
          'Maya edited',
        );
        await tester.drag(header, const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(repository.identityUpdates, 0);
        expect(find.text('Maya Chen'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('avatar opens an authenticated zoomable photo and closes', (
    tester,
  ) async {
    final profile = _FakeProfileRepository().profile.copyWith(
      avatarImageKey: 'avatar.jpg',
    );
    const headers = {'Authorization': 'Bearer test-token'};
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ProfileBalancedOverview(
            profile: profile,
            stats: null,
            onEdit: () {},
            avatarUrl: 'https://example.test/avatar.jpg',
            avatarHeaders: headers,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsNothing);
    expect(find.byTooltip('Edit profile'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-avatar')));
    await tester.pumpAndSettle();
    final viewer = tester.widget<ProfilePhotoScreen>(
      find.byType(ProfilePhotoScreen),
    );
    expect(viewer.headers, headers);
    expect(viewer.imageUrl, 'https://example.test/avatar.jpg');
    expect(
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).maxScale,
      4,
    );
    await tester.tap(find.byTooltip('Close photo'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePhotoScreen), findsNothing);
    expect(find.byKey(const Key('profile-overview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit profile validates and saves identity', (tester) async {
    final changed = <UserProfile>[];
    final repository = await _pumpProfile(
      tester,
      onProfileChanged: changed.add,
    );

    await tester.tap(find.byKey(const Key('profile-edit-action')));
    await tester.pumpAndSettle();
    expect(find.text('Profile details'), findsOneWidget);
    expect(find.byKey(const Key('save-profile-button')), findsOneWidget);
    expect(find.text('Save profile'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'Maya C.');
    await tester.enterText(find.byType(TextFormField).at(1), 'Maya.Dot');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      find.text('Use lowercase letters, numbers, or underscores.'),
      findsOneWidget,
    );
    expect(repository.identityUpdates, 0);

    await tester.enterText(find.byType(TextFormField).at(1), 'maya_local');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.identityUpdates, 1);
    expect(find.text('Maya C.'), findsOneWidget);
    expect(find.text('@maya_local'), findsOneWidget);
    expect(changed.last.username, 'maya_local');
    expect(find.byKey(const Key('app-sheet')), findsNothing);
  });

  testWidgets('edit profile locks a recently changed username', (tester) async {
    final changedAt = DateTime.now().subtract(const Duration(days: 1));
    final lockedProfile = UserProfile(
      displayName: 'Maya Chen',
      username: 'maya_chen',
      bio: 'Coffee walks and local art.',
      city: 'Berlin',
      preferredRadiusKm: 10,
      approximateLatitude: 52.52,
      approximateLongitude: 13.4,
      assistantEnabled: true,
      usernameChangedAt: changedAt,
    );
    final repository = await _pumpProfile(
      tester,
      initialProfile: lockedProfile,
    );

    await tester.tap(find.byKey(const Key('profile-edit-action')));
    await tester.pumpAndSettle();

    final usernameField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('profile-username-field')),
        matching: find.byType(TextField),
      ),
    );
    expect(usernameField.readOnly, isTrue);
    expect(usernameField.enabled, isFalse);
    final nextDate = DateFormat.yMMMMd().format(
      lockedProfile.nextUsernameChangeAt!,
    );
    expect(find.text('You can change it again on $nextDate.'), findsOneWidget);
    expect(find.byKey(const Key('profile-photo-action')), findsOneWidget);
    expect(repository.identityUpdates, 0);
  });

  testWidgets('settings action opens the profile settings hub', (tester) async {
    await _pumpProfile(tester);
    await tester.tap(find.byTooltip('Profile settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(const Key('profile-settings-hub')), findsOneWidget);
    expect(find.byKey(const Key('settings-account-row')), findsOneWidget);
    expect(find.byKey(const Key('settings-preferences-row')), findsOneWidget);
    expect(find.byKey(const Key('settings-security-row')), findsOneWidget);
  });

  testWidgets('owner profile leaves event management to Plans', (tester) async {
    await _pumpProfile(tester, textScale: 1.6);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-events-section')), findsNothing);
    expect(find.text('Hosting'), findsNothing);
    expect(find.text('Past'), findsNothing);
    expect(
      find.byKey(const Key('profile-contributions-header')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile failures offer a retry without claiming maintenance', (
    tester,
  ) async {
    await _pumpProfile(tester, failFetch: true);

    expect(find.byKey(const Key('profile-maintenance-state')), findsOneWidget);
    expect(find.text('MAINTENANCE'), findsNothing);
    expect(find.text('Couldn’t load this'), findsOneWidget);
    expect(find.text('Couldn’t load your profile'), findsNothing);
    expect(find.text('database detail hidden from UI'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
