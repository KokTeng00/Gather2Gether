import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const apiUrl = 'https://gather2gether.pages.dev/api/v1';
  const postId = '33333333-3333-4333-8333-333333333333';

  test('forum feed uses the authenticated Cloudflare API', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/forum/posts');
      expect(request.headers['authorization'], 'Bearer access-token');
      return http.Response(
        jsonEncode({
          'data': [forumPostJson(postId)],
        }),
        200,
      );
    });
    final repository = ForumRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    final posts = await repository.listPosts();

    expect(posts.single.id, postId);
    expect(posts.single.commentCount, 2);
    expect(posts.single.isLocked, isFalse);
  });

  test('new discussions send only the public API contract', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/forum/posts');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body, {
        'title': 'Sunday walking group',
        'body': 'Would anyone like to meet at the park?',
        'category': 'Looking for group',
      });
      expect(body['author_id'], isNull);
      return http.Response(jsonEncode({'id': postId}), 201);
    });
    final repository = ForumRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    final createdId = await repository.createPost(
      title: ' Sunday walking group ',
      body: ' Would anyone like to meet at the park? ',
      category: 'Looking for group',
    );

    expect(createdId, postId);
  });

  test('forum rate-limit response is preserved for the UI', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'code': 'forum_rate_limited',
            'message':
                'You are posting too quickly. Please wait and try again.',
          },
        }),
        429,
      ),
    );
    final repository = ForumRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    await expectLater(
      repository.createComment(postId: postId, body: 'Count me in!'),
      throwsA(
        isA<ForumApiException>()
            .having((error) => error.statusCode, 'statusCode', 429)
            .having((error) => error.code, 'code', 'forum_rate_limited'),
      ),
    );
  });
}

Map<String, dynamic> forumPostJson(String postId) => {
  'id': postId,
  'author_id': '11111111-1111-4111-8111-111111111111',
  'author_name': 'Alex',
  'category': 'Looking for group',
  'title': 'Sunday walking group',
  'body': 'Would anyone like to meet at the park?',
  'status': 'active',
  'created_at': '2026-08-23T10:00:00Z',
  'last_activity_at': '2026-08-23T11:00:00Z',
  'comment_count': 2,
  'viewer_is_author': false,
};
