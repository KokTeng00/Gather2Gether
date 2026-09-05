import 'dart:convert';

import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/features/assistant/domain/assistant_message.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AssistantAccessTokenProvider = String? Function();

class AssistantApiException implements Exception {
  const AssistantApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'AssistantApiException($code): $message';
}

class AssistantRepository {
  AssistantRepository({
    http.Client? httpClient,
    AssistantAccessTokenProvider? accessTokenProvider,
    String? edgeApiUrl,
  }) : _httpClient = httpClient ?? _sharedHttpClient,
       _accessTokenProvider =
           accessTokenProvider ??
           (() => Supabase.instance.client.auth.currentSession?.accessToken),
       _edgeApiUrl = edgeApiUrl ?? AppConfig.edgeApiUrl;

  static final http.Client _sharedHttpClient = http.Client();
  static const _timeout = Duration(seconds: 22);

  final http.Client _httpClient;
  final AssistantAccessTokenProvider _accessTokenProvider;
  final String _edgeApiUrl;

  Future<List<AssistantMessage>> history() async {
    final payload = _map(await _request('GET', 'assistant/history'));
    final rows = payload['data'];
    if (rows is! List<dynamic>) throw _invalidResponse('history');
    return rows
        .map((row) => AssistantMessage.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<AssistantReply> sendMessage({
    required String message,
    required double radiusKm,
    double? latitude,
    double? longitude,
  }) async {
    final payload = _map(
      await _request(
        'POST',
        'assistant/chat',
        body: {
          'message': message.trim(),
          'latitude': latitude,
          'longitude': longitude,
          'radius_km': radiusKm,
        },
      ),
    );
    final matchesJson = payload['event_matches'];
    if (matchesJson is! List<dynamic>) throw _invalidResponse('event matches');
    final matches = matchesJson
        .map((row) => AssistantEventMatch.fromJson(_map(row)))
        .toList(growable: false);
    final assistantMessage = AssistantMessage.fromJson(
      _map(payload['message']),
      eventMatches: matches,
    );
    return AssistantReply(message: assistantMessage, eventMatches: matches);
  }

  Future<void> clearHistory() => _request('DELETE', 'assistant/history');

  Future<AssistantEventDraft> draftEvent({
    required String prompt,
    required String locale,
  }) async {
    final payload = _map(
      await _request(
        'POST',
        'assistant/event-draft',
        body: {'prompt': prompt.trim(), 'locale': locale},
      ),
    );
    return AssistantEventDraft.fromJson(_map(payload['draft']));
  }

  Future<Object?> _request(String method, String path, {Object? body}) async {
    final token = _accessTokenProvider();
    if (token == null || token.isEmpty) {
      throw const AssistantApiException(
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
      'DELETE' => _httpClient.delete(uri, headers: headers),
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
      throw AssistantApiException(
        statusCode: response.statusCode,
        code: details['code'] is String
            ? details['code'] as String
            : 'assistant_request_failed',
        message: details['message'] is String
            ? details['message'] as String
            : 'Gather Guide could not answer right now.',
      );
    }
    return payload;
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw _invalidResponse('data');
  }

  AssistantApiException _invalidResponse(String value) => AssistantApiException(
    statusCode: 502,
    code: 'invalid_edge_response',
    message: 'Gather Guide returned invalid $value.',
  );
}
