import 'dart:convert';

import 'package:gather2gether/config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class PushDeviceRepository {
  PushDeviceRepository({
    SupabaseClient? client,
    http.Client? httpClient,
    String? edgeApiUrl,
    String? Function()? accessTokenProvider,
  }) : _client = client,
       _http = httpClient ?? http.Client(),
       _edgeApiUrl = edgeApiUrl ?? AppConfig.edgeApiUrl,
       _accessTokenProvider = accessTokenProvider;

  final SupabaseClient? _client;
  final http.Client _http;
  final String _edgeApiUrl;
  final String? Function()? _accessTokenProvider;

  Future<void> register({
    required String token,
    required String platform,
    required String locale,
  }) async {
    await _request('PUT', {
      'token': token,
      'platform': platform,
      'locale': locale,
    });
  }

  Future<void> unregister(String token) => _request('DELETE', {'token': token});

  Future<void> _request(String method, Map<String, Object?> body) async {
    final accessToken =
        _accessTokenProvider?.call() ??
        _client?.auth.currentSession?.accessToken ??
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const PushDeviceException('Sign in is required.');
    }
    final base = _edgeApiUrl.endsWith('/')
        ? _edgeApiUrl.substring(0, _edgeApiUrl.length - 1)
        : _edgeApiUrl;
    final request = http.Request(method, Uri.parse('$base/push/devices'))
      ..headers.addAll({
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode(body);
    final streamed = await _http.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    var message = 'Notification setup is temporarily unavailable.';
    try {
      final payload = jsonDecode(response.body);
      final error = payload is Map<String, dynamic> ? payload['error'] : null;
      if (error is Map<String, dynamic> && error['message'] is String) {
        message = error['message'] as String;
      }
    } catch (_) {
      // Keep a safe, user-facing fallback for non-JSON gateway failures.
    }
    throw PushDeviceException(message);
  }
}

class PushDeviceException implements Exception {
  const PushDeviceException(this.message);

  final String message;

  @override
  String toString() => message;
}
