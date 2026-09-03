import 'dart:convert';

import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/features/forum/domain/forum_comment.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ForumAccessTokenProvider = String? Function();

class ForumApiException implements Exception {
  const ForumApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ForumApiException($code): $message';
}

class ForumLikeState {
  const ForumLikeState({required this.liked, required this.likeCount});

  factory ForumLikeState.fromJson(Map<String, dynamic> json) {
    final rawCount = json['like_count'];
    return ForumLikeState(
      liked: json['liked'] == true,
      likeCount: rawCount is int ? rawCount : int.tryParse('$rawCount') ?? 0,
    );
  }

  final bool liked;
  final int likeCount;
}

class ForumRepository {
  ForumRepository({
    http.Client? httpClient,
    ForumAccessTokenProvider? accessTokenProvider,
    String? edgeApiUrl,
  }) : _httpClient = httpClient ?? _sharedHttpClient,
       _accessTokenProvider =
           accessTokenProvider ??
           (() => Supabase.instance.client.auth.currentSession?.accessToken),
       _edgeApiUrl = edgeApiUrl ?? AppConfig.edgeApiUrl;

  static final http.Client _sharedHttpClient = http.Client();
  static const _timeout = Duration(seconds: 20);

  final http.Client _httpClient;
  final ForumAccessTokenProvider _accessTokenProvider;
  final String _edgeApiUrl;

  Future<List<ForumPost>> listPosts() async {
    return _postList(await _request('GET', 'forum/posts'));
  }

  Future<List<ForumPost>> searchPosts(String interest) async {
    final normalized = interest.trim();
    if (normalized.isEmpty) return listPosts();
    return _postList(
      await _request('GET', 'forum/posts', query: {'interest': normalized}),
    );
  }

  Future<List<ForumPost>> listOwnPosts() async {
    final posts = _postList(await _request('GET', 'forum/posts?scope=mine'));
    // Older edge deployments ignore the scope query and return the regular
    // feed. viewer_is_author has been part of that contract from the start, so
    // this keeps staged mobile/edge rollouts safe without showing other users'
    // posts on the signed-in member's profile.
    return posts.where((post) => post.viewerIsAuthor).toList(growable: false);
  }

