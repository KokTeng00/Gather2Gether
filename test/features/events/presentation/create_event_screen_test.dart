import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/events/presentation/create_event_screen.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/places/data/place_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('event category uses the simple app choice sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CreateEventScreen(onCreated: () {})),
    );
    await tester.pump();

    expect(find.byKey(const Key('event-category-field')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

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

  testWidgets('selecting an address suggestion sets its venue and map pin', (
    tester,
  ) async {
    final places = PlaceRepository(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': [
              {
                'id': '51a-place',
                'name': 'Kunsthalle Mannheim',
                'formatted_address':
                    'Friedrichsplatz 4, 68165 Mannheim, Germany',
                'address_line1': 'Kunsthalle Mannheim',
                'address_line2': 'Friedrichsplatz 4, 68165 Mannheim, Germany',
                'country_code': 'de',
                'latitude': 49.4842,
                'longitude': 8.4755,
                'result_type': 'amenity',
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
        home: CreateEventScreen(onCreated: () {}, placeRepository: places),
      ),
    );

    expect(find.text('Use current location'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('event-address-field')),
      'Kunsthalle',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final suggestion = find.byKey(const ValueKey('place-suggestion-51a-place'));
    expect(suggestion, findsOneWidget);
    await tester.ensureVisible(suggestion);
    await tester.pumpAndSettle();
    await tester.tap(suggestion);
    await tester.pump();

    expect(find.text('Kunsthalle Mannheim'), findsOneWidget);
    expect(find.text('Use current location'), findsNothing);
    final address = tester.widget<TextFormField>(
      find.byKey(const Key('event-address-field')),
    );
    expect(address.controller?.text, contains('Germany'));
  });

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

    expect(find.text('Create Again'), findsOneWidget);
    expect(find.text('Run it again'), findsOneWidget);
    expect(find.text('Morning Run'), findsOneWidget);
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
}
