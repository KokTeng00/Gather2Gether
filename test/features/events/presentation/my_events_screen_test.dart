import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/my_events_screen.dart';

class _FakeEventRepository extends EventRepository {
  _FakeEventRepository()
    : super(
        accessTokenProvider: () => 'token',
        edgeApiUrl: 'https://example.test/api/v1',
      );

  final filters = <String>[];

  @override
  Future<List<EventSummary>> myEvents(String filter) async {
    filters.add(filter);
    if (filter == 'saved') return const [];
    return [
      event(userRsvpStatus: filter == 'tentative' ? 'waitlisted' : 'joined'),
    ];
  }
}

EventSummary event({required String userRsvpStatus}) => EventSummary(
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
  joinedCount: 10,
  tentativeCount: 2,
  distanceMeters: 0,
  userRsvpStatus: userRsvpStatus,
  waitlistPosition: userRsvpStatus == 'waitlisted' ? 2 : null,
);

void main() {
  testWidgets('plans expose every lifecycle filter and waitlist state', (
    tester,
  ) async {
    final repository = _FakeEventRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: MyEventsScreen(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my-events-tabs')), findsOneWidget);
    for (final label in ['Going', 'Maybe', 'Hosting', 'Saved', 'Past']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Morning Run'), findsOneWidget);

    await tester.tap(find.text('Maybe'));
    await tester.pumpAndSettle();

    expect(repository.filters, containsAllInOrder(['going', 'tentative']));
    expect(find.text('City Park · Waitlist #2'), findsOneWidget);

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.textContaining('without committing'), findsOneWidget);
  });
}