  List<ForumPost> _postList(Object? response) {
    final payload = _map(response);
    final rows = payload['data'];
    if (rows is! List<dynamic>) throw _invalidResponse('post data');
    return rows
        .map((row) => ForumPost.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<ForumPost> getPost(String postId) async {
    final payload = _map(await _request('GET', 'forum/posts/$postId'));
    return ForumPost.fromJson(_map(payload['data']));
  }

  Future<List<ForumComment>> listComments(String postId) async {
    final payload = _map(await _request('GET', 'forum/posts/$postId/comments'));
    final rows = payload['data'];
    if (rows is! List<dynamic>) throw _invalidResponse('comment data');
    return rows
        .map((row) => ForumComment.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<String> createPost({
    required String title,
    required String body,
    required String category,
    PreparedImage? image,
    String? placeName,
    String? placeAddress,
  }) async {
    final normalizedPlaceName = _trimmedOrNull(placeName);
    final normalizedPlaceAddress = _trimmedOrNull(placeAddress);
    if ((normalizedPlaceName == null) != (normalizedPlaceAddress == null)) {
      throw const ForumApiException(
        statusCode: 400,
        code: 'forum_validation',
        message: 'Add both a public place name and address.',
      );
    }

    final imageToken = image == null ? null : await _uploadImage(image);
    final payload = _map(
      await _request(
        'POST',
        'forum/posts',
        body: {
          'title': title.trim(),
          'body': body.trim(),
          'category': category,
          'image_token': imageToken,
          'place_name': normalizedPlaceName,
          'place_address': normalizedPlaceAddress,
        },
      ),
    );
    return _id(payload, 'post');
  }

  Future<String> createComment({
    required String postId,
    required String body,
  }) async {
    final payload = _map(
      await _request(
        'POST',
        'forum/posts/$postId/comments',
        body: {'body': body.trim()},
      ),
    );
    return _id(payload, 'comment');
  }

  Future<ForumLikeState> setPostLike({
    required String postId,
    required bool liked,
  }) async {
    final payload = _map(
      await _request('PUT', 'forum/posts/$postId/like', body: {'liked': liked}),
    );
    return ForumLikeState.fromJson(_map(payload['data']));
  }

  Future<void> reportPost(String postId, String reason) =>
      _request('POST', 'forum/posts/$postId/report', body: {'reason': reason});

  Future<void> reportComment(String commentId, String reason) => _request(
    'POST',
    'forum/comments/$commentId/report',
    body: {'reason': reason},
  );

  String mediaUrl(String postId) =>
      _uri('forum/posts/${Uri.encodeComponent(postId)}/media').toString();

  Map<String, String> mediaHeaders() {
    final token = _accessTokenProvider();
    return {
      'Accept': PreparedImage.jpegContentType,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<String> _uploadImage(PreparedImage image) async {
    if (image.bytes.isEmpty || image.bytes.length > PreparedImage.maxBytes) {
      throw const ForumApiException(
        statusCode: 400,
        code: 'invalid_forum_image',
        message: 'Choose a JPEG photo under 5 MB.',
      );
    }

    final token = _requiredAccessToken();
    final response = await _httpClient
        .post(
          _uri('forum/media'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'Content-Type': image.contentType,
          },
          body: image.bytes,
        )
        .timeout(_timeout);
    final payload = _map(_responsePayload(response));
    final uploadToken = payload['token'];
    if (uploadToken is! String || uploadToken.isEmpty) {
      throw _invalidResponse('image token');
    }
    return uploadToken;
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final token = _requiredAccessToken();
    var uri = _uri(path);
    if (query != null) uri = uri.replace(queryParameters: query);
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final future = switch (method) {
      'GET' => _httpClient.get(uri, headers: headers),
      'POST' => _httpClient.post(uri, headers: headers, body: jsonEncode(body)),
      'PUT' => _httpClient.put(uri, headers: headers, body: jsonEncode(body)),
      _ => throw ArgumentError.value(
        method,
        'method',
        'Unsupported HTTP method',
      ),
    };
    final response = await future.timeout(_timeout);
    return _responsePayload(response);
  }

  Object? _responsePayload(http.Response response) {
    Object? payload;
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(response.body);
      } on FormatException {
        throw _invalidResponse('JSON');
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = payload is Map<String, dynamic> ? payload['error'] : null;
      final details = error is Map<String, dynamic>
          ? error
          : const <String, dynamic>{};
      throw ForumApiException(
        statusCode: response.statusCode,
        code: details['code'] is String
            ? details['code'] as String
            : 'edge_request_failed',
        message: details['message'] is String
            ? details['message'] as String
            : 'The request failed. Please try again.',
      );
    }
    return payload;
  }

  String _requiredAccessToken() {
    final token = _accessTokenProvider();
    if (token == null || token.isEmpty) {
      throw const ForumApiException(
        statusCode: 401,
        code: 'authentication_required',
        message: 'Sign in is required.',
      );
    }
    return token;
  }

  Uri _uri(String path) {
    final base = _edgeApiUrl.endsWith('/')
        ? _edgeApiUrl.substring(0, _edgeApiUrl.length - 1)
        : _edgeApiUrl;
    return Uri.parse('$base/$path');
  }

  String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  String _id(Map<String, dynamic> payload, String kind) {
    final id = payload['id'];
    if (id is! String || id.isEmpty) throw _invalidResponse('$kind identifier');
    return id;
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw _invalidResponse('data');
  }

  ForumApiException _invalidResponse(String value) => ForumApiException(
    statusCode: 502,
    code: 'invalid_edge_response',
    message: 'The edge API returned invalid $value.',
  );
}
