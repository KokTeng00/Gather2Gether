import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_filters.dart';
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
        expect(body['beginner_friendly'], isTrue);
        expect(body['wheelchair_accessible'], isTrue);
        expect(body['event_setting'], 'outdoor');
        expect(body['event_language'], 'English');
        expect(body['age_guidance'], 'adults');
        expect(body['what_to_bring'], 'Water');
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
          beginnerFriendly: true,
          wheelchairAccessible: true,
          eventSetting: 'outdoor',
          eventLanguage: 'English',
          ageGuidance: 'adults',
          whatToBring: 'Water',
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

  test('my events retain lifecycle fields from the edge API', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/events/mine');
      expect(request.url.queryParameters['filter'], 'tentative');
      return http.Response(
        jsonEncode({
          'data': [
            {
              ...eventJson(eventId),
              'event_status': 'published',
              'is_saved': true,
              'reminder_at': '2098-12-31T08:00:00Z',
              'waitlist_position': 2,
              'viewer_is_organizer': false,
              'user_rsvp_status': 'waitlisted',
            },
          ],
        }),
        200,
      );
    });
    final repository = EventRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    final event = (await repository.myEvents('tentative')).single;

    expect(event.isSaved, isTrue);
    expect(event.userRsvpStatus, 'waitlisted');
    expect(event.waitlistPosition, 2);
    expect(event.reminderAt, isNotNull);
  });

  test('a full event can return a waitlist RSVP state', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/v1/events/$eventId/rsvp');
      return http.Response(jsonEncode({'status': 'waitlisted'}), 200);
    });
    final repository = EventRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    expect(await repository.updateRsvp(eventId, 'joined'), 'waitlisted');
  });

  test('saved state uses PUT and DELETE without a request body', () async {
    final methods = <String>[];
    final client = MockClient((request) async {
      methods.add(request.method);
      expect(request.url.path, '/api/v1/events/$eventId/save');
      return http.Response(jsonEncode({'saved': request.method == 'PUT'}), 200);
    });
    final repository = EventRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    expect(await repository.setSaved(eventId, true), isTrue);
    expect(await repository.setSaved(eventId, false), isFalse);
    expect(methods, ['PUT', 'DELETE']);
  });

  test(
    'discovery sends category, time, availability, and following filters',
    () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['category'], 'Games');
        expect(request.url.queryParameters['time_filter'], 'evening');
        expect(request.url.queryParameters['spots_only'], 'true');
        expect(request.url.queryParameters['following_only'], 'true');
        expect(
          request.url.queryParameters['timezone_offset_minutes'],
          isNotNull,
        );
        return http.Response(jsonEncode({'data': <Object>[]}), 200);
      });
      final repository = EventRepository(
        httpClient: client,
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: apiUrl,
      );

      await repository.nearbyEvents(
        latitude: 52.52,
        longitude: 13.405,
        radiusKm: 10,
        filters: const EventDiscoveryFilters(
          category: 'Games',
          timeFilter: 'evening',
          spotsOnly: true,
          followingOnly: true,
        ),
      );
    },
  );

  test(
    'saved searches and attendee controls use their narrow API routes',
    () async {
      const searchId = '88888888-8888-4888-8888-888888888888';
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/event-searches')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['timezone_offset_minutes'], isA<int>());
          return http.Response(jsonEncode({'id': searchId}), 201);
        }
        if (request.url.path.endsWith('/attendees')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'profile_id': '11111111-1111-4111-8111-111111111111',
                  'display_name': 'Alex',
                  'username': 'alex',
                  'rsvp_status': 'joined',
                  'visible_to_attendees': true,
                  'is_self': false,
                  'reconfirmed_at': '2098-12-31T08:00:00Z',
                },
              ],
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/attendees/visibility')) {
          return http.Response(jsonEncode({'visible': true}), 200);
        }
        if (request.url.path.endsWith('/discussion-notifications')) {
          return http.Response(jsonEncode({'enabled': false}), 200);
        }
        if (request.url.path.endsWith('/reconfirmation/request')) {
          return http.Response(
            jsonEncode({'deadline_at': '2098-12-31T18:00:00Z'}),
            200,
          );
        }
        if (request.url.path.endsWith('/reconfirmation/confirm')) {
          return http.Response(
            jsonEncode({'confirmed_at': '2098-12-31T12:00:00Z'}),
            200,
          );
        }
        throw StateError('Unexpected request: ${request.url}');
      });
      final repository = EventRepository(
        httpClient: client,
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: apiUrl,
      );

      expect(
        await repository.saveSearch(
          name: 'Games',
          interest: 'board games',
          radiusKm: 10,
          filters: const EventDiscoveryFilters(category: 'Games'),
        ),
        searchId,
      );
      expect((await repository.attendees(eventId)).single.username, 'alex');
      expect(await repository.setAttendeeVisibility(eventId, true), isTrue);
      expect(
        await repository.setDiscussionNotifications(eventId, false),
        isFalse,
      );
      expect(
        (await repository.requestRsvpReconfirmation(eventId)).isUtc,
        isFalse,
      );
      expect((await repository.confirmRsvp(eventId)).isUtc, isFalse);
      expect(paths, [
        'POST /api/v1/event-searches',
        'GET /api/v1/events/$eventId/attendees',
        'PUT /api/v1/events/$eventId/attendees/visibility',
        'PUT /api/v1/events/$eventId/discussion-notifications',
        'POST /api/v1/events/$eventId/reconfirmation/request',
        'POST /api/v1/events/$eventId/reconfirmation/confirm',
      ]);
    },
  );
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
