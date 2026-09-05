import 'dart:async';
import 'dart:convert';

import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/features/events/data/event_offline_cache.dart';
import 'package:gather2gether/features/events/domain/event_filters.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/domain/event_lifecycle.dart';
import 'package:gather2gether/features/events/domain/event_operations.dart';
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
    this.status = 'published',
    this.visibility = 'public',
    this.repeatInterval = 'none',
    this.repeatCount = 1,
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
  final String status;
  final String visibility;
  final String repeatInterval;
  final int repeatCount;

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
    'status': status,
    'visibility': visibility,
    'repeat_interval': repeatInterval,
    'repeat_count': repeatCount,
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
    EventOfflineCache? offlineCache,
  }) : _httpClient = httpClient ?? _sharedHttpClient,
       _accessTokenProvider =
           accessTokenProvider ??
           (() => Supabase.instance.client.auth.currentSession?.accessToken),
       _edgeApiUrl = edgeApiUrl ?? AppConfig.edgeApiUrl,
       _offlineCache = offlineCache ?? EventOfflineCache();

  static final http.Client _sharedHttpClient = http.Client();
  static const _timeout = Duration(seconds: 20);

  final http.Client _httpClient;
  final AccessTokenProvider _accessTokenProvider;
  final String _edgeApiUrl;
  final EventOfflineCache _offlineCache;
  bool _lastReadWasOffline = false;

  bool get lastReadWasOffline => _lastReadWasOffline;

  Future<List<EventSummary>> nearbyEvents({
    required double latitude,
    required double longitude,
    required double radiusKm,
    String? interest,
    EventDiscoveryFilters filters = const EventDiscoveryFilters(),
  }) async {
    final normalizedInterest = interest?.trim() ?? '';
    final dateRange = filters.dateRange(DateTime.now());
    final query = <String, String>{
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
      'beginner_friendly_only': '${filters.beginnerFriendlyOnly}',
      'wheelchair_accessible_only': '${filters.wheelchairAccessibleOnly}',
      'event_setting': filters.eventSetting,
      if (filters.eventLanguage.trim().isNotEmpty)
        'event_language': filters.eventLanguage.trim(),
      'age_guidance': filters.ageGuidance,
      'timezone_offset_minutes': '${DateTime.now().timeZoneOffset.inMinutes}',
    };
    return _withOfflineList('nearby', () async {
      final payload = await _request('GET', 'events/nearby', query: query);
      return _eventList(payload);
    });
  }

  Future<EventSummary> eventDetails(
    String eventId, {
    bool viaInvite = false,
  }) async {
    final scope = 'event_$eventId';
    try {
      final payload = await _request(
        'GET',
        'events/$eventId',
        query: {if (viaInvite) 'invite': '1'},
      );
      final event = EventSummary.fromJson(_map(_map(payload)['data']));
      _lastReadWasOffline = false;
      await _cacheEvents(scope, [event]);
      return event;
    } catch (error) {
      if (!_canUseOfflineFallback(error)) rethrow;
      final cached = await _readCachedEvents(scope);
      if (cached != null && cached.isNotEmpty) {
        _lastReadWasOffline = true;
        return cached.first;
      }
      rethrow;
    }
  }

  Future<List<EventSummary>> myEvents(String filter) async {
    return _withOfflineList('mine_$filter', () async {
      final payload = await _request(
        'GET',
        'events/mine',
        query: {'filter': filter},
      );
      return _eventList(payload);
    });
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

  Future<int> updateEventSeries(
    String eventId,
    String scope,
    CreateEventInput input,
  ) async {
    final payload = await _request(
      'PUT',
      'events/$eventId/series',
      body: {...input.toApiJson(), 'scope': scope},
    );
    return (_map(payload)['updated_count'] as num).toInt();
  }

  Future<EventQualityReview> reviewEventQuality(CreateEventInput input) async {
    final event = input.toApiJson();
    final payload = await _request(
      'POST',
      'assistant/event-quality',
      body: {
        'title': event['title'],
        'description': event['description'],
        'category': event['category'],
        'venue_name': event['venue_name'],
        'address': event['address'],
        'start_at': event['start_at'],
        'end_at': event['end_at'],
        'max_participants': event['max_participants'],
        'what_to_bring': event['what_to_bring'],
      },
    );
    return EventQualityReview.fromJson(_map(_map(payload)['quality']));
  }

  Future<NaturalEventFilters> naturalEventFilters(String query) async {
    final payload = await _request(
      'POST',
      'assistant/event-filters',
      body: {'query': query.trim(), 'locale': 'en'},
    );
    return NaturalEventFilters.fromJson(_map(_map(payload)['filters']));
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

  Future<EventDiscussionSummary> summarizeDiscussion(String eventId) async {
    final payload = await _request(
      'POST',
      'events/$eventId/discussion-summary',
    );
    return EventDiscussionSummary.fromJson(_map(payload));
  }

  Future<DiscussionChanges> discussionChanges(String eventId) async {
    final payload = await _request(
      'POST',
      'events/$eventId/discussion-changes',
    );
    return DiscussionChanges.fromJson(_map(payload));
  }

  Future<void> markDiscussionSeen(String eventId) =>
      _request('PUT', 'events/$eventId/discussion/seen');

  Future<String> translateEvent(String eventId, String targetLanguage) async {
    final payload = await _request(
      'POST',
      'events/$eventId/translation',
      body: {'target_language': targetLanguage.trim()},
    );
    final translation = _map(payload)['translation'];
    if (translation is! String || translation.trim().isEmpty) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned an invalid translation.',
      );
    }
    return translation;
  }

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
        'beginner_friendly_only': filters.beginnerFriendlyOnly,
        'wheelchair_accessible_only': filters.wheelchairAccessibleOnly,
        'event_setting': filters.eventSetting,
        'event_language': filters.eventLanguage.trim(),
        'age_guidance': filters.ageGuidance,
        'alerts_enabled': true,
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

  Future<void> updateSavedSearch({
    required SavedEventSearch search,
    String? name,
    String? interest,
    double? radiusKm,
    EventDiscoveryFilters? filters,
    bool? alertsEnabled,
  }) async {
    final updatedFilters = filters ?? search.filters;
    await _request(
      'PUT',
      'event-searches/${search.id}',
      body: {
        'name': (name ?? search.name).trim(),
        'interest': (interest ?? search.interest).trim(),
        'radius_km': radiusKm ?? search.radiusKm,
        'category': updatedFilters.category,
        'date_filter': updatedFilters.dateFilter,
        'time_filter': updatedFilters.timeFilter,
        'timezone_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        'spots_only': updatedFilters.spotsOnly,
        'following_only': updatedFilters.followingOnly,
        'beginner_friendly_only': updatedFilters.beginnerFriendlyOnly,
        'wheelchair_accessible_only': updatedFilters.wheelchairAccessibleOnly,
        'event_setting': updatedFilters.eventSetting,
        'event_language': updatedFilters.eventLanguage.trim(),
        'age_guidance': updatedFilters.ageGuidance,
        'alerts_enabled': alertsEnabled ?? search.alertsEnabled,
      },
    );
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

  Future<List<EventCohost>> cohosts(String eventId) async {
    final payload = await _request('GET', 'events/$eventId/cohosts');
    final rows = _map(payload)['data'];
    if (rows is! List<dynamic>) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned invalid co-host data.',
      );
    }
    return rows
        .map((row) => EventCohost.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<void> setCohost(String eventId, String username, bool enabled) =>
      _request(
        enabled ? 'PUT' : 'DELETE',
        'events/$eventId/cohosts',
        body: {'username': username.trim()},
      );

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

  Future<EventHostDashboard> hostDashboard(String eventId) async {
    final payload = await _request('GET', 'events/$eventId/host-dashboard');
    return EventHostDashboard.fromJson(_map(_map(payload)['data']));
  }

  Future<List<EventHostAttendee>> hostAttendees(String eventId) async {
    final payload = await _request('GET', 'events/$eventId/host-attendees');
    final rows = _map(payload)['data'];
    if (rows is! List<dynamic>) {
      throw const EdgeApiException(
        statusCode: 502,
        code: 'invalid_edge_response',
        message: 'The edge API returned invalid host attendee data.',
      );
    }
    return rows
        .map((row) => EventHostAttendee.fromJson(_map(row)))
        .toList(growable: false);
  }

  Future<void> setAttendance(String eventId, String profileId, String status) =>
      _request(
        'PUT',
        'events/$eventId/attendance/$profileId',
        body: {'status': status},
      );

  Future<void> hideEventRecommendation(String eventId) => _request(
    'POST',
    'recommendations/hide',
    body: {'content_kind': 'event', 'content_id': eventId},
  );

  List<EventSummary> _eventList(Object? payload) {
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

  Future<List<EventSummary>> _withOfflineList(
    String scope,
    Future<List<EventSummary>> Function() fetchLive,
  ) async {
    try {
      final events = await fetchLive();
      _lastReadWasOffline = false;
      await _cacheEvents(scope, events);
      return events;
    } catch (error) {
      if (!_canUseOfflineFallback(error)) rethrow;
      final cached = await _readCachedEvents(scope);
      if (cached != null) {
        _lastReadWasOffline = true;
        return cached;
      }
      rethrow;
    }
  }

  Future<void> _cacheEvents(String scope, List<EventSummary> events) async {
    final userId = _userIdFromAccessToken();
    if (userId != null) await _offlineCache.writeEvents(userId, scope, events);
  }

  Future<List<EventSummary>?> _readCachedEvents(String scope) async {
    final userId = _userIdFromAccessToken();
    return userId == null ? null : _offlineCache.readEvents(userId, scope);
  }

  bool _canUseOfflineFallback(Object error) =>
      error is TimeoutException ||
      error is http.ClientException ||
      (error is EdgeApiException && error.statusCode >= 500);

  String? _userIdFromAccessToken() {
    final token = _accessTokenProvider();
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final subject = payload is Map ? payload['sub'] : null;
      return subject is String && subject.isNotEmpty ? subject : null;
    } catch (_) {
      return null;
    }
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
