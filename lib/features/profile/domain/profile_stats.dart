class ProfileStats {
  const ProfileStats({
    required this.postsCount,
    required this.hostedCount,
    required this.goingCount,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) {
    return ProfileStats(
      postsCount: _count(json['posts_count']),
      hostedCount: _count(json['hosted_count']),
      goingCount: _count(json['going_count']),
    );
  }

  final int postsCount;
  final int hostedCount;
  final int goingCount;

  static int _count(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }
}
