import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/public_profile.dart';
import 'package:gather2gether/features/profile/presentation/public_profile_screen.dart';

class _FakePublicProfileRepository extends ProfileRepository {
  _FakePublicProfileRepository()
    : super(
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: 'https://example.test/api/v1',
      );

  var followChanges = 0;

  @override
  Future<PublicProfile> fetchPublicProfile(String profileId) async =>
      PublicProfile(
        id: profileId,
        displayName: 'Alex Morgan',
        username: 'alex_local',
        bio: 'Hiking, coffee, and good neighbours.',
        city: 'Berlin',
        hasAvatar: false,
        followersCount: 12,
        followingCount: 8,
        viewerIsFollowing: followChanges > 0,
        viewerIsSelf: false,
      );

  @override
  Future<bool> setFollowing(String profileId, bool following) async {
    followChanges += following ? 1 : -1;
    return following;
  }
}

void main() {
  testWidgets('a member can follow another public profile', (tester) async {
    final repository = _FakePublicProfileRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: PublicProfileScreen(
          profileId: '11111111-1111-4111-8111-111111111111',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alex Morgan'), findsOneWidget);
    expect(find.text('@alex_local'), findsNWidgets(2));
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-follow-button')));
    await tester.pumpAndSettle();

    expect(repository.followChanges, 1);
    expect(find.text('13'), findsOneWidget);
    expect(find.text('Following'), findsAtLeastNWidgets(2));
  });
}
