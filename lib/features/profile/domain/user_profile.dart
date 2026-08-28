class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.city,
    required this.preferredRadiusKm,
    required this.approximateLatitude,
    required this.approximateLongitude,
    required this.assistantEnabled,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      displayName: (json['display_name'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      preferredRadiusKm:
          (json['preferred_radius_km'] as num?)?.toDouble() ?? 10,
      approximateLatitude: (json['approximate_latitude'] as num?)?.toDouble(),
      approximateLongitude: (json['approximate_longitude'] as num?)?.toDouble(),
      assistantEnabled: (json['assistant_enabled'] as bool?) ?? true,
    );
  }

  final String displayName;
  final String city;
  final double preferredRadiusKm;
  final double? approximateLatitude;
  final double? approximateLongitude;
  final bool assistantEnabled;
}
