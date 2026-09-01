import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const apiUrl = 'https://gather2gether.pages.dev/api/v1';

  test('avatar upload sends authenticated privacy-safe JPEG bytes', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/profile/avatar');
      expect(request.headers['authorization'], 'Bearer access-token');
      expect(request.headers['content-type'], PreparedImage.jpegContentType);
      expect(request.bodyBytes, bytes);
      return http.Response('', 204);
    });
    final repository = ProfileRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    await repository.uploadAvatar(PreparedImage(bytes: bytes));
  });

  test('avatar deletion uses the authenticated profile endpoint', () async {
    final client = MockClient((request) async {
      expect(request.method, 'DELETE');
      expect(request.url.path, '/api/v1/profile/avatar');
      expect(request.headers['authorization'], 'Bearer access-token');
      return http.Response('', 204);
    });
    final repository = ProfileRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    await repository.deleteAvatar();
  });

  test('empty avatars are rejected before making a network request', () async {
    var called = false;
    final repository = ProfileRepository(
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('', 204);
      }),
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    await expectLater(
      repository.uploadAvatar(PreparedImage(bytes: Uint8List(0))),
      throwsArgumentError,
    );
    expect(called, isFalse);
  });

  test('avatar changes require an authenticated access token', () async {
    final repository = ProfileRepository(
      httpClient: MockClient((_) async => http.Response('', 204)),
      accessTokenProvider: () => null,
      edgeApiUrl: apiUrl,
    );

    await expectLater(
      repository.deleteAvatar(),
      throwsA(
        isA<ProfileApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.code, 'code', 'authentication_required'),
      ),
    );
  });

  test('safe avatar API errors remain available to the UI', () async {
    final repository = ProfileRepository(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'avatar_too_large',
              'message': 'Choose an image smaller than 5 MB.',
            },
          }),
          413,
        ),
      ),
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    await expectLater(
      repository.uploadAvatar(
        PreparedImage(bytes: Uint8List.fromList([1, 2, 3])),
      ),
      throwsA(
        isA<ProfileApiException>()
            .having((error) => error.statusCode, 'statusCode', 413)
            .having((error) => error.code, 'code', 'avatar_too_large'),
      ),
    );
  });
}
