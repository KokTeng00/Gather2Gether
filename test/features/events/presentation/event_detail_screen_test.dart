import 'package:gather2gether/features/events/domain/event_operations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_lifecycle.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/event_detail_screen.dart';

class _FakeEventRepository extends EventRepository {
  @override
  Future<List<EventConflict>> conflicts(String eventId) async => [];
  _FakeEventRepository(this.current)
    : super(
        accessTokenProvider: () => 'token',
        edgeApiUrl: 'https://example.test/api/v1',
      );

  EventSummary current;
  int saveCalls = 0;
  int confirmCalls = 0;
  int translationCalls = 0;

  @override
  Future<EventSummary> eventDetails(
    String eventId, {
    bool viaInvite = false,
  }) async => current;

  @override
  Future<List<EventAnnouncement>> announcements(String eventId) async => [
    EventAnnouncement(
      id: '33333333-3333-4333-8333-333333333333',
      eventId: eventId,
      body: 'Meet beside the north entrance.',
      createdAt: DateTime(2098, 12, 31),
    ),
  ];

  @override
  Future<bool> setSaved(String eventId, bool saved) async {
    saveCalls++;
    current = current.copyWith(isSaved: saved);
    return saved;
  }

  @override
  Future<String> updateRsvp(String eventId, String status) async {
    final saved = status == 'joined' && current.spotsLeft == 0
        ? 'waitlisted'
        : status;
    current = current.copyWith(
      userRsvpStatus: saved,
      waitlistPosition: saved == 'waitlisted' ? 1 : null,
    );
    return saved;
  }

  @override
  Future<DateTime> confirmRsvp(String eventId) async {
    confirmCalls++;
    final confirmedAt = DateTime(2098, 12, 31, 12);
    current = current.copyWith(viewerReconfirmedAt: confirmedAt);
    return confirmedAt;
  }

  @override
  Future<String> translateEvent(String eventId, String targetLanguage) async {
    translationCalls++;
    return 'Titel: Morgenlauf\nBeschreibung: Ein lockerer Lauf.';
  }

  @override
  Future<List<EventCohost>> cohosts(String eventId) async => const [
    EventCohost(
      profileId: '11111111-1111-4111-8111-111111111111',
      displayName: 'Alex',
      username: 'alex',
      role: 'Owner',
      viewerCanEdit: true,
    ),
  ];
}

EventSummary event({
  bool organizer = false,
  bool pendingConfirmation = false,
}) => EventSummary(
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
  userRsvpStatus: organizer || pendingConfirmation ? 'joined' : null,
  viewerIsOrganizer: organizer,
  beginnerFriendly: true,
  wheelchairAccessible: true,
  eventSetting: 'outdoor',
  eventLanguage: 'English',
  whatToBring: 'Water bottle',
  attendeeVisible: pendingConfirmation,
  reconfirmationDeadlineAt: pendingConfirmation
      ? DateTime(2098, 12, 31, 18)
      : null,
);

Future<void> _pumpEvent(
  WidgetTester tester,
  _FakeEventRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: EventDetailScreen(
        event: repository.current,
        repository: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('event detail exposes planning actions and organizer tools', (
    tester,
  ) async {
    final repository = _FakeEventRepository(event(organizer: true));
    await _pumpEvent(tester, repository);

    expect(find.byKey(const Key('event-save-action')), findsOneWidget);
    expect(find.byKey(const Key('event-share-action')), findsOneWidget);
    expect(find.byKey(const Key('event-calendar-action')), findsOneWidget);
    expect(find.byKey(const Key('event-directions-action')), findsOneWidget);
    expect(find.byKey(const Key('event-reminder-action')), findsOneWidget);
    expect(find.byKey(const Key('event-discussion-action')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Meet beside the north entrance.'),
      250,
    );
    expect(find.text('Meet beside the north entrance.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('event-edit-action')),
      300,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event-edit-action')), findsOneWidget);
    expect(find.byKey(const Key('event-announce-action')), findsOneWidget);
    expect(find.byKey(const Key('event-cohosts-action')), findsOneWidget);
    expect(
      find.byKey(const Key('event-request-reconfirmation-action')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('event-create-again-action')), findsOneWidget);
    expect(find.byKey(const Key('event-cancel-action')), findsOneWidget);

    await tester.tap(find.byKey(const Key('event-save-action')));
    await tester.pumpAndSettle();
    expect(repository.saveCalls, 1);
    expect(find.byTooltip('Remove saved event'), findsOneWidget);
  });

  testWidgets('a join attempt on a full event enters the waitlist', (
    tester,
  ) async {
    final repository = _FakeEventRepository(event());
    await _pumpEvent(tester, repository);

    expect(find.text('Join Waitlist'), findsOneWidget);
    await tester.tap(find.text('Join Waitlist'));
    await tester.pumpAndSettle();

    expect(find.text('Waitlist #1'), findsOneWidget);
    expect(
      find.text('The event is full. You joined the waitlist.'),
      findsOneWidget,
    );
  });

  testWidgets('an attendee can reconfirm and control roster privacy', (
    tester,
  ) async {
    final repository = _FakeEventRepository(event(pendingConfirmation: true));
    await _pumpEvent(tester, repository);

    expect(
      find.byKey(const Key('event-reconfirmation-banner')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('event-confirm-rsvp-action')));
    await tester.pumpAndSettle();
    expect(repository.confirmCalls, 1);
    expect(find.text('Your place is confirmed.'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('event-attendee-visibility')),
      250,
    );
    expect(find.byKey(const Key('event-attendees-action')), findsOneWidget);
    expect(find.byKey(const Key('event-attendee-visibility')), findsOneWidget);
    expect(find.text('Beginner-friendly'), findsOneWidget);
    expect(find.text('Wheelchair accessible'), findsOneWidget);
  });

  testWidgets('event details can be translated on demand', (tester) async {
    final repository = _FakeEventRepository(event());
    await _pumpEvent(tester, repository);

    await tester.scrollUntilVisible(
      find.byKey(const Key('event-translate-action')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('event-translate-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('event-translate-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('event-translation-language-field')),
      'German',
    );
    await tester.tap(find.byKey(const Key('event-translate-confirm')));
    await tester.pumpAndSettle();

    expect(repository.translationCalls, 1);
    expect(find.byKey(const Key('event-translation-result')), findsOneWidget);
    expect(find.textContaining('Morgenlauf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
