import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRepository {
  ProfileRepository([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<UserProfile> fetchOwnProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required.');

    final response = await _client
        .from('profiles')
        .select(
          'display_name, city, preferred_radius_km, '
          'approximate_latitude, approximate_longitude',
        )
        .eq('id', userId)
        .single();
    return UserProfile.fromJson(response);
  }

  Future<void> updateProfile({
    required String displayName,
    required String city,
    required double preferredRadiusKm,
    double? latitude,
    double? longitude,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in required.');

    final values = <String, Object?>{
      'display_name': displayName.trim(),
      'city': city.trim().isEmpty ? null : city.trim(),
      'preferred_radius_km': preferredRadiusKm,
    };
    if (latitude != null && longitude != null) {
      values['approximate_latitude'] = _roundLocation(latitude);
      values['approximate_longitude'] = _roundLocation(longitude);
    }

    await _client.from('profiles').update(values).eq('id', userId);
  }

  double _roundLocation(double value) => (value * 100).round() / 100;
}
