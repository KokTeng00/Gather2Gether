import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/notifications/data/push_device_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const apiUrl = 'https://gather2gether.pages.dev/api/v1';
  const token = 'fcm-device-token-with-enough-entropy';

  test('register sends only the current device metadata', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/v1/push/devices');
      expect(request.headers['authorization'], 'Bearer access-token');
      expect(jsonDecode(request.body), {
        'token': token,
        'platform': 'android',
        'locale': 'en-GB',
      });
      return http.Response(jsonEncode({'registered': true}), 200);
    });
    final repository = PushDeviceRepository(
      httpClient: client,
      edgeApiUrl: apiUrl,
      accessTokenProvider: () => 'access-token',
    );

    await repository.register(
      token: token,
      platform: 'android',
      locale: 'en-GB',
    );
  });

  test('unregister removes only the supplied current token', () async {
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/api/v1/push/devices');
      expect(jsonDecode(request.body), {'token': token});
      return http.Response(jsonEncode({'removed': true}), 200);
    });
    final repository = PushDeviceRepository(
      httpClient: client,
      edgeApiUrl: apiUrl,
      accessTokenProvider: () => 'access-token',
    );

    await repository.unregister(token);
  });
}
