import 'dart:async';

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
  Completer<List<EventSummary>>? pendingGoing;

  @override
  Future<List<EventSummary>> myEvents(String filter) async {
    filters.add(filter);
    return switch (filter) {
      'going' =>
        pendingGoing?.future ??
            [_event('run', 'Morning Run', hour: 8), _hostedEvent],
      'tentative' => [
        _event('waitlist', 'Coffee Meetup', hour: 9, status: 'waitlisted'),
        _event('maybe', 'Evening Walk', hour: 18, status: 'tentative'),
      ],
      'hosting' => [_hostedEvent],
      'drafts' => [
        _event('draft', 'Picnic Draft', hour: 7, eventStatus: 'draft'),
      ],
      'past' => [_event('past', 'Last Week Run', hour: 8)],
      _ => [],
    };
  }
}

final _hostedEvent = _event('host', 'Hosted Lunch', hour: 12, isHost: true);

EventSummary _event(
  String id,
  String title, {
  required int hour,
  String status = 'joined',
  String eventStatus = 'published',
  bool isHost = false,
}) => EventSummary(
  id: id,
  organizerId: '11111111-1111-4111-8111-111111111111',
  organizerName: 'Alex',
  title: title,
  description: 'A social plan.',
  category: 'Running',
  venueName: 'City Park',
  address: 'Main entrance',
  latitude: 52.52,
  longitude: 13.405,
  startAt: DateTime(2099, 1, 1, hour),
  endAt: DateTime(2099, 1, 1, hour + 1),
  maxParticipants: 10,
  joinedCount: 10,
  tentativeCount: 2,
  distanceMeters: 0,
  userRsvpStatus: status,
  waitlistPosition: status == 'waitlisted' ? 2 : null,
  viewerIsOrganizer: isHost,
  eventStatus: eventStatus,
);

Future<void> _showPlans(
  WidgetTester tester,
  _FakeEventRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: MyEventsScreen(repository: repository)),
    ),
  );
}

void main() {
  testWidgets('three tabs combine upcoming plans and keep status on cards', (
    tester,
  ) async {
    final repository = _FakeEventRepository();
    await _showPlans(tester, repository);
    await tester.pumpAndSettle();

    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.tabs.map((tab) => (tab as Tab).text), [
      'Upcoming',
      'Saved',
      'Past',
    ]);
    expect(tabs.isScrollable, isFalse);
    expect(repository.filters, ['going', 'tentative', 'hosting', 'drafts']);
    expect(find.text('Morning Run'), findsOneWidget);
    expect(find.text('City Park · Going'), findsOneWidget);
    expect(find.text('City Park · Waitlist #2'), findsOneWidget);
    expect(find.text('City Park · Maybe'), findsOneWidget);
    expect(find.text('Hosted Lunch'), findsOneWidget);
    expect(find.text('City Park · Hosting'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Morning Run')).dy,
      lessThan(tester.getTopLeft(find.text('Coffee Meetup')).dy),
    );
    await tester.scrollUntilVisible(find.text('Picnic Draft'), 150);
    expect(find.text('City Park · Draft'), findsOneWidget);

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.textContaining('without committing'), findsOneWidget);

    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();
    expect(find.text('Last Week Run'), findsOneWidget);
    expect(
      repository.filters.where((filter) => filter == 'past'),
      hasLength(1),
    );
  });

  testWidgets('a late upcoming response cannot replace the selected tab', (
    tester,
  ) async {
    final pending = Completer<List<EventSummary>>();
    final repository = _FakeEventRepository()..pendingGoing = pending;
    await _showPlans(tester, repository);
    await tester.pump();
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    expect(find.textContaining('without committing'), findsOneWidget);

    pending.complete([_event('late', 'Late Plan', hour: 8)]);
    await tester.pumpAndSettle();
    expect(find.textContaining('without committing'), findsOneWidget);
    expect(find.text('Late Plan'), findsNothing);
  });
}
