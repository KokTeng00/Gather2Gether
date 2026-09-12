import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:gather2gether/core/theme/app_date_time_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/assistant/data/assistant_repository.dart';
import 'package:gather2gether/features/assistant/domain/assistant_message.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/presentation/create_event_screen.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/places/data/place_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeAssistantRepository extends AssistantRepository {
  _FakeAssistantRepository()
    : super(
        accessTokenProvider: () => 'token',
        edgeApiUrl: 'https://example.test/api/v1',
      );

  @override
  Future<AssistantEventDraft> draftEvent({
    required String prompt,
    required String locale,
  }) async => const AssistantEventDraft(
    title: 'Beginner photo walk',
    description: 'Practise street photography together at a relaxed pace.',
    category: 'Photography',
    beginnerFriendly: true,
    eventSetting: 'outdoor',
    eventLanguage: 'English',
    ageGuidance: 'all_ages',
    whatToBring: 'A phone or camera',
  );
}

EventSummary _eventWithOptions({DateTime? startAt, DateTime? endAt}) =>
    EventSummary(
      id: '22222222-2222-4222-8222-222222222222',
      organizerId: '11111111-1111-4111-8111-111111111111',
      organizerName: 'Alex',
      title: 'Morning walk',
      description: 'A relaxed walk together.',
      category: 'Hiking',
      venueName: 'City Park',
      address: 'Park entrance',
      latitude: 52.52,
      longitude: 13.405,
      startAt: startAt ?? DateTime(2099, 9, 20, 10),
      endAt: endAt ?? DateTime(2099, 9, 20, 12),
      maxParticipants: 24,
      joinedCount: 3,
      tentativeCount: 0,
      distanceMeters: 0,
      userRsvpStatus: 'joined',
      viewerIsOrganizer: true,
      beginnerFriendly: true,
      wheelchairAccessible: true,
      eventSetting: 'outdoor',
      ageGuidance: 'adults',
      eventLanguage: 'English',
      whatToBring: 'Water',
      allowGuest: true,
      meetingInstructions: 'Meet beside the north gate.',
      meetingLatitude: 52.521,
      meetingLongitude: 13.406,
      hasMeetingImage: true,
      eventVisibility: 'unlisted',
      invitePreviewEnabled: true,
      previewArea: 'Berlin',
    );

