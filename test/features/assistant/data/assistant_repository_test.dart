import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/assistant/data/assistant_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const apiUrl = 'https://gather2gether.pages.dev/api/v1';

  test(
    'assistant sends location context only to the authenticated edge API',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/assistant/chat');
        expect(request.headers['authorization'], 'Bearer access-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, {
          'message': 'Any running events near me?',
          'latitude': 52.52,
          'longitude': 13.405,
          'radius_km': 10.0,
        });
        return http.Response(
          jsonEncode({
            'message': {
              'id': 2,
              'role': 'assistant',
              'content': 'Morning Run is nearby.',
              'created_at': '2099-01-01T07:00:00Z',
            },
            'event_matches': [
              {
                'id': '22222222-2222-4222-8222-222222222222',
                'title': 'Morning Run',
                'category': 'Running',
                'venue_name': 'City Park',
                'start_at': '2099-01-01T08:00:00Z',
                'distance_meters': 850,
              },
            ],
          }),
          200,
        );
      });
      final repository = AssistantRepository(
        httpClient: client,
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: apiUrl,
      );

      final reply = await repository.sendMessage(
        message: ' Any running events near me? ',
        latitude: 52.52,
        longitude: 13.405,
        radiusKm: 10,
      );

      expect(reply.message.content, 'Morning Run is nearby.');
      expect(reply.eventMatches.single.title, 'Morning Run');
    },
  );

  test('assistant history remains ordered data from the edge API', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'data': [
            {
              'id': 1,
              'role': 'user',
              'content': 'How do I join?',
              'created_at': '2099-01-01T07:00:00Z',
            },
            {
              'id': 2,
              'role': 'assistant',
              'content': 'Open an event and choose Join.',
              'created_at': '2099-01-01T07:00:01Z',
            },
          ],
        }),
        200,
      ),
    );
    final repository = AssistantRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    final history = await repository.history();

    expect(history.map((item) => item.role), ['user', 'assistant']);
  });

  test('assistant preserves safe rate-limit errors for the UI', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'assistant_rate_limited',
            'message': 'Please wait a moment before sending another message.',
          },
        }),
        429,
      ),
    );
    final repository = AssistantRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    await expectLater(
      repository.sendMessage(message: 'Hello', radiusKm: 10),
      throwsA(
        isA<AssistantApiException>()
            .having((error) => error.statusCode, 'statusCode', 429)
            .having((error) => error.code, 'code', 'assistant_rate_limited'),
      ),
    );
  });

  test('event drafting returns a typed editable draft', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/assistant/event-draft');
      expect(jsonDecode(request.body), {
        'prompt': 'A relaxed photo walk for beginners',
        'locale': 'en-DE',
      });
      return http.Response(
        jsonEncode({
          'draft': {
            'title': 'Beginner photo walk',
            'description': 'Practise photography together.',
            'category': 'Photography',
            'beginner_friendly': true,
            'event_setting': 'outdoor',
            'event_language': 'English',
            'age_guidance': 'all_ages',
            'what_to_bring': 'A phone or camera',
          },
        }),
        200,
      );
    });
    final repository = AssistantRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    final draft = await repository.draftEvent(
      prompt: ' A relaxed photo walk for beginners ',
      locale: 'en-DE',
    );

    expect(draft.title, 'Beginner photo walk');
    expect(draft.category, 'Photography');
    expect(draft.beginnerFriendly, isTrue);
  });
}
