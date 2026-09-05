import 'dart:convert';

import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/profile/domain/profile_stats.dart';
import 'package:gather2gether/features/profile/domain/profile_connection.dart';
import 'package:gather2gether/features/profile/domain/public_profile.dart';
import 'package:gather2gether/features/profile/domain/member_controls.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ProfileAccessTokenProvider = String? Function();

class ProfileApiException implements Exception {
  const ProfileApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ProfileApiException($code): $message';
}

class ProfileRepository {
  ProfileRepository({
    SupabaseClient? client,
    http.Client? httpClient,
    ProfileAccessTokenProvider? accessTokenProvider,
    String? edgeApiUrl,
  }) : _clientOverride = client,
       _httpClientOverride = httpClient,
       _accessTokenProviderOverride = accessTokenProvider,
       _edgeApiUrl = edgeApiUrl ?? AppConfig.edgeApiUrl;

  static final http.Client _sharedHttpClient = http.Client();
  static const _timeout = Duration(seconds: 20);
  static const _profileFields =
      'display_name, username, bio, city, preferred_radius_km, '
      'approximate_latitude, approximate_longitude, assistant_enabled, '
      'show_past_events_public, avatar_image_key, username_changed_at, updated_at, '
      'interests, accessibility_preferences, onboarding_completed_at';
  static const _preOperationsProfileFields =
      'display_name, username, bio, city, preferred_radius_km, '
      'approximate_latitude, approximate_longitude, assistant_enabled, '
      'show_past_events_public, avatar_image_key, username_changed_at, updated_at';
  static const _prePastVisibilityProfileFields =
      'display_name, username, bio, city, preferred_radius_km, '
      'approximate_latitude, approximate_longitude, assistant_enabled, '
      'avatar_image_key, username_changed_at, updated_at';
  static const _legacyProfileFields =
      'display_name, username, bio, city, preferred_radius_km, '
      'approximate_latitude, approximate_longitude, assistant_enabled, '
      'avatar_image_key, updated_at';

  final SupabaseClient? _clientOverride;
  final http.Client? _httpClientOverride;
  final ProfileAccessTokenProvider? _accessTokenProviderOverride;
  final String _edgeApiUrl;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;
  http.Client get _httpClient => _httpClientOverride ?? _sharedHttpClient;
  String? get _accessToken {
    final provider = _accessTokenProviderOverride;
    return provider == null
        ? _client.auth.currentSession?.accessToken
        : provider();
  }

  Future<UserProfile> fetchOwnProfile() async {
    final userId = _requireUserId();
    try {
      final response = await _fetchOwnProfileRow(userId, _profileFields);
      return UserProfile.fromJson(response);
    } on PostgrestException catch (error) {
      if (_isMissingOperationsColumn(error)) {
        final response = await _fetchOwnProfileRow(
          userId,
          _preOperationsProfileFields,
        );
        return UserProfile.fromJson(response);
      }
      // Keep read-only profile screens available during the short deployment
      // window between shipping the app and applying profile migrations.
      if (_isMissingPastVisibilityColumn(error)) {
        try {
          final response = await _fetchOwnProfileRow(
            userId,
            _prePastVisibilityProfileFields,
          );
          return UserProfile.fromJson(response);
        } on PostgrestException catch (legacyError) {
          if (!_isMissingCooldownColumn(legacyError)) rethrow;
          final response = await _fetchOwnProfileRow(
            userId,
            _legacyProfileFields,
          );
          return UserProfile.fromJson(response);
        }
      }
      // Username writes never use this older fallback.
      if (!_isMissingCooldownColumn(error)) rethrow;
      final response = await _fetchOwnProfileRow(userId, _legacyProfileFields);
      return UserProfile.fromJson(response);
    }
  }

