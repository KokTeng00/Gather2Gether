const memberInterestOptions = [
  'Sports',
  'Outdoors',
  'Coffee',
  'Games',
  'Languages',
  'Photography',
  'Technology',
  'Arts',
  'Wellness',
  'Volunteering',
];

const memberAccessibilityOptions = <String, String>{
  'wheelchair_accessible': 'Wheelchair accessible',
  'beginner_friendly': 'Beginner friendly',
};

class NotificationPreferences {
  const NotificationPreferences({
    this.pushEnabled = true,
    this.remindersEnabled = true,
    this.announcementsEnabled = true,
    this.discussionEnabled = true,
    this.recommendationsEnabled = true,
    this.quietStartMinute,
    this.quietEndMinute,
    this.timezoneOffsetMinutes = 0,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        pushEnabled: json['push_enabled'] != false,
        remindersEnabled: json['reminders_enabled'] != false,
        announcementsEnabled: json['announcements_enabled'] != false,
        discussionEnabled: json['discussion_enabled'] != false,
        recommendationsEnabled: json['recommendations_enabled'] != false,
        quietStartMinute: (json['quiet_start_minute'] as num?)?.toInt(),
        quietEndMinute: (json['quiet_end_minute'] as num?)?.toInt(),
        timezoneOffsetMinutes:
            (json['timezone_offset_minutes'] as num?)?.toInt() ?? 0,
      );

  final bool pushEnabled;
  final bool remindersEnabled;
  final bool announcementsEnabled;
  final bool discussionEnabled;
  final bool recommendationsEnabled;
  final int? quietStartMinute;
  final int? quietEndMinute;
  final int timezoneOffsetMinutes;

  Map<String, Object?> toJson() => {
    'push_enabled': pushEnabled,
    'reminders_enabled': remindersEnabled,
    'announcements_enabled': announcementsEnabled,
    'discussion_enabled': discussionEnabled,
    'recommendations_enabled': recommendationsEnabled,
    'quiet_start_minute': quietStartMinute,
    'quiet_end_minute': quietEndMinute,
    'timezone_offset_minutes': timezoneOffsetMinutes,
  };

  NotificationPreferences copyWith({
    bool? pushEnabled,
    bool? remindersEnabled,
    bool? announcementsEnabled,
    bool? discussionEnabled,
    bool? recommendationsEnabled,
    int? quietStartMinute,
    int? quietEndMinute,
    bool clearQuietHours = false,
    int? timezoneOffsetMinutes,
  }) => NotificationPreferences(
    pushEnabled: pushEnabled ?? this.pushEnabled,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    announcementsEnabled: announcementsEnabled ?? this.announcementsEnabled,
    discussionEnabled: discussionEnabled ?? this.discussionEnabled,
    recommendationsEnabled:
        recommendationsEnabled ?? this.recommendationsEnabled,
    quietStartMinute: clearQuietHours
        ? null
        : quietStartMinute ?? this.quietStartMinute,
    quietEndMinute: clearQuietHours
        ? null
        : quietEndMinute ?? this.quietEndMinute,
    timezoneOffsetMinutes: timezoneOffsetMinutes ?? this.timezoneOffsetMinutes,
  );
}

class RecommendationPreferences {
  const RecommendationPreferences({
    required this.enabled,
    required this.hiddenCategories,
    required this.hiddenCount,
  });

  factory RecommendationPreferences.fromJson(Map<String, dynamic> json) =>
      RecommendationPreferences(
        enabled: json['enabled'] != false,
        hiddenCategories:
            (json['hidden_categories'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList(growable: false),
        hiddenCount: (json['hidden_count'] as num?)?.toInt() ?? 0,
      );

  final bool enabled;
  final List<String> hiddenCategories;
  final int hiddenCount;
}

class MemberReport {
  const MemberReport({
    required this.kind,
    required this.id,
    required this.reason,
    required this.status,
    required this.title,
    required this.createdAt,
  });

  factory MemberReport.fromJson(Map<String, dynamic> json) => MemberReport(
    kind: json['report_kind'] as String,
    id: json['report_id'] as String,
    reason: json['reason'] as String,
    status: json['status'] as String,
    title: json['target_title'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );

  final String kind;
  final String id;
  final String reason;
  final String status;
  final String title;
  final DateTime createdAt;
}

class ModerationReport extends MemberReport {
  const ModerationReport({
    required super.kind,
    required super.id,
    required super.reason,
    required super.status,
    required super.title,
    required super.createdAt,
    required this.excerpt,
    this.priority,
    this.priorityReason,
  });

  factory ModerationReport.fromJson(Map<String, dynamic> json) =>
      ModerationReport(
        kind: json['report_kind'] as String,
        id: json['report_id'] as String,
        reason: json['reason'] as String,
        status: json['status'] as String,
        title: json['target_title'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        excerpt: (json['excerpt'] as String?) ?? '',
        priority: json['priority'] as String?,
        priorityReason: json['priority_reason'] as String?,
      );

  final String excerpt;
  final String? priority;
  final String? priorityReason;

  ModerationReport withPriority(String value, String explanation) =>
      ModerationReport(
        kind: kind,
        id: id,
        reason: reason,
        status: status,
        title: title,
        createdAt: createdAt,
        excerpt: excerpt,
        priority: value,
        priorityReason: explanation,
      );
}
