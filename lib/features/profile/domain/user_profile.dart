class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.city,
    required this.preferredRadiusKm,
    required this.approximateLatitude,
    required this.approximateLongitude,
    required this.assistantEnabled,
    this.username = '',
    this.bio = '',
    this.avatarImageKey,
    this.updatedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final updatedAtValue = json['updated_at'];
    return UserProfile(
      displayName: (json['display_name'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      bio: (json['bio'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      preferredRadiusKm:
          (json['preferred_radius_km'] as num?)?.toDouble() ?? 10,
      approximateLatitude: (json['approximate_latitude'] as num?)?.toDouble(),
      approximateLongitude: (json['approximate_longitude'] as num?)?.toDouble(),
      assistantEnabled: (json['assistant_enabled'] as bool?) ?? true,
      avatarImageKey: json['avatar_image_key'] as String?,
      updatedAt: updatedAtValue is String
          ? DateTime.tryParse(updatedAtValue)?.toLocal()
          : null,
    );
  }

  final String displayName;
  final String username;
  final String bio;
  final String city;
  final double preferredRadiusKm;
  final double? approximateLatitude;
  final double? approximateLongitude;
  final bool assistantEnabled;
  final String? avatarImageKey;
  final DateTime? updatedAt;

  bool get hasAvatar => avatarImageKey?.trim().isNotEmpty == true;

  UserProfile copyWith({
    String? displayName,
    String? username,
    String? bio,
    String? city,
    double? preferredRadiusKm,
    double? approximateLatitude,
    double? approximateLongitude,
    bool? assistantEnabled,
    String? avatarImageKey,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      city: city ?? this.city,
      preferredRadiusKm: preferredRadiusKm ?? this.preferredRadiusKm,
      approximateLatitude: approximateLatitude ?? this.approximateLatitude,
      approximateLongitude: approximateLongitude ?? this.approximateLongitude,
      assistantEnabled: assistantEnabled ?? this.assistantEnabled,
      avatarImageKey: avatarImageKey ?? this.avatarImageKey,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
