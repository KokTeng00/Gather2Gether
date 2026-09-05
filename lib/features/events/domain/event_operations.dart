import 'package:gather2gether/features/events/domain/event_filters.dart';

class NaturalEventFilters {
  const NaturalEventFilters({
    required this.interest,
    required this.filters,
    this.radiusKm,
  });

  factory NaturalEventFilters.fromJson(Map<String, dynamic> json) =>
      NaturalEventFilters(
        interest: (json['interest'] as String?) ?? '',
        radiusKm: (json['radius_km'] as num?)?.toDouble(),
        filters: EventDiscoveryFilters(
          category: json['category'] as String?,
          dateFilter: (json['date_filter'] as String?) ?? 'any',
          timeFilter: (json['time_filter'] as String?) ?? 'any',
          spotsOnly: json['spots_only'] == true,
          followingOnly: json['following_only'] == true,
          beginnerFriendlyOnly: json['beginner_friendly_only'] == true,
          wheelchairAccessibleOnly: json['wheelchair_accessible_only'] == true,
          eventSetting: (json['event_setting'] as String?) ?? 'any',
          eventLanguage: (json['event_language'] as String?) ?? '',
          ageGuidance: (json['age_guidance'] as String?) ?? 'any',
        ),
      );

  final String interest;
  final EventDiscoveryFilters filters;
  final double? radiusKm;
}

class EventQualityIssue {
  const EventQualityIssue({
    required this.field,
    required this.severity,
    required this.message,
  });

  factory EventQualityIssue.fromJson(Map<String, dynamic> json) =>
      EventQualityIssue(
        field: json['field'] as String,
        severity: json['severity'] as String,
        message: json['message'] as String,
      );

  final String field;
  final String severity;
  final String message;
}

class EventQualityReview {
  const EventQualityReview({required this.ready, required this.issues});

  factory EventQualityReview.fromJson(Map<String, dynamic> json) =>
      EventQualityReview(
        ready: json['ready'] == true,
        issues: (json['issues'] as List<dynamic>? ?? const [])
            .map(
              (value) => EventQualityIssue.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(growable: false),
      );

  final bool ready;
  final List<EventQualityIssue> issues;
}

class EventHostDashboard {
  const EventHostDashboard({
    required this.joined,
    required this.tentative,
    required this.waitlisted,
    required this.attended,
    required this.noShow,
    required this.saved,
    required this.feedbackCount,
    required this.averageRating,
  });

  factory EventHostDashboard.fromJson(Map<String, dynamic> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    return EventHostDashboard(
      joined: count('joined'),
      tentative: count('tentative'),
      waitlisted: count('waitlisted'),
      attended: count('attended'),
      noShow: count('no_show'),
      saved: count('saved'),
      feedbackCount: count('feedback_count'),
      averageRating: (json['average_rating'] as num?)?.toDouble(),
    );
  }

  final int joined;
  final int tentative;
  final int waitlisted;
  final int attended;
  final int noShow;
  final int saved;
  final int feedbackCount;
  final double? averageRating;
}

class EventHostAttendee {
  const EventHostAttendee({
    required this.profileId,
    required this.displayName,
    required this.username,
    required this.status,
    this.reconfirmedAt,
  });

  factory EventHostAttendee.fromJson(Map<String, dynamic> json) =>
      EventHostAttendee(
        profileId: json['profile_id'] as String,
        displayName: json['display_name'] as String,
        username: (json['username'] as String?) ?? '',
        status: json['rsvp_status'] as String,
        reconfirmedAt: json['reconfirmed_at'] is String
            ? DateTime.tryParse(json['reconfirmed_at'] as String)?.toLocal()
            : null,
      );

  final String profileId;
  final String displayName;
  final String username;
  final String status;
  final DateTime? reconfirmedAt;
}

class DiscussionChanges {
  const DiscussionChanges({
    required this.summary,
    required this.actionItems,
    required this.messageCount,
  });

  factory DiscussionChanges.fromJson(Map<String, dynamic> json) =>
      DiscussionChanges(
        summary: json['summary'] as String,
        actionItems: (json['action_items'] as List<dynamic>).cast<String>(),
        messageCount: (json['message_count'] as num).toInt(),
      );

  final String summary;
  final List<String> actionItems;
  final int messageCount;
}
