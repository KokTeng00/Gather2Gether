import 'dart:convert';

import 'package:gather2gether/config/app_config.dart';
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
    final payload = _map(await _request('GET', 'forum/posts'));
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
  }) async {
    final payload = _map(
      await _request(
        'POST',
        'forum/posts',
        body: {
          'title': title.trim(),
          'body': body.trim(),
          'category': category,
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

  Future<void> reportPost(String postId, String reason) =>
      _request('POST', 'forum/posts/$postId/report', body: {'reason': reason});

  Future<void> reportComment(String commentId, String reason) => _request(
    'POST',
    'forum/comments/$commentId/report',
    body: {'reason': reason},
  );

  Future<Object?> _request(String method, String path, {Object? body}) async {
    final token = _accessTokenProvider();
    if (token == null || token.isEmpty) {
      throw const ForumApiException(
        statusCode: 401,
        code: 'authentication_required',
        message: 'Sign in is required.',
      );
    }

    final base = _edgeApiUrl.endsWith('/')
        ? _edgeApiUrl.substring(0, _edgeApiUrl.length - 1)
        : _edgeApiUrl;
    final uri = Uri.parse('$base/$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final future = switch (method) {
      'GET' => _httpClient.get(uri, headers: headers),
      'POST' => _httpClient.post(uri, headers: headers, body: jsonEncode(body)),
      _ => throw ArgumentError.value(
        method,
        'method',
        'Unsupported HTTP method',
      ),
    };
    final response = await future.timeout(_timeout);
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
