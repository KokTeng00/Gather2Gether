import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/places/data/place_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const apiUrl = 'https://gather2gether.pages.dev/api/v1';

  test(
    'autocomplete requests worldwide suggestions through the edge API',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/places/autocomplete');
        expect(request.url.queryParameters['text'], 'Kunsthalle');
        expect(request.url.queryParameters['latitude'], '49.48');
        expect(request.url.queryParameters['longitude'], '8.47');
        expect(request.url.queryParameters['language'], 'de');
        expect(request.url.queryParameters.containsKey('country'), isFalse);
        expect(request.headers['authorization'], 'Bearer access-token');
        return http.Response(
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
        );
      });
      final repository = PlaceRepository(
        httpClient: client,
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: apiUrl,
      );

      final places = await repository.autocomplete(
        text: ' Kunsthalle ',
        latitude: 49.48,
        longitude: 8.47,
        language: 'DE',
      );

      expect(places.single.suggestedVenueName, 'Kunsthalle Mannheim');
      expect(places.single.formattedAddress, contains('Germany'));
      expect(places.single.timezone, 'Europe/Berlin');
    },
  );

  test(
    'autocomplete does not make a request before three characters',
    () async {
      final client = MockClient((_) async {
        fail('short queries must not call the edge API');
      });
      final repository = PlaceRepository(
        httpClient: client,
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: apiUrl,
      );

      expect(await repository.autocomplete(text: 'ab'), isEmpty);
    },
  );

  test('safe place-search errors are retained for the UI', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'place_search_busy',
            'message': 'Address suggestions are busy. Please wait and retry.',
          },
        }),
        429,
      ),
    );
    final repository = PlaceRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    await expectLater(
      repository.autocomplete(text: 'Berlin'),
      throwsA(
        isA<PlaceSearchException>()
            .having((error) => error.statusCode, 'statusCode', 429)
            .having((error) => error.code, 'code', 'place_search_busy'),
      ),
    );
  });
}
