class ProfileStats {
  const ProfileStats({
    required this.postsCount,
    required this.hostedCount,
    required this.goingCount,
    this.followersCount = 0,
    this.followingCount = 0,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) {
    return ProfileStats(
      postsCount: _count(json['posts_count']),
      hostedCount: _count(json['hosted_count']),
      goingCount: _count(json['going_count']),
      followersCount: _count(json['followers_count']),
      followingCount: _count(json['following_count']),
    );
  }

  final int postsCount;
  final int hostedCount;
  final int goingCount;
  final int followersCount;
  final int followingCount;

  static int _count(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }
}
