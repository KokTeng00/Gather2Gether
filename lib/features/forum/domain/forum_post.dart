import 'package:gather2gether/features/forum/domain/planning_poll.dart';

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
    this.likeCount = 0,
    this.viewerHasLiked = false,
    this.hasImage = false,
    this.hasPoll = false,
    this.poll,
    this.placeName,
    this.placeAddress,
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
      likeCount: _integer(json['like_count']),
      viewerHasLiked: json['liked'] == true || json['viewer_has_liked'] == true,
      hasImage: json['has_image'] == true,
      hasPoll: json['has_poll'] == true || json['poll'] is Map,
      poll: json['poll'] is Map
          ? PlanningPoll.fromJson(
              Map<String, dynamic>.from(json['poll'] as Map),
            )
          : null,
      placeName: _optionalString(json['place_name']),
      placeAddress: _optionalString(json['place_address']),
    );
  }

  static String? _optionalString(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static int _integer(Object? value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
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
  final int likeCount;
  final bool viewerHasLiked;
  final bool hasImage;
  final bool hasPoll;
  final PlanningPoll? poll;
  final String? placeName;
  final String? placeAddress;

  bool get isLocked => status == 'locked';

  bool get hasPlace => placeName != null && placeAddress != null;

  ForumPost withLike({required bool liked, required int count}) => ForumPost(
    id: id,
    authorId: authorId,
    authorName: authorName,
    category: category,
    title: title,
    body: body,
    status: status,
    createdAt: createdAt,
    lastActivityAt: lastActivityAt,
    commentCount: commentCount,
    viewerIsAuthor: viewerIsAuthor,
    likeCount: count,
    viewerHasLiked: liked,
    hasImage: hasImage,
    hasPoll: hasPoll,
    poll: poll,
    placeName: placeName,
    placeAddress: placeAddress,
  );
}
