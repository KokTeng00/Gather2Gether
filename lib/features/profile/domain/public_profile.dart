class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.displayName,
    required this.username,
    required this.bio,
    required this.city,
    required this.hasAvatar,
    required this.followersCount,
    required this.followingCount,
    required this.viewerIsFollowing,
    required this.viewerIsSelf,
    this.avatarVersion,
  });

  factory PublicProfile.fromJson(Map<String, dynamic> json) => PublicProfile(
    id: json['id'] as String,
    displayName: (json['display_name'] as String?) ?? 'Community member',
    username: (json['username'] as String?) ?? '',
    bio: (json['bio'] as String?) ?? '',
    city: (json['city'] as String?) ?? '',
    hasAvatar: json['has_avatar'] == true,
    avatarVersion: json['avatar_version'] is String
        ? DateTime.tryParse(json['avatar_version'] as String)?.toLocal()
        : null,
    followersCount: _count(json['followers_count']),
    followingCount: _count(json['following_count']),
    viewerIsFollowing: json['viewer_is_following'] == true,
    viewerIsSelf: json['viewer_is_self'] == true,
  );

  final String id;
  final String displayName;
  final String username;
  final String bio;
  final String city;
  final bool hasAvatar;
  final DateTime? avatarVersion;
  final int followersCount;
  final int followingCount;
  final bool viewerIsFollowing;
  final bool viewerIsSelf;

  PublicProfile copyWith({int? followersCount, bool? viewerIsFollowing}) =>
      PublicProfile(
        id: id,
        displayName: displayName,
        username: username,
        bio: bio,
        city: city,
        hasAvatar: hasAvatar,
        avatarVersion: avatarVersion,
        followersCount: followersCount ?? this.followersCount,
        followingCount: followingCount,
        viewerIsFollowing: viewerIsFollowing ?? this.viewerIsFollowing,
        viewerIsSelf: viewerIsSelf,
      );

  static int _count(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }
}