  Future<ProfileStats> fetchStats() async {
    _requireUserId();
    final response = await _client.rpc('get_own_profile_stats');
    final row = switch (response) {
      Map<String, dynamic> value => value,
      Map value => Map<String, dynamic>.from(value),
      List value when value.isNotEmpty && value.first is Map =>
        Map<String, dynamic>.from(value.first as Map),
      _ => throw const FormatException('Invalid profile stats response.'),
    };
    return ProfileStats.fromJson(row);
  }

  Future<UserProfile> updateIdentity({
    required String displayName,
    required String username,
    required String bio,
    required String city,
  }) async {
    _requireUserId();
    UserProfile? currentProfile;
    try {
      currentProfile = await fetchOwnProfile();
    } catch (_) {}
    try {
      final response = await _client.rpc(
        'update_own_profile_identity',
        params: {
          'p_display_name': displayName.trim(),
          'p_username': username.trim().toLowerCase(),
          'p_bio': bio.trim(),
          'p_city': city.trim().isEmpty ? null : city.trim(),
        },
      );
      final updated = UserProfile.fromJson(_singleRow(response));
      return currentProfile == null
          ? updated
          : updated.copyWith(
              showPastEventsPublic: currentProfile.showPastEventsPublic,
              interests: currentProfile.interests,
              accessibilityPreferences: currentProfile.accessibilityPreferences,
              onboardingCompletedAt: currentProfile.onboardingCompletedAt,
            );
    } on PostgrestException catch (error) {
      throw switch (error.message) {
        'profile_username_cooldown' => const ProfileApiException(
          statusCode: 409,
          code: 'username_change_cooldown',
          message: 'You can change your username once every three months.',
        ),
        'profile_username_taken' => const ProfileApiException(
          statusCode: 409,
          code: 'username_taken',
          message: 'That username is already taken.',
        ),
        'profile_identity_validation' => const ProfileApiException(
          statusCode: 400,
          code: 'profile_validation',
          message: 'Check your public profile details and try again.',
        ),
        _ => error,
      };
    }
  }

  Future<UserProfile> updateDiscoveryPreferences({
    required double preferredRadiusKm,
    double? latitude,
    double? longitude,
  }) async {
    final userId = _requireUserId();
    final values = <String, Object?>{'preferred_radius_km': preferredRadiusKm};
    if (latitude != null && longitude != null) {
      values['approximate_latitude'] = _roundLocation(latitude);
      values['approximate_longitude'] = _roundLocation(longitude);
    }
    final response = await _client
        .from('profiles')
        .update(values)
        .eq('id', userId)
        .select(_profileFields)
        .single();
    return UserProfile.fromJson(response);
  }

  /// Retained for callers that still save identity and discovery together.
  Future<void> updateProfile({
    required String displayName,
    required String city,
    required double preferredRadiusKm,
    double? latitude,
    double? longitude,
  }) async {
    final current = await fetchOwnProfile();
    await updateIdentity(
      displayName: displayName,
      username: current.username,
      bio: current.bio,
      city: city,
    );
    await updateDiscoveryPreferences(
      preferredRadiusKm: preferredRadiusKm,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<void> updateAssistantEnabled(bool enabled) async {
    final userId = _requireUserId();
    await _client
        .from('profiles')
        .update({'assistant_enabled': enabled})
        .eq('id', userId);
  }

  Future<UserProfile> updatePastEventsVisibility(bool isPublic) async {
    final userId = _requireUserId();
    final response = await _client
        .from('profiles')
        .update({'show_past_events_public': isPublic})
        .eq('id', userId)
        .select(_profileFields)
        .single();
    return UserProfile.fromJson(response);
  }

  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _requireUserId();
    final email = _client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      throw StateError('An email address is required to change the password.');
    }
    await _client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    await _client.auth.updateUser(
      UserAttributes(password: newPassword, currentPassword: currentPassword),
    );
  }

  Future<void> uploadAvatar(PreparedImage image) async {
    if (image.bytes.isEmpty || image.bytes.length > PreparedImage.maxBytes) {
      throw ArgumentError.value(
        image.bytes.length,
        'image',
        'Avatar must be a non-empty JPEG no larger than 5 MB.',
      );
    }
    await _avatarRequest(
      'POST',
      body: image.bytes,
      contentType: PreparedImage.jpegContentType,
    );
  }

