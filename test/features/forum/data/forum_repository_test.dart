import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const apiUrl = 'https://gather2gether.pages.dev/api/v1';
  const postId = '33333333-3333-4333-8333-333333333333';
  const imageToken = '44444444-4444-4444-8444-444444444444';

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
    expect(posts.single.hasImage, isFalse);
    expect(posts.single.hasPlace, isFalse);
  });

  test('semantic community search sends a trimmed interest query', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/forum/posts');
      expect(request.url.queryParameters, {
        'interest': 'people learning new skills',
        'planning': '1',
      });
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

    final posts = await repository.searchPosts(
      '  people learning new skills  ',
    );

    expect(posts.single.id, postId);
  });

  test(
    'own discussion list scopes the collection and filters legacy feed rows',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/forum/posts');
        expect(request.url.queryParameters, {'scope': 'mine'});
        expect(request.headers['authorization'], 'Bearer access-token');
        return http.Response(
          jsonEncode({
            'data': [
              forumPostJson(postId),
              {
                ...forumPostJson('55555555-5555-4555-8555-555555555555'),
                'viewer_is_author': true,
              },
            ],
          }),
          200,
        );
      });
      final repository = ForumRepository(
        httpClient: client,
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: apiUrl,
      );

      final posts = await repository.listOwnPosts();

      expect(posts, hasLength(1));
      expect(posts.single.id, '55555555-5555-4555-8555-555555555555');
    },
  );

  test('new discussions send only the public API contract', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/forum/posts');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body, {
        'title': 'Sunday walking group',
        'body': 'Would anyone like to meet at the park?',
        'category': 'Looking for group',
        'image_token': null,
        'place_name': null,
        'place_address': null,
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

  test(
    'photo is staged before its token and place are sent to create',
    () async {
      var call = 0;
      final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
      final client = MockClient((request) async {
        call += 1;
        expect(request.headers['authorization'], 'Bearer access-token');
        if (call == 1) {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/forum/media');
          expect(request.headers['content-type'], 'image/jpeg');
          expect(request.bodyBytes, bytes);
          return http.Response(jsonEncode({'token': imageToken}), 201);
        }

        expect(request.url.path, '/api/v1/forum/posts');
        expect(jsonDecode(request.body), {
          'title': 'Coffee this weekend?',
          'body': 'The courtyard has plenty of space for a small group.',
          'category': 'Looking for group',
          'image_token': imageToken,
          'place_name': 'Courtyard Café',
          'place_address': '10 Market Street, Berlin',
        });
        return http.Response(jsonEncode({'id': postId}), 201);
      });
      final repository = ForumRepository(
        httpClient: client,
        accessTokenProvider: () => 'access-token',
        edgeApiUrl: apiUrl,
      );

      final createdId = await repository.createPost(
        title: ' Coffee this weekend? ',
        body: ' The courtyard has plenty of space for a small group. ',
        category: 'Looking for group',
        image: PreparedImage(bytes: bytes),
        placeName: ' Courtyard Café ',
        placeAddress: ' 10 Market Street, Berlin ',
      );

      expect(createdId, postId);
      expect(call, 2);
    },
  );

  test('a partial public-place tag is rejected before any request', () async {
    var called = false;
    final repository = ForumRepository(
      httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 500);
      }),
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    await expectLater(
      repository.createPost(
        title: 'Coffee this weekend?',
        body: 'Would anyone like to meet for coffee this weekend?',
        category: 'Looking for group',
        placeName: 'Courtyard Café',
      ),
      throwsA(
        isA<ForumApiException>().having(
          (error) => error.code,
          'code',
          'forum_validation',
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('new forum fields parse without breaking the legacy model', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'data': [
            {
              ...forumPostJson(postId),
              'has_image': true,
              'place_name': 'Tempelhof Field',
              'place_address': 'Tempelhofer Damm, Berlin',
            },
          ],
        }),
        200,
      ),
    );
    final repository = ForumRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    final post = (await repository.listPosts()).single;

    expect(post.hasImage, isTrue);
    expect(post.hasPlace, isTrue);
    expect(post.placeName, 'Tempelhof Field');
    expect(post.placeAddress, 'Tempelhofer Damm, Berlin');
    expect(repository.mediaUrl(postId), '$apiUrl/forum/posts/$postId/media');
    expect(repository.mediaHeaders()['Authorization'], 'Bearer access-token');
  });

  test('discussion detail parses its current like state', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/forum/posts/$postId');
      return http.Response(
        jsonEncode({
          'data': {...forumPostJson(postId), 'liked': true, 'like_count': 12},
        }),
        200,
      );
    });
    final repository = ForumRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    final post = await repository.getPost(postId);

    expect(post.viewerHasLiked, isTrue);
    expect(post.likeCount, 12);
  });

  test('like changes use the authenticated boolean API contract', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/v1/forum/posts/$postId/like');
      expect(request.headers['authorization'], 'Bearer access-token');
      expect(jsonDecode(request.body), {'liked': true});
      return http.Response(
        jsonEncode({
          'data': {'liked': true, 'like_count': 4, 'changed': true},
        }),
        200,
      );
    });
    final repository = ForumRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    final state = await repository.setPostLike(postId: postId, liked: true);

    expect(state.liked, isTrue);
    expect(state.likeCount, 4);
  });

  test('not-for-me hides only the selected forum recommendation', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/recommendations/hide');
      expect(request.headers['authorization'], 'Bearer access-token');
      expect(jsonDecode(request.body), {
        'content_kind': 'forum_post',
        'content_id': postId,
      });
      return http.Response(jsonEncode({'hidden': true}), 200);
    });
    final repository = ForumRepository(
      httpClient: client,
      accessTokenProvider: () => 'access-token',
      edgeApiUrl: apiUrl,
    );

    await repository.hidePostRecommendation(postId);
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
