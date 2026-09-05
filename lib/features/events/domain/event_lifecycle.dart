class EventAnnouncement {
  const EventAnnouncement({
    required this.id,
    required this.eventId,
    required this.body,
    required this.createdAt,
  });

  factory EventAnnouncement.fromJson(Map<String, dynamic> json) =>
      EventAnnouncement(
        id: json['id'] as String,
        eventId: json['event_id'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );

  final String id;
  final String eventId;
  final String body;
  final DateTime createdAt;
}

class EventCohost {
  const EventCohost({
    required this.profileId,
    required this.displayName,
    required this.username,
    required this.role,
    required this.viewerCanEdit,
  });

  factory EventCohost.fromJson(Map<String, dynamic> json) => EventCohost(
    profileId: json['profile_id'] as String,
    displayName: (json['display_name'] as String?) ?? 'Community member',
    username: (json['username'] as String?) ?? '',
    role: (json['role'] as String?) ?? 'Co-host',
    viewerCanEdit: json['viewer_can_edit'] == true,
  );

  final String profileId;
  final String displayName;
  final String username;
  final String role;
  final bool viewerCanEdit;
}

class EventDiscussionSummary {
  const EventDiscussionSummary({
    required this.summary,
    required this.actionItems,
  });

  factory EventDiscussionSummary.fromJson(Map<String, dynamic> json) =>
      EventDiscussionSummary(
        summary: json['summary'] as String,
        actionItems: (json['action_items'] as List<dynamic>)
            .cast<String>()
            .toList(growable: false),
      );

  final String summary;
  final List<String> actionItems;
}

class EventDiscussionMessage {
  const EventDiscussionMessage({
    required this.id,
    required this.eventId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.createdAt,
    required this.viewerIsAuthor,
  });

  factory EventDiscussionMessage.fromJson(Map<String, dynamic> json) =>
      EventDiscussionMessage(
        id: json['id'] as String,
        eventId: json['event_id'] as String,
        authorId: json['author_id'] as String,
        authorName: (json['author_name'] as String?) ?? 'Community member',
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        viewerIsAuthor: json['viewer_is_author'] == true,
      );

  final String id;
  final String eventId;
  final String authorId;
  final String authorName;
  final String body;
  final DateTime createdAt;
  final bool viewerIsAuthor;
}

class MemberNotification {
  const MemberNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.eventId,
  });

  factory MemberNotification.fromJson(Map<String, dynamic> json) =>
      MemberNotification(
        id: json['id'] as String,
        eventId: json['event_id'] as String?,
        kind: json['kind'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        isRead: json['read_at'] != null,
      );

  final String id;
  final String? eventId;
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  MemberNotification copyWith({bool? isRead}) => MemberNotification(
    id: id,
    eventId: eventId,
    kind: kind,
    title: title,
    body: body,
    createdAt: createdAt,
    isRead: isRead ?? this.isRead,
  );
}

class EventFeedbackEntry {
  const EventFeedbackEntry({
    required this.attended,
    required this.comment,
    required this.createdAt,
    this.rating,
  });

  factory EventFeedbackEntry.fromJson(Map<String, dynamic> json) =>
      EventFeedbackEntry(
        attended: json['attended'] == true,
        rating: json['rating'] is int
            ? json['rating'] as int
            : int.tryParse('${json['rating']}'),
        comment: (json['comment'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );

  final bool attended;
  final int? rating;
  final String comment;
  final DateTime createdAt;
}

class EventAttendee {
  const EventAttendee({
    required this.profileId,
    required this.displayName,
    required this.username,
    required this.rsvpStatus,
    required this.visibleToAttendees,
    required this.isSelf,
    this.reconfirmedAt,
  });

  factory EventAttendee.fromJson(Map<String, dynamic> json) => EventAttendee(
    profileId: json['profile_id'] as String,
    displayName: (json['display_name'] as String?) ?? 'Community member',
    username: (json['username'] as String?) ?? '',
    rsvpStatus: (json['rsvp_status'] as String?) ?? 'joined',
    visibleToAttendees: json['visible_to_attendees'] == true,
    isSelf: json['is_self'] == true,
    reconfirmedAt: json['reconfirmed_at'] is String
        ? DateTime.parse(json['reconfirmed_at'] as String).toLocal()
        : null,
  );

  final String profileId;
  final String displayName;
  final String username;
  final String rsvpStatus;
  final bool visibleToAttendees;
  final bool isSelf;
  final DateTime? reconfirmedAt;
}