  Future<void> deleteAvatar() => _avatarRequest('DELETE');

  Future<PublicProfile> fetchPublicProfile(String profileId) async {
    final payload = _responseMap(
      await _edgeRequest('GET', 'profiles/${Uri.encodeComponent(profileId)}'),
    );
    return PublicProfile.fromJson(_responseMap(payload['data']));
  }

  Future<List<EventSummary>> fetchProfileEvents(
    String profileId,
    String filter,
  ) async {
    final payload = _responseMap(
      await _edgeRequest(
        'GET',
        'profiles/${Uri.encodeComponent(profileId)}/events'
            '?filter=${Uri.encodeQueryComponent(filter)}',
      ),
    );
    final rows = payload['data'];
    if (rows is! List<dynamic>) {
      throw const FormatException('Invalid profile event response.');
    }
    return rows
        .map((row) => EventSummary.fromJson(_responseMap(row)))
        .toList(growable: false);
  }

  Future<bool> setFollowing(String profileId, bool following) async {
    final payload = _responseMap(
      await _edgeRequest(
        following ? 'PUT' : 'DELETE',
        'profiles/${Uri.encodeComponent(profileId)}/follow',
      ),
    );
    return payload['following'] == true;
  }

  Future<ProfileConnectionPage> fetchConnections({
    String? profileId,
    required ProfileConnectionKind kind,
    String query = '',
    String? cursor,
  }) async {
    final parameters = <String, String>{
      if (query.trim().isNotEmpty) 'query': query.trim(),
      'cursor': ?cursor,
    };
    final path =
        'profiles/${Uri.encodeComponent(profileId ?? 'me')}/${kind.name}';
    final uri = Uri(
      path: path,
      queryParameters: parameters.isEmpty ? null : parameters,
    );
    final payload = _responseMap(await _edgeRequest('GET', uri.toString()));
    final rows = payload['data'];
    if (rows is! List) {
      throw const FormatException('Invalid member list response.');
    }
    return ProfileConnectionPage(
      members: rows
          .map((row) => ProfileConnection.fromJson(_responseMap(row)))
          .toList(growable: false),
      canSearch: payload['can_search'] == true,
      nextCursor: payload['next_cursor'] as String?,
    );
  }

  String connectionAvatarUrl(ProfileConnection member) {
    final base = _edgeApiUrl.endsWith('/')
        ? _edgeApiUrl.substring(0, _edgeApiUrl.length - 1)
        : _edgeApiUrl;
    return '$base/profiles/${Uri.encodeComponent(member.id)}/avatar?v=${Uri.encodeQueryComponent(member.avatarVersion ?? 'current')}';
  }

  Future<bool> setBlocked(String profileId, bool blocked) async {
    final payload = _responseMap(
      await _edgeRequest(
        blocked ? 'PUT' : 'DELETE',
        'profiles/${Uri.encodeComponent(profileId)}/block',
      ),
    );
    return payload['blocked'] == true;
  }

  Future<List<BlockedProfile>> blockedProfiles() async {
    final payload = _responseMap(await _edgeRequest('GET', 'blocks'));
    final rows = payload['data'];
    if (rows is! List<dynamic>) {
      throw const FormatException('Invalid blocked profiles response.');
    }
    return rows
        .map((row) => BlockedProfile.fromJson(_responseMap(row)))
        .toList(growable: false);
  }

  Future<void> completeOnboarding({
    required List<String> interests,
    required List<String> accessibilityPreferences,
    required double radiusKm,
    double? latitude,
    double? longitude,
  }) => _edgeRequest(
    'POST',
    'onboarding',
    body: {
      'interests': interests,
      'accessibility_preferences': accessibilityPreferences,
      'radius_km': radiusKm,
      'latitude': latitude,
      'longitude': longitude,
    },
  );

