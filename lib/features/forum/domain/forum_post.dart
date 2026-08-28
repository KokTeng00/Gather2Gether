class ForumPost {
  const ForumPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.category,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.lastActivityAt,
    required this.commentCount,
    required this.viewerIsAuthor,
  });

  factory ForumPost.fromJson(Map<String, dynamic> json) {
    final count = json['comment_count'];
    return ForumPost(
      id: json['id'] as String,
      authorId: json['author_id'] as String,
      authorName: (json['author_name'] as String?) ?? 'Community member',
      category: json['category'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      lastActivityAt: DateTime.parse(
        json['last_activity_at'] as String,
      ).toLocal(),
      commentCount: count is int ? count : int.parse('$count'),
      viewerIsAuthor: json['viewer_is_author'] == true,
    );
  }

  final String id;
  final String authorId;
  final String authorName;
  final String category;
  final String title;
  final String body;
  final String status;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final int commentCount;
  final bool viewerIsAuthor;

  bool get isLocked => status == 'locked';
}
