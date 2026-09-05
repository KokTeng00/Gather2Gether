class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.city,
    required this.preferredRadiusKm,
    required this.approximateLatitude,
    required this.approximateLongitude,
    required this.assistantEnabled,
    this.showPastEventsPublic = false,
    this.username = '',
    this.bio = '',
    this.avatarImageKey,
    this.usernameChangedAt,
    this.updatedAt,
    this.interests = const [],
    this.accessibilityPreferences = const [],
    this.onboardingCompletedAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final updatedAtValue = json['updated_at'];
    final usernameChangedAtValue = json['username_changed_at'];
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
      showPastEventsPublic: json['show_past_events_public'] == true,
      avatarImageKey: json['avatar_image_key'] as String?,
      usernameChangedAt: usernameChangedAtValue is String
          ? DateTime.tryParse(usernameChangedAtValue)?.toLocal()
          : null,
      updatedAt: updatedAtValue is String
          ? DateTime.tryParse(updatedAtValue)?.toLocal()
          : null,
      interests: (json['interests'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      accessibilityPreferences:
          (json['accessibility_preferences'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(growable: false),
      onboardingCompletedAt: json['onboarding_completed_at'] is String
          ? DateTime.tryParse(
              json['onboarding_completed_at'] as String,
            )?.toLocal()
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
  final bool showPastEventsPublic;
  final String? avatarImageKey;
  final DateTime? usernameChangedAt;
  final DateTime? updatedAt;
  final List<String> interests;
  final List<String> accessibilityPreferences;
  final DateTime? onboardingCompletedAt;

  bool get hasCompletedOnboarding => onboardingCompletedAt != null;

  bool get hasAvatar => avatarImageKey?.trim().isNotEmpty == true;

  /// The instant at which PostgreSQL's three-calendar-month cooldown ends.
  DateTime? get nextUsernameChangeAt {
    final changedAt = usernameChangedAt;
    if (changedAt == null) return null;

    // Supabase evaluates the interval in UTC. Clamp the day so dates such as
    // 31 January match PostgreSQL's calendar-month behaviour.
    final utc = changedAt.toUtc();
    final monthIndex = utc.month - 1 + 3;
    final year = utc.year + monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    final day = utc.day > lastDay ? lastDay : utc.day;
    return DateTime.utc(
      year,
      month,
      day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond,
      utc.microsecond,
    ).toLocal();
  }

  bool canChangeUsernameAt(DateTime now) {
    final nextChange = nextUsernameChangeAt;
    return nextChange == null || !now.isBefore(nextChange);
  }

  UserProfile copyWith({
    String? displayName,
    String? username,
    String? bio,
    String? city,
    double? preferredRadiusKm,
    double? approximateLatitude,
    double? approximateLongitude,
    bool? assistantEnabled,
    bool? showPastEventsPublic,
    String? avatarImageKey,
    DateTime? usernameChangedAt,
    DateTime? updatedAt,
    List<String>? interests,
    List<String>? accessibilityPreferences,
    DateTime? onboardingCompletedAt,
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
      showPastEventsPublic: showPastEventsPublic ?? this.showPastEventsPublic,
      avatarImageKey: avatarImageKey ?? this.avatarImageKey,
      usernameChangedAt: usernameChangedAt ?? this.usernameChangedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      interests: interests ?? this.interests,
      accessibilityPreferences:
          accessibilityPreferences ?? this.accessibilityPreferences,
      onboardingCompletedAt:
          onboardingCompletedAt ?? this.onboardingCompletedAt,
    );
  }
}
