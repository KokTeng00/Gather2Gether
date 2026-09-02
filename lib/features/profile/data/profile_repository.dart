import 'dart:convert';

import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/features/profile/domain/profile_stats.dart';
import 'package:gather2gether/features/profile/domain/public_profile.dart';
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
      // Keep read-only profile screens available during the short deployment
      // window between shipping the app and applying the cooldown migration.
      // Username writes never use this fallback.
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
      return UserProfile.fromJson(_singleRow(response));
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

  Future<bool> setFollowing(String profileId, bool following) async {
    final payload = _responseMap(
      await _edgeRequest(
        following ? 'PUT' : 'DELETE',
        'profiles/${Uri.encodeComponent(profileId)}/follow',
      ),
    );
    return payload['following'] == true;
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

  Future<Object?> _edgeRequest(String method, String path) async {
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
      });
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
