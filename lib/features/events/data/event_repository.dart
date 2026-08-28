import 'dart:convert';

import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AccessTokenProvider = String? Function();

class CreateEventInput {
  const CreateEventInput({
    required this.title,
    required this.description,
    required this.category,
    required this.venueName,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.startAt,
    required this.endAt,
    required this.maxParticipants,
  });

  final String title;
  final String description;
  final String category;
  final String venueName;
  final String address;
  final double latitude;
  final double longitude;
  final DateTime startAt;
  final DateTime endAt;
  final int maxParticipants;

  Map<String, Object> toApiJson() => {
    'title': title.trim(),
    'description': description.trim(),
    'category': category,
    'venue_name': venueName.trim(),
    'address': address.trim(),
    'latitude': latitude,
    'longitude': longitude,
    'start_at': startAt.toUtc().toIso8601String(),
    'end_at': endAt.toUtc().toIso8601String(),
    'max_participants': maxParticipants,
  };
}

class EdgeApiException implements Exception {
  const EdgeApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'EdgeApiException($code): $message';
}

class EventRepository {
  EventRepository({
    http.Client? httpClient,
    AccessTokenProvider? accessTokenProvider,
    String? edgeApiUrl,
  }) : _httpClient = httpClient ?? _sharedHttpClient,
       _accessTokenProvider =
           accessTokenProvider ??
           (() => Supabase.instance.client.auth.currentSession?.accessToken),
       _edgeApiUrl = edgeApiUrl ?? AppConfig.edgeApiUrl;

  static final http.Client _sharedHttpClient = http.Client();
  static const _timeout = Duration(seconds: 20);

  final http.Client _httpClient;
  final AccessTokenProvider _accessTokenProvider;
  final String _edgeApiUrl;

  Future<List<EventSummary>> nearbyEvents({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) async {
    final payload = await _request(
      'GET',
      'events/nearby',
      query: {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'radius_km': '$radiusKm',
      },
    );
    final rows = _map(payload)['data'];
    if (rows is! List<dynamic>) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned invalid event data.',
      );
    }
    return rows
        .map((row) => EventSummary.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<EventSummary> eventDetails(String eventId) async {
    final payload = await _request('GET', 'events/$eventId');
    return EventSummary.fromJson(_map(_map(payload)['data']));
  }

  Future<String> createEvent(CreateEventInput input) async {
    final payload = await _request('POST', 'events', body: input.toApiJson());
    final eventId = _map(payload)['id'];
    if (eventId is! String || eventId.isEmpty) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned an invalid event identifier.',
      );
    }
    return eventId;
  }

  Future<void> setRsvp(String eventId, String status) async {
    await _request('PUT', 'events/$eventId/rsvp', body: {'status': status});
  }

  Future<void> reportEvent({
    required String eventId,
    required String reason,
  }) async {
    await _request('POST', 'events/$eventId/report', body: {'reason': reason});
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final token = _accessTokenProvider();
    if (token == null || token.isEmpty) {
      throw const EdgeApiException(
        statusCode: 401,
        code: 'authentication_required',
        message: 'Sign in is required.',
      );
    }

    final base = _edgeApiUrl.endsWith('/')
        ? _edgeApiUrl.substring(0, _edgeApiUrl.length - 1)
        : _edgeApiUrl;
    var uri = Uri.parse('$base/$path');
    if (query != null) uri = uri.replace(queryParameters: query);
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };

    final request = switch (method) {
      'GET' => _httpClient.get(uri, headers: headers),
      'POST' => _httpClient.post(uri, headers: headers, body: jsonEncode(body)),
      'PUT' => _httpClient.put(uri, headers: headers, body: jsonEncode(body)),
      _ => throw ArgumentError.value(
        method,
        'method',
        'Unsupported HTTP method',
      ),
    };

    final completed = await request.timeout(_timeout);
    Object? payload;
    if (completed.body.isNotEmpty) {
      try {
        payload = jsonDecode(completed.body);
      } on FormatException {
        throw EdgeApiException(
          statusCode: completed.statusCode,
          code: 'invalid_edge_response',
          message: 'The edge API returned invalid JSON.',
        );
      }
    }

    if (completed.statusCode < 200 || completed.statusCode >= 300) {
      final error = payload is Map<String, dynamic> ? payload['error'] : null;
      final details = error is Map<String, dynamic>
          ? error
          : const <String, dynamic>{};
      throw EdgeApiException(
        statusCode: completed.statusCode,
        code: details['code'] is String
            ? details['code'] as String
            : 'edge_request_failed',
        message: details['message'] is String
            ? details['message'] as String
            : 'The edge API request failed.',
      );
    }
    return payload;
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const EdgeApiException(
      statusCode: 502,
      code: 'invalid_edge_response',
      message: 'The edge API returned invalid data.',
    );
  }
}
