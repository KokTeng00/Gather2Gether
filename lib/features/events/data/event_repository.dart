import 'dart:convert';

import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/features/events/domain/event_filters.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/domain/event_lifecycle.dart';
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
    this.beginnerFriendly = false,
    this.wheelchairAccessible = false,
    this.eventSetting = 'unspecified',
    this.eventLanguage = '',
    this.ageGuidance = 'all_ages',
    this.whatToBring = '',
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
  final bool beginnerFriendly;
  final bool wheelchairAccessible;
  final String eventSetting;
  final String eventLanguage;
  final String ageGuidance;
  final String whatToBring;

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
    'beginner_friendly': beginnerFriendly,
    'wheelchair_accessible': wheelchairAccessible,
    'event_setting': eventSetting,
    'event_language': eventLanguage.trim(),
    'age_guidance': ageGuidance,
    'what_to_bring': whatToBring.trim(),
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
    String? interest,
    EventDiscoveryFilters filters = const EventDiscoveryFilters(),
  }) async {
    final normalizedInterest = interest?.trim() ?? '';
    final dateRange = filters.dateRange(DateTime.now());
    final payload = await _request(
      'GET',
      'events/nearby',
      query: {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'radius_km': '$radiusKm',
        if (normalizedInterest.isNotEmpty) 'interest': normalizedInterest,
        if (filters.category != null) 'category': filters.category!,
        if (dateRange.startFrom != null)
          'start_from': dateRange.startFrom!.toUtc().toIso8601String(),
        if (dateRange.startBefore != null)
          'start_before': dateRange.startBefore!.toUtc().toIso8601String(),
        'time_filter': filters.timeFilter,
        'spots_only': '${filters.spotsOnly}',
        'following_only': '${filters.followingOnly}',
        'timezone_offset_minutes': '${DateTime.now().timeZoneOffset.inMinutes}',
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

  Future<List<EventSummary>> myEvents(String filter) async {
    final payload = await _request(
      'GET',
      'events/mine',
      query: {'filter': filter},
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

  Future<String> updateRsvp(String eventId, String status) async {
    final payload = await _request(
      'PUT',
      'events/$eventId/rsvp',
      body: {'status': status},
    );
    return (_map(payload)['status'] as String?) ?? status;
  }

  Future<void> updateEvent(String eventId, CreateEventInput input) async {
    await _request('PUT', 'events/$eventId', body: input.toApiJson());
  }

  Future<void> cancelEvent(String eventId) =>
      _request('POST', 'events/$eventId/cancel');

  Future<bool> setSaved(String eventId, bool saved) async {
    final payload = await _request(
      saved ? 'PUT' : 'DELETE',
      'events/$eventId/save',
    );
    return _map(payload)['saved'] == true;
  }

  Future<DateTime> setReminder(String eventId, DateTime remindAt) async {
    final payload = await _request(
      'PUT',
      'events/$eventId/reminder',
      body: {'remind_at': remindAt.toUtc().toIso8601String()},
    );
    return DateTime.parse(_map(payload)['remind_at'] as String).toLocal();
  }

  Future<void> clearReminder(String eventId) =>
      _request('DELETE', 'events/$eventId/reminder');

  Future<List<EventAnnouncement>> announcements(String eventId) async {
    final payload = await _request('GET', 'events/$eventId/announcements');
    final rows = _map(payload)['data'];
    if (rows is! List<dynamic>) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned invalid announcement data.',
      );
    }
    return rows
        .map((row) => EventAnnouncement.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<void> createAnnouncement(String eventId, String body) => _request(
    'POST',
    'events/$eventId/announcements',
    body: {'body': body.trim()},
  );

  Future<List<EventDiscussionMessage>> eventDiscussion(String eventId) async {
    final payload = await _request('GET', 'events/$eventId/discussion');
    final rows = _map(payload)['data'];
    if (rows is! List<dynamic>) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned invalid discussion data.',
      );
    }
    return rows
        .map((row) => EventDiscussionMessage.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<void> createDiscussionMessage(String eventId, String body) => _request(
    'POST',
    'events/$eventId/discussion',
    body: {'body': body.trim()},
  );

  Future<void> reportDiscussionMessage(
    String eventId,
    String messageId,
    String reason,
  ) => _request(
    'POST',
    'events/$eventId/discussion/$messageId/report',
    body: {'reason': reason},
  );

  Future<void> submitFeedback({
    required String eventId,
    required bool attended,
    int? rating,
    String comment = '',
  }) => _request(
    'POST',
    'events/$eventId/feedback',
    body: {'attended': attended, 'rating': rating, 'comment': comment.trim()},
  );

  Future<List<EventFeedbackEntry>> eventFeedback(String eventId) async {
    final payload = await _request('GET', 'events/$eventId/feedback');
    final rows = _map(payload)['data'];
    if (rows is! List<dynamic>) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned invalid feedback data.',
      );
    }
    return rows
        .map((row) => EventFeedbackEntry.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<List<MemberNotification>> notifications() async {
    final payload = await _request('GET', 'notifications');
    final rows = _map(payload)['data'];
    if (rows is! List<dynamic>) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned invalid notification data.',
      );
    }
    return rows
        .map((row) => MemberNotification.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<void> markNotificationRead(String notificationId) =>
      _request('PUT', 'notifications/$notificationId/read');

  Future<void> markAllNotificationsRead() =>
      _request('PUT', 'notifications/read-all');

  Future<void> reportEvent({
    required String eventId,
    required String reason,
  }) async {
    await _request('POST', 'events/$eventId/report', body: {'reason': reason});
  }

  Future<List<SavedEventSearch>> savedSearches() async {
    final payload = await _request('GET', 'event-searches');
    final rows = _map(payload)['data'];
    if (rows is! List<dynamic>) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned invalid saved search data.',
      );
    }
    return rows
        .map((row) => SavedEventSearch.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<String> saveSearch({
    required String name,
    required String interest,
    required double radiusKm,
    required EventDiscoveryFilters filters,
  }) async {
    final payload = await _request(
      'POST',
      'event-searches',
      body: {
        'name': name.trim(),
        'interest': interest.trim(),
        'radius_km': radiusKm,
        'category': filters.category,
        'date_filter': filters.dateFilter,
        'time_filter': filters.timeFilter,
        'timezone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        'spots_only': filters.spotsOnly,
        'following_only': filters.followingOnly,
      },
    );
    final id = _map(payload)['id'];
    if (id is! String || id.isEmpty) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned an invalid saved search identifier.',
      );
    }
    return id;
  }

  Future<void> deleteSavedSearch(String searchId) =>
      _request('DELETE', 'event-searches/$searchId');

  Future<List<EventAttendee>> attendees(String eventId) async {
    final payload = await _request('GET', 'events/$eventId/attendees');
    final rows = _map(payload)['data'];
    if (rows is! List<dynamic>) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned invalid attendee data.',
      );
    }
    return rows
        .map((row) => EventAttendee.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<bool> setAttendeeVisibility(String eventId, bool visible) async {
    final payload = await _request(
      'PUT',
      'events/$eventId/attendees/visibility',
      body: {'visible': visible},
    );
    return _map(payload)['visible'] == true;
  }

  Future<bool> setDiscussionNotifications(String eventId, bool enabled) async {
    final payload = await _request(
      'PUT',
      'events/$eventId/discussion-notifications',
      body: {'enabled': enabled},
    );
    return _map(payload)['enabled'] == true;
  }

  Future<DateTime> requestRsvpReconfirmation(String eventId) async {
    final payload = await _request(
      'POST',
      'events/$eventId/reconfirmation/request',
    );
    return DateTime.parse(_map(payload)['deadline_at'] as String).toLocal();
  }

  Future<DateTime> confirmRsvp(String eventId) async {
    final payload = await _request(
      'POST',
      'events/$eventId/reconfirmation/confirm',
    );
    return DateTime.parse(_map(payload)['confirmed_at'] as String).toLocal();
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
      'DELETE' => _httpClient.delete(uri, headers: headers),
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
