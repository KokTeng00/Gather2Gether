enum ProfileConnectionKind {
  followers('Followers'),
  following('Following');

  const ProfileConnectionKind(this.label);
  final String label;
}

class ProfileConnection {
  const ProfileConnection({
    required this.id,
    required this.displayName,
    required this.username,
    this.hasAvatar = false,
    this.avatarVersion,
  });

  factory ProfileConnection.fromJson(Map<String, dynamic> json) =>
      ProfileConnection(
        id: json['id'] as String,
        displayName: (json['display_name'] as String?) ?? 'Community member',
        username: (json['username'] as String?) ?? '',
        hasAvatar: json['has_avatar'] == true,
        avatarVersion: json['avatar_version'] as String?,
      );

  final String id;
  final String displayName;
  final String username;
  final bool hasAvatar;
  final String? avatarVersion;
}

class ProfileConnectionPage {
  const ProfileConnectionPage({
    required this.members,
    required this.canSearch,
    this.nextCursor,
  });
  final List<ProfileConnection> members;
  final bool canSearch;
  final String? nextCursor;
}
