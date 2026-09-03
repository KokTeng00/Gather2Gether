import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/public_profile.dart';
import 'package:gather2gether/features/profile/presentation/public_profile_screen.dart';

class _FakePublicProfileRepository extends ProfileRepository {
  _FakePublicProfileRepository({this.pastEventsPublic = false})
    : super(
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: 'https://example.test/api/v1',
      );

  var followChanges = 0;
  final bool pastEventsPublic;
  final requestedEventFilters = <String>[];

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
        pastEventsPublic: pastEventsPublic,
      );

  @override
  Future<List<EventSummary>> fetchProfileEvents(
    String profileId,
    String filter,
  ) async {
    requestedEventFilters.add(filter);
    return [
      EventSummary(
        id: filter == 'hosting' ? 'hosting-event' : 'past-event',
        organizerId: profileId,
        organizerName: 'Alex Morgan',
        title: filter == 'hosting' ? 'Saturday hike' : 'Community picnic',
        description: 'A community event.',
        category: 'Social',
        venueName: 'Town square',
        address: 'Main street',
        latitude: 52.52,
        longitude: 13.4,
        startAt: filter == 'hosting'
            ? DateTime(2099, 1, 1, 10)
            : DateTime(2025, 1, 1, 10),
        endAt: filter == 'hosting'
            ? DateTime(2099, 1, 1, 12)
            : DateTime(2025, 1, 1, 12),
        maxParticipants: 20,
        joinedCount: 8,
        tentativeCount: 1,
        distanceMeters: 0,
        userRsvpStatus: null,
      ),
    ];
  }

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
    expect(find.text('Saturday hike'), findsOneWidget);
    expect(find.byKey(const Key('profile-events-switcher')), findsOneWidget);
    expect(find.byKey(const Key('profile-past-events-private')), findsNothing);

    await tester.ensureVisible(find.text('Past'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('profile-past-events-private')),
      findsOneWidget,
    );
    expect(repository.requestedEventFilters, ['hosting']);
  });

  testWidgets('public past activity loads only after the member opts in', (
    tester,
  ) async {
    final repository = _FakePublicProfileRepository(pastEventsPublic: true);
    await tester.pumpWidget(
      MaterialApp(
        home: PublicProfileScreen(
          profileId: '11111111-1111-4111-8111-111111111111',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saturday hike'), findsOneWidget);
    expect(find.text('Community picnic'), findsNothing);

    await tester.ensureVisible(find.text('Past'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();

    expect(find.text('Saturday hike'), findsNothing);
    expect(find.text('Community picnic'), findsOneWidget);
    expect(find.byKey(const Key('profile-past-events-private')), findsNothing);
    expect(repository.requestedEventFilters, ['hosting', 'past']);
  });
}
