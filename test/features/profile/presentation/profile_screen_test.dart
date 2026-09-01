import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/profile_stats.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/profile_screen.dart';

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository()
    : profile = const UserProfile(
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
  int identityUpdates = 0;

  @override
  Future<UserProfile> fetchOwnProfile() async => profile;

  @override
  Future<ProfileStats> fetchStats() async =>
      const ProfileStats(postsCount: 12, hostedCount: 4, goingCount: 7);

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
  ValueChanged<UserProfile>? onProfileChanged,
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
            onProfileChanged: onProfileChanged,
            repository: repository,
            emailOverride: 'maya@example.com',
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
    expect(find.text('4'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('No community posts yet'), findsOneWidget);
    expect(find.byTooltip('Profile settings'), findsOneWidget);
    expect(find.byKey(const Key('profile-social-header')), findsOneWidget);
    expect(find.byKey(const Key('profile-avatar')), findsOneWidget);
    expect(find.byKey(const Key('profile-inline-stats')), findsOneWidget);
    expect(find.byKey(const Key('profile-edit-action')), findsOneWidget);
    expect(find.byKey(const Key('profile-posts-tab')), findsOneWidget);

    final header = tester.getRect(
      find.byKey(const Key('profile-social-header')),
    );
    final avatar = tester.getRect(find.byKey(const Key('profile-avatar')));
    final stats = tester.getRect(find.byKey(const Key('profile-inline-stats')));
    final edit = tester.getRect(find.byKey(const Key('profile-edit-action')));
    final postsTab = tester.getRect(find.byKey(const Key('profile-posts-tab')));
    expect(header.top, greaterThanOrEqualTo(0));
    expect(avatar.top, greaterThan(header.top));
    expect((avatar.center.dy - stats.center.dy).abs(), lessThan(2));
    expect(edit.top, greaterThan(avatar.bottom));
    expect(postsTab.top, greaterThan(edit.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit profile validates and saves identity', (tester) async {
    final changed = <UserProfile>[];
    final repository = await _pumpProfile(
      tester,
      onProfileChanged: changed.add,
    );

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('Your identity'), findsOneWidget);

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
}
