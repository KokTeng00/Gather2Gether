class PollDateOption {
  const PollDateOption({
    required this.startAt,
    required this.endAt,
    this.id = '',
    this.voteCount = 0,
    this.voted = false,
  });
  factory PollDateOption.fromJson(Map<String, dynamic> json) => PollDateOption(
    id: json['id'] as String,
    startAt: DateTime.parse(json['start_at'] as String).toLocal(),
    endAt: DateTime.parse(json['end_at'] as String).toLocal(),
    voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
    voted: json['voted'] == true,
  );
  final String id;
  final DateTime startAt;
  final DateTime endAt;
  final int voteCount;
  final bool voted;
  Map<String, String> toJson() => {
    'start_at': startAt.toUtc().toIso8601String(),
    'end_at': endAt.toUtc().toIso8601String(),
  };
}

class PlanningPoll {
  const PlanningPoll({
    required this.postId,
    required this.closed,
    required this.canVote,
    required this.viewerIsAuthor,
    required this.options,
    this.eventId,
  });
  factory PlanningPoll.fromJson(Map<String, dynamic> json) => PlanningPoll(
    postId: json['post_id'] as String,
    closed: json['closed'] == true,
    canVote: json['can_vote'] == true,
    viewerIsAuthor: json['viewer_is_author'] == true,
    eventId: json['event_id'] as String?,
    options: (json['options'] as List)
        .map(
          (row) =>
              PollDateOption.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList(),
  );
  final String postId;
  final bool closed;
  final bool canVote;
  final bool viewerIsAuthor;
  final String? eventId;
  final List<PollDateOption> options;
}
