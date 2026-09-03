import 'dart:convert';

import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/features/places/domain/place_suggestion.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PlaceAccessTokenProvider = String? Function();

class PlaceSearchException implements Exception {
  const PlaceSearchException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'PlaceSearchException($code): $message';
}

class PlaceRepository {
  PlaceRepository({
    http.Client? httpClient,
    PlaceAccessTokenProvider? accessTokenProvider,
    String? edgeApiUrl,
  }) : _httpClient = httpClient ?? _sharedHttpClient,
       _accessTokenProvider =
           accessTokenProvider ??
           (() => Supabase.instance.client.auth.currentSession?.accessToken),
       _edgeApiUrl = edgeApiUrl ?? AppConfig.edgeApiUrl;

  static final http.Client _sharedHttpClient = http.Client();
  static const _timeout = Duration(seconds: 12);

  final http.Client _httpClient;
  final PlaceAccessTokenProvider _accessTokenProvider;
  final String _edgeApiUrl;

  Future<List<PlaceSuggestion>> autocomplete({
    required String text,
    double? latitude,
    double? longitude,
    String? language,
  }) async {
    final query = text.trim();
    if (query.length < 3) return const [];
    if ((latitude == null) != (longitude == null)) {
      throw ArgumentError('Place search bias requires both coordinates.');
    }

    final token = _accessTokenProvider();
    if (token == null || token.isEmpty) {
      throw const PlaceSearchException(
        statusCode: 401,
        code: 'authentication_required',
        message: 'Sign in is required.',
      );
    }

    final base = _edgeApiUrl.endsWith('/')
        ? _edgeApiUrl.substring(0, _edgeApiUrl.length - 1)
        : _edgeApiUrl;
    final normalizedLanguage = language?.trim().toLowerCase();
    final uri = Uri.parse('$base/places/autocomplete').replace(
      queryParameters: {
        'text': query,
        if (latitude != null) 'latitude': '$latitude',
        if (longitude != null) 'longitude': '$longitude',
        if (normalizedLanguage != null &&
            RegExp(r'^[a-z]{2}$').hasMatch(normalizedLanguage))
          'language': normalizedLanguage,
      },
    );

    final response = await _httpClient
        .get(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(_timeout);

    Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw PlaceSearchException(
        statusCode: response.statusCode,
        code: 'invalid_edge_response',
        message: 'The address service returned invalid data.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = payload is Map<String, dynamic> ? payload['error'] : null;
      final details = error is Map<String, dynamic>
          ? error
          : const <String, dynamic>{};
      throw PlaceSearchException(
        statusCode: response.statusCode,
        code: details['code'] is String
            ? details['code'] as String
            : 'place_search_failed',
        message: details['message'] is String
            ? details['message'] as String
            : 'Address suggestions are temporarily unavailable.',
      );
    }

    final root = _map(payload);
    final rows = root['data'];
    if (rows is! List<dynamic>) {
      throw const PlaceSearchException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The address service returned invalid data.',
      );
    }
    try {
      return rows
          .map((row) => PlaceSuggestion.fromJson(_map(row)))
          .toList(growable: false);
    } on FormatException {
      throw const PlaceSearchException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The address service returned invalid data.',
      );
    }
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const PlaceSearchException(
      statusCode: 502,
      code: 'invalid_edge_response',
      message: 'The address service returned invalid data.',
    );
  }
}