void main() {
  testWidgets(
    'editing preserves optional settings without opening their sections',
    (tester) async {
      Map<String, dynamic>? saved;
      final events = EventRepository(
        httpClient: MockClient((request) async {
          saved = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        }),
        accessTokenProvider: () => 'token',
        edgeApiUrl: 'https://example.test/api/v1',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CreateEventScreen(
            onCreated: () {},
            initialEvent: _eventWithOptions(endAt: DateTime(2099, 9, 22, 9)),
            eventRepository: events,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('event-meeting-instructions')), findsNothing);
      expect(find.byKey(const Key('event-capacity-field')), findsNothing);
      expect(find.byKey(const Key('event-language-field')), findsNothing);
      expect(find.byKey(const Key('event-visibility-field')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('publish-event-button')));
      await tester.tap(find.byKey(const Key('publish-event-button')));
      await tester.pumpAndSettle();
      expect(
        DateTime.parse(saved!['start_at']).toLocal(),
        DateTime(2099, 9, 20, 10),
      );
      expect(
        DateTime.parse(saved!['end_at']).toLocal(),
        DateTime(2099, 9, 22, 9),
      );
      expect(saved!['max_participants'], 24);
      expect(saved!['event_language'], 'English');
      expect(saved!['what_to_bring'], 'Water');
      expect(saved!['beginner_friendly'], true);
      expect(saved!['wheelchair_accessible'], true);
      expect(saved!['visibility'], 'unlisted');
      final planning = saved!['planning'] as Map<String, dynamic>;
      expect(planning['allow_guest'], true);
      expect(planning['meeting_instructions'], 'Meet beside the north gate.');
      expect(planning['meeting_latitude'], 52.521);
      expect(planning['meeting_longitude'], closeTo(13.406, 1e-9));
      expect(planning['invite_preview_enabled'], true);
      expect(planning['preview_area'], 'Berlin');
      expect(planning['remove_meeting_image'], false);
    },
  );

  testWidgets(
    'start and end pickers save independent dates and preserve duration when moved',
    (tester) async {
      Map<String, dynamic>? saved;
      final events = EventRepository(
        httpClient: MockClient((request) async {
          saved = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        }),
        accessTokenProvider: () => 'token',
        edgeApiUrl: 'https://example.test/api/v1',
      );
      final originalStart = DateTime(2099, 9, 20, 10);
      final selectedEnd = DateTime(2099, 9, 22, 9);
      await tester.pumpWidget(
        MaterialApp(
          home: CreateEventScreen(
            onCreated: () {},
            initialEvent: _eventWithOptions(),
            eventRepository: events,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Date'), findsNothing);
      Future<void> choose(
        String field,
        DateTime selected, {
        bool cancel = false,
      }) async {
        final row = find.byKey(Key(field));
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        final wheel = tester.widget<CupertinoDatePicker>(
          find.byType(CupertinoDatePicker),
        );
        expect(wheel.mode, CupertinoDatePickerMode.dateAndTime);
        wheel.onDateTimeChanged(selected);
        if (cancel) {
          Navigator.of(tester.element(find.byType(AppDateTimeSheet))).pop();
        } else {
          await tester.tap(find.byKey(const Key('use-event-date-time')));
        }
        await tester.pumpAndSettle();
      }

      Future<void> save() async {
        await tester.ensureVisible(
          find.byKey(const Key('publish-event-button')),
        );
        await tester.tap(find.byKey(const Key('publish-event-button')));
        await tester.pumpAndSettle();
      }

      await choose('event-end-date-time', selectedEnd);
      await save();
      expect(DateTime.parse(saved!['start_at']).toLocal(), originalStart);
      expect(DateTime.parse(saved!['end_at']).toLocal(), selectedEnd);

      final movedStart = DateTime(2099, 9, 25, 18);
      await choose('event-start-date-time', movedStart, cancel: true);
      await save();
      expect(DateTime.parse(saved!['start_at']).toLocal(), originalStart);
      await choose('event-start-date-time', movedStart);
      await save();
      expect(DateTime.parse(saved!['start_at']).toLocal(), movedStart);
      expect(
        DateTime.parse(saved!['end_at']).toLocal(),
        movedStart.add(selectedEnd.difference(originalStart)),
      );
      await tester.ensureVisible(find.byKey(const Key('event-end-date-time')));
      await tester.tap(find.byKey(const Key('event-end-date-time')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
            .minimumDate,
        movedStart.add(const Duration(minutes: 1)),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('copying a past multi-day event retains its whole duration', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    final template = _eventWithOptions(
      startAt: DateTime(2025, 1, 1, 18),
      endAt: DateTime(2025, 1, 3, 9),
    );
    final events = EventRepository(
      httpClient: MockClient((request) async {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'created-event'}), 201);
      }),
      accessTokenProvider: () => 'token',
      edgeApiUrl: 'https://example.test/api/v1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CreateEventScreen(
          onCreated: () {},
          templateEvent: template,
          eventRepository: events,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('publish-event-button')));
    await tester.tap(find.byKey(const Key('publish-event-button')));
    await tester.pumpAndSettle();
    final start = DateTime.parse(saved!['start_at']);
    final end = DateTime.parse(saved!['end_at']);
    expect(start.isAfter(DateTime.now()), isTrue);
    expect(end.difference(start), template.endAt.difference(template.startAt));
  });

  testWidgets(
    'invalid optional values reopen their section before publishing',
    (tester) async {
      Map<String, dynamic>? saved;
      final events = EventRepository(
        httpClient: MockClient((request) async {
          saved = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        }),
        accessTokenProvider: () => 'token',
        edgeApiUrl: 'https://example.test/api/v1',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CreateEventScreen(
            onCreated: () {},
            initialEvent: _eventWithOptions(),
            eventRepository: events,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final guests = find.byKey(const Key('event-guests-options'));
      await tester.ensureVisible(guests);
      await tester.tap(guests);
      await tester.pumpAndSettle();
      final capacity = find.byKey(const Key('event-capacity-field'));
      await tester.ensureVisible(capacity);
      await tester.enterText(capacity, '');
      await tester.ensureVisible(guests);
      await tester.tap(find.text('Guests & capacity'));
      await tester.pumpAndSettle();
      expect(capacity, findsNothing);
      await tester.ensureVisible(find.byKey(const Key('publish-event-button')));
      await tester.tap(find.byKey(const Key('publish-event-button')));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Choose a limit from 2 to 500.'), findsOneWidget);
      expect(capacity.hitTestable(), findsOneWidget);
      await tester.enterText(capacity, '30');
      await tester.ensureVisible(guests);
      await tester.tap(find.text('Guests & capacity'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('publish-event-button')));
      await tester.tap(find.byKey(const Key('publish-event-button')));
      await tester.pumpAndSettle();
      expect(saved!['max_participants'], 30);
    },
  );

  testWidgets('new event hierarchy stays usable on a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: CreateEventScreen(onCreated: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('New event'), findsOneWidget);
    expect(find.text('Basics'), findsOneWidget);
    expect(find.byKey(const Key('event-ai-draft-button')), findsOneWidget);
    expect(find.byKey(const Key('event-ai-quality-button')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('event category uses the simple app choice sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CreateEventScreen(onCreated: () {})),
    );
    await tester.pump();

    expect(find.byKey(const Key('event-category-field')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byKey(const Key('event-ai-quality-button')), findsNothing);
    expect(find.text('Check event quality with AI'), findsNothing);
    expect(find.text('Basics'), findsOneWidget);
    expect(find.text('Make a plan'), findsNothing);

    await tester.tap(find.byKey(const Key('event-category-field')));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(
      find.byKey(const Key('app-choice-sheet-title')),
    );
    expect(title.data, 'Category');

    await tester.tap(find.byKey(const ValueKey('app-choice-Running')));
    await tester.pumpAndSettle();
    expect(find.text('Running'), findsOneWidget);
  });

  for (final namedVenue in [true, false]) {
    testWidgets(
      'address-only form saves ${namedVenue ? 'a venue' : 'a street address'} and its map pin',
      (tester) async {
        Map<String, dynamic>? savedEvent;
        final events = EventRepository(
          httpClient: MockClient((request) async {
            savedEvent = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(jsonEncode({'id': 'created-event'}), 201);
          }),
          accessTokenProvider: () => 'access-token',
          edgeApiUrl: 'https://example.test/api/v1',
        );
        final places = PlaceRepository(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': '51a-place',
                    if (namedVenue) 'name': 'Kunsthalle Mannheim',
                    'formatted_address':
                        'Friedrichsplatz 4, 68165 Mannheim, Germany',
                    'address_line1': namedVenue
                        ? 'Kunsthalle Mannheim'
                        : 'Friedrichsplatz 4',
                    'address_line2':
                        'Friedrichsplatz 4, 68165 Mannheim, Germany',
                    'country_code': 'de',
                    'latitude': 49.4842,
                    'longitude': 8.4755,
                    'result_type': namedVenue ? 'amenity' : 'building',
                    'timezone': 'Europe/Berlin',
                  },
                ],
              }),
              200,
            ),
          ),
          accessTokenProvider: () => 'access-token',
          edgeApiUrl: 'https://gather2gether.pages.dev/api/v1',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: CreateEventScreen(
              onCreated: () {},
              placeRepository: places,
              eventRepository: events,
            ),
          ),
        );

        expect(find.text('Use current location'), findsNothing);
        expect(find.widgetWithText(TextFormField, 'Venue name'), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Event title'),
          'An afternoon together',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'What should people know?'),
          'Meet at the entrance.',
        );

        await tester.enterText(
          find.byKey(const Key('event-address-field')),
          'Kunsthalle',
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();

        final suggestion = find.byKey(
          const ValueKey('place-suggestion-51a-place'),
        );
        expect(suggestion, findsOneWidget);
        await tester.ensureVisible(suggestion);
        await tester.pumpAndSettle();
        await tester.tap(suggestion);
        await tester.pump();

        expect(find.text('Kunsthalle Mannheim'), findsNothing);
        expect(find.text('Use current location'), findsNothing);
        final address = tester.widget<TextFormField>(
          find.byKey(const Key('event-address-field')),
        );
        expect(address.controller?.text, contains('Germany'));
        await tester.scrollUntilVisible(
          find.byKey(const Key('publish-event-button')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('publish-event-button')));
        await tester.pumpAndSettle();

        expect(savedEvent, isNotNull);
        expect(
          savedEvent!['venue_name'],
          namedVenue ? 'Kunsthalle Mannheim' : 'Friedrichsplatz 4',
        );
        expect(
          savedEvent!['address'],
          'Friedrichsplatz 4, 68165 Mannheim, Germany',
        );
        expect(savedEvent!['latitude'], 49.4842);
        expect(savedEvent!['longitude'], 8.4755);
      },
    );
  }

  testWidgets('an unavailable address route uses a helpful message', (
    tester,
  ) async {
    final places = PlaceRepository(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'route_not_found',
              'message': 'API route was not found.',
            },
          }),
          404,
        ),
      ),
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: 'https://gather2gether.pages.dev/api/v1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CreateEventScreen(onCreated: () {}, placeRepository: places),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('event-address-field')),
      'Berlin',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(
      find.text('Address search is being set up. Please try again shortly.'),
      findsOneWidget,
    );
    expect(find.text('API route was not found.'), findsNothing);
  });

  testWidgets('create again prefills useful event details as a new event', (
    tester,
  ) async {
    final template = EventSummary(
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
      startAt: DateTime(2025, 1, 1, 8),
      endAt: DateTime(2025, 1, 1, 9),
      maxParticipants: 10,
      joinedCount: 4,
      tentativeCount: 2,
      distanceMeters: 0,
      userRsvpStatus: 'joined',
      viewerIsOrganizer: true,
      beginnerFriendly: true,
      eventSetting: 'outdoor',
      eventLanguage: 'English',
      whatToBring: 'Water',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CreateEventScreen(onCreated: () {}, templateEvent: template),
      ),
    );
    await tester.pump();

    expect(find.text('Create again'), findsOneWidget);
    expect(find.text('Morning Run'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('event-details-options')));
    await tester.tap(find.byKey(const Key('event-details-options')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('event-beginner-friendly')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Outdoor'), findsOneWidget);
    final language = tester.widget<TextFormField>(
      find.byKey(const Key('event-language-field')),
    );
    expect(language.controller?.text, 'English');
  });

  testWidgets('AI drafting fills editable fields without publishing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateEventScreen(
          onCreated: () {},
          assistantRepository: _FakeAssistantRepository(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('event-ai-draft-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('event-ai-idea-field')),
      'A welcoming photography walk for complete beginners',
    );
    await tester.tap(find.byKey(const Key('event-ai-generate-button')));
    await tester.pumpAndSettle();

    expect(find.text('Beginner photo walk'), findsOneWidget);
    expect(find.text('Photography'), findsOneWidget);
    expect(
      find.text('Draft added. Review the details before publishing.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'publishing controls expose unlisted and bounded repeat options',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: CreateEventScreen(onCreated: () {})),
      );
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const Key('event-sharing-options')),
      );
      await tester.tap(find.byKey(const Key('event-sharing-options')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('event-visibility-field')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('event-visibility-field')), findsOneWidget);
      expect(find.byKey(const Key('event-repeat-field')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('save-event-draft-button')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('save-event-draft-button')), findsOneWidget);
    },
  );
}
