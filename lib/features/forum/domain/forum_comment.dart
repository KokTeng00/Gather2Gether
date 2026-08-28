class ForumComment {
  const ForumComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    required this.viewerIsAuthor,
  });

  factory ForumComment.fromJson(Map<String, dynamic> json) => ForumComment(
    id: json['id'] as String,
    postId: json['post_id'] as String,
    authorId: json['author_id'] as String,
    authorName: (json['author_name'] as String?) ?? 'Community member',
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    viewerIsAuthor: json['viewer_is_author'] == true,
  );

  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final bool viewerIsAuthor;
}
