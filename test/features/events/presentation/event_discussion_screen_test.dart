import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_lifecycle.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/event_discussion_screen.dart';

class _FakeDiscussionRepository extends EventRepository {
  _FakeDiscussionRepository()
    : super(
        accessTokenProvider: () => 'token',
        edgeApiUrl: 'https://example.test/api/v1',
      );

  var summaryCalls = 0;

  @override
  Future<List<EventDiscussionMessage>> eventDiscussion(String eventId) async =>
      [
        EventDiscussionMessage(
          id: '33333333-3333-4333-8333-333333333333',
          eventId: eventId,
          authorId: '11111111-1111-4111-8111-111111111111',
          authorName: 'Alex',
          body: 'Meet by the north gate.',
          createdAt: DateTime(2098, 12, 31, 10),
          viewerIsAuthor: false,
        ),
        EventDiscussionMessage(
          id: '44444444-4444-4444-8444-444444444444',
          eventId: eventId,
          authorId: '55555555-5555-4555-8555-555555555555',
          authorName: 'Maya',
          body: 'I will bring cups.',
          createdAt: DateTime(2098, 12, 31, 11),
          viewerIsAuthor: true,
        ),
      ];

  @override
  Future<EventDiscussionSummary> summarizeDiscussion(String eventId) async {
    summaryCalls++;
    return const EventDiscussionSummary(
      summary: 'The group will meet at the north gate.',
      actionItems: ['Maya will bring cups.'],
    );
  }
}

final _event = EventSummary(
  id: '22222222-2222-4222-8222-222222222222',
  organizerId: '11111111-1111-4111-8111-111111111111',
  organizerName: 'Alex',
  title: 'Morning Run',
  description: 'An easy social run.',
  category: 'Running',
  venueName: 'City Park',
  address: 'Main entrance',
  latitude: 52.52,
  longitude: 13.405,
  startAt: DateTime(2099, 1, 1, 8),
  endAt: DateTime(2099, 1, 1, 9),
  maxParticipants: 10,
  joinedCount: 4,
  tentativeCount: 2,
  distanceMeters: 0,
  userRsvpStatus: 'joined',
);

void main() {
  testWidgets('participants can request a reviewable discussion summary', (
    tester,
  ) async {
    final repository = _FakeDiscussionRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: EventDiscussionScreen(event: _event, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('event-discussion-summary-action')));
    await tester.pumpAndSettle();

    expect(repository.summaryCalls, 1);
    expect(
      find.byKey(const Key('event-discussion-summary-result')),
      findsOneWidget,
    );
    expect(find.textContaining('Maya will bring cups.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
