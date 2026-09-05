class AssistantEventMatch {
  const AssistantEventMatch({
    required this.id,
    required this.title,
    required this.category,
    required this.venueName,
    required this.startAt,
    required this.distanceMeters,
  });

  factory AssistantEventMatch.fromJson(Map<String, dynamic> json) {
    return AssistantEventMatch(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Untitled event',
      category: (json['category'] as String?) ?? 'Event',
      venueName: (json['venue_name'] as String?) ?? '',
      startAt:
          DateTime.tryParse((json['start_at'] as String?) ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final String title;
  final String category;
  final String venueName;
  final DateTime startAt;
  final double distanceMeters;
}

class AssistantMessage {
  const AssistantMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.eventMatches = const [],
  });

  factory AssistantMessage.fromJson(
    Map<String, dynamic> json, {
    List<AssistantEventMatch> eventMatches = const [],
  }) {
    return AssistantMessage(
      id: int.tryParse('${json['id']}') ?? 0,
      role: (json['role'] as String?) ?? 'assistant',
      content: (json['content'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((json['created_at'] as String?) ?? '')?.toLocal() ??
          DateTime.now(),
      eventMatches: eventMatches,
    );
  }

  final int id;
  final String role;
  final String content;
  final DateTime createdAt;
  final List<AssistantEventMatch> eventMatches;

  bool get isUser => role == 'user';
}

class AssistantReply {
  const AssistantReply({required this.message, required this.eventMatches});

  final AssistantMessage message;
  final List<AssistantEventMatch> eventMatches;
}

class AssistantEventDraft {
  const AssistantEventDraft({
    required this.title,
    required this.description,
    required this.category,
    required this.beginnerFriendly,
    required this.eventSetting,
    required this.eventLanguage,
    required this.ageGuidance,
    required this.whatToBring,
  });

  factory AssistantEventDraft.fromJson(Map<String, dynamic> json) =>
      AssistantEventDraft(
        title: json['title'] as String,
        description: json['description'] as String,
        category: json['category'] as String,
        beginnerFriendly: json['beginner_friendly'] == true,
        eventSetting: json['event_setting'] as String,
        eventLanguage: json['event_language'] as String,
        ageGuidance: json['age_guidance'] as String,
        whatToBring: json['what_to_bring'] as String,
      );

  final String title;
  final String description;
  final String category;
  final bool beginnerFriendly;
  final String eventSetting;
  final String eventLanguage;
  final String ageGuidance;
  final String whatToBring;
}