  Future<NotificationPreferences> notificationPreferences() async {
    final payload = _responseMap(
      await _edgeRequest('GET', 'notification-preferences'),
    );
    return NotificationPreferences.fromJson(_responseMap(payload['data']));
  }

  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) => _edgeRequest(
    'PUT',
    'notification-preferences',
    body: preferences
        .copyWith(
          timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
        )
        .toJson(),
  );

  Future<RecommendationPreferences> recommendationPreferences() async {
    final payload = _responseMap(
      await _edgeRequest('GET', 'recommendations/preferences'),
    );
    return RecommendationPreferences.fromJson(_responseMap(payload['data']));
  }

  Future<void> updateRecommendationPreferences({
    required bool enabled,
    required List<String> hiddenCategories,
  }) => _edgeRequest(
    'PUT',
    'recommendations/preferences',
    body: {'enabled': enabled, 'hidden_categories': hiddenCategories},
  );

  Future<void> resetRecommendationControls() =>
      _edgeRequest('DELETE', 'recommendations/preferences');

  Future<List<MemberReport>> ownReports() async {
    final payload = _responseMap(await _edgeRequest('GET', 'reports/mine'));
    final rows = payload['data'];
    if (rows is! List<dynamic>) {
      throw const FormatException('Invalid report status response.');
    }
    return rows
        .map((row) => MemberReport.fromJson(_responseMap(row)))
        .toList(growable: false);
  }

  Future<String> exportOwnData() async {
    final payload = _responseMap(await _edgeRequest('GET', 'account/export'));
    return const JsonEncoder.withIndent('  ').convert(payload['data']);
  }

  Future<bool> isModerator() async {
    final payload = _responseMap(
      await _edgeRequest('GET', 'moderation/status'),
    );
    return payload['moderator'] == true;
  }

  Future<Map<String, int>> moderationOverview() async {
    final payload = _responseMap(
      await _edgeRequest('GET', 'moderation/overview'),
    );
    final data = _responseMap(payload['data']);
    return data.map(
      (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
    );
  }

  Future<List<ModerationReport>> moderationReports({
    String status = 'open',
  }) async {
    final payload = _responseMap(
      await _edgeRequest(
        'GET',
        'moderation/reports?status=${Uri.encodeQueryComponent(status)}',
      ),
    );
    final rows = payload['data'];
    if (rows is! List<dynamic>) {
      throw const FormatException('Invalid moderation report response.');
    }
    return rows
        .map((row) => ModerationReport.fromJson(_responseMap(row)))
        .toList(growable: false);
  }

  Future<Map<String, ({String priority, String reason})>>
  triageReports() async {
    final payload = _responseMap(
      await _edgeRequest('POST', 'moderation/triage'),
    );
    final rows = payload['data'];
    if (rows is! List<dynamic>) {
      throw const FormatException('Invalid moderation triage response.');
    }
    return {
      for (final row in rows)
        if (row is Map && row['report_id'] is String)
          row['report_id'] as String: (
            priority: row['priority'] as String,
            reason: row['reason'] as String,
          ),
    };
  }

  Future<void> moderateReport({
    required String reportKind,
    required String reportId,
    required String action,
    String note = '',
  }) => _edgeRequest(
    'POST',
    'moderation/action',
    body: {
      'report_kind': reportKind,
      'report_id': reportId,
      'action': action,
      'note': note.trim(),
    },
  );

  Future<void> deleteAccount() async {
    await _edgeRequest('DELETE', 'account', body: {'confirmation': 'DELETE'});
    await _client.auth.signOut();
  }

  String publicAvatarUrl(PublicProfile profile) {
    final base = _edgeApiUrl.endsWith('/')
        ? _edgeApiUrl.substring(0, _edgeApiUrl.length - 1)
        : _edgeApiUrl;
    final version = Uri.encodeQueryComponent(
      profile.avatarVersion?.toUtc().toIso8601String() ?? 'current',
    );
    return '$base/profiles/${Uri.encodeComponent(profile.id)}/avatar?v=$version';
  }

  Map<String, String> publicMediaHeaders() {
    final token = _accessToken;
    return token == null || token.isEmpty
        ? const {}
        : {'Authorization': 'Bearer $token'};
  }

  Future<Object?> _edgeRequest(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      throw const ProfileApiException(
        statusCode: 401,
        code: 'authentication_required',
        message: 'Sign in is required.',
      );
    }
    final base = _edgeApiUrl.endsWith('/')
        ? _edgeApiUrl.substring(0, _edgeApiUrl.length - 1)
        : _edgeApiUrl;
    final request = http.Request(method, Uri.parse('$base/$path'))
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _httpClient.send(request).timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    Object? payload;
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(response.body);
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const FormatException('Invalid profile API response.');
        }
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return payload;
    final error = payload is Map<String, dynamic> ? payload['error'] : null;
    final details = error is Map<String, dynamic>
        ? error
        : const <String, dynamic>{};
    throw ProfileApiException(
      statusCode: response.statusCode,
      code: details['code'] is String
          ? details['code'] as String
          : 'profile_request_failed',
      message: details['message'] is String
          ? details['message'] as String
          : 'The profile request failed. Please try again.',
    );
  }

  Future<void> _avatarRequest(
    String method, {
    List<int>? body,
    String? contentType,
  }) async {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      throw const ProfileApiException(
        statusCode: 401,
        code: 'authentication_required',
        message: 'Sign in is required.',
      );
    }
    final base = _edgeApiUrl.endsWith('/')
        ? _edgeApiUrl.substring(0, _edgeApiUrl.length - 1)
        : _edgeApiUrl;
    final request = http.Request(method, Uri.parse('$base/profile/avatar'))
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Content-Type': ?contentType,
      });
    if (body != null) request.bodyBytes = body;
    final streamed = await _httpClient.send(request).timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    Object? payload;
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(response.body);
      } on FormatException {
        // The safe generic message below is used for non-JSON responses.
      }
    }
    final error = payload is Map<String, dynamic> ? payload['error'] : null;
    final details = error is Map<String, dynamic>
        ? error
        : const <String, dynamic>{};
    throw ProfileApiException(
      statusCode: response.statusCode,
      code: details['code'] is String
          ? details['code'] as String
          : 'profile_request_failed',
      message: details['message'] is String
          ? details['message'] as String
          : 'The profile request failed. Please try again.',
    );
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required.');
    return userId;
  }

  double _roundLocation(double value) => (value * 100).round() / 100;

  Future<Map<String, dynamic>> _fetchOwnProfileRow(
    String userId,
    String fields,
  ) {
    return _client.from('profiles').select(fields).eq('id', userId).single();
  }

  bool _isMissingCooldownColumn(PostgrestException error) {
    return error.code == '42703' ||
        error.message.toLowerCase().contains('username_changed_at');
  }

  bool _isMissingPastVisibilityColumn(PostgrestException error) {
    return error.message.toLowerCase().contains('show_past_events_public');
  }

  bool _isMissingOperationsColumn(PostgrestException error) {
    final message = error.message.toLowerCase();
    return message.contains('interests') ||
        message.contains('accessibility_preferences') ||
        message.contains('onboarding_completed_at');
  }

  Map<String, dynamic> _singleRow(Object? response) {
    return switch (response) {
      Map<String, dynamic> value => value,
      Map value => Map<String, dynamic>.from(value),
      List value when value.isNotEmpty && value.first is Map =>
        Map<String, dynamic>.from(value.first as Map),
      _ => throw const FormatException('Invalid profile response.'),
    };
  }

  Map<String, dynamic> _responseMap(Object? response) {
    if (response is Map<String, dynamic>) return response;
    if (response is Map) return Map<String, dynamic>.from(response);
    throw const FormatException('Invalid profile API response.');
  }
}
