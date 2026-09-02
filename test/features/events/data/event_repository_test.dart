import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const apiUrl = 'https://gather2gether.pages.dev/api/v1';
  const eventId = '22222222-2222-4222-8222-222222222222';

  test(
    'nearby events are requested through the authenticated edge API',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/events/nearby');
        expect(request.url.queryParameters['latitude'], '52.52');
        expect(request.url.queryParameters['radius_km'], '10.0');
        expect(
          request.url.queryParameters['interest'],
          'quiet outdoor activities',
        );
        expect(request.headers['authorization'], 'Bearer access-token');
        return http.Response(
          jsonEncode({
            'data': [eventJson(eventId)],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final repository = EventRepository(
        httpClient: client,
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: apiUrl,
      );

      final events = await repository.nearbyEvents(
        latitude: 52.52,
        longitude: 13.405,
        radiusKm: 10,
        interest: ' quiet outdoor activities ',
      );

      expect(events.single.id, eventId);
      expect(events.single.title, 'Morning Run');
    },
  );

  test(
    'event creation sends the public API contract instead of RPC parameters',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/events');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['title'], 'Morning Run');
        expect(body['venue_name'], 'City Park');
        expect(body['p_title'], isNull);
        return http.Response(jsonEncode({'id': eventId}), 201);
      });
      final repository = EventRepository(
        httpClient: client,
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: apiUrl,
      );

      final createdId = await repository.createEvent(
        CreateEventInput(
          title: ' Morning Run ',
          description: 'An easy social run.',
          category: 'Running',
          venueName: 'City Park',
          address: 'Main entrance',
          latitude: 52.52,
          longitude: 13.405,
          startAt: DateTime.utc(2099, 1, 1, 8),
          endAt: DateTime.utc(2099, 1, 1, 9),
          maxParticipants: 10,
        ),
      );

      expect(createdId, eventId);
    },
  );

  test('safe edge error codes are retained for UI messaging', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {'code': 'event_full', 'message': 'This event is full.'},
        }),
        409,
      ),
    );
    final repository = EventRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    await expectLater(
      repository.setRsvp(eventId, 'joined'),
      throwsA(
        isA<EdgeApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having((error) => error.code, 'code', 'event_full'),
      ),
    );
  });
}

Map<String, dynamic> eventJson(String eventId) => {
  'id': eventId,
  'organizer_id': '11111111-1111-4111-8111-111111111111',
  'organizer_name': 'Alex',
  'title': 'Morning Run',
  'description': 'An easy social run.',
  'category': 'Running',
  'venue_name': 'City Park',
  'address': 'Main entrance',
  'latitude': 52.52,
  'longitude': 13.405,
  'start_at': '2099-01-01T08:00:00Z',
  'end_at': '2099-01-01T09:00:00Z',
  'max_participants': 10,
  'joined_count': 4,
  'tentative_count': 2,
  'distance_meters': 850.5,
  'user_rsvp_status': 'tentative',
};
