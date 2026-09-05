class EventSummary {
  const EventSummary({
    required this.id,
    required this.organizerId,
    required this.organizerName,
    required this.title,
    required this.description,
    required this.category,
    required this.venueName,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.startAt,
    required this.endAt,
    required this.maxParticipants,
    required this.joinedCount,
    required this.tentativeCount,
    required this.distanceMeters,
    required this.userRsvpStatus,
    this.eventStatus = 'published',
    this.isSaved = false,
    this.reminderAt,
    this.waitlistPosition,
    this.viewerIsOrganizer = false,
    this.beginnerFriendly = false,
    this.wheelchairAccessible = false,
    this.eventSetting = 'unspecified',
    this.eventLanguage = '',
    this.ageGuidance = 'all_ages',
    this.whatToBring = '',
    this.attendeeVisible = false,
    this.discussionNotificationsEnabled = true,
    this.reconfirmationDeadlineAt,
    this.viewerReconfirmedAt,
    this.eventVisibility = 'public',
    this.eventSeriesId,
    this.recommendationReason = '',
  });

  factory EventSummary.fromJson(Map<String, dynamic> json) {
    int asInt(Object? value) => value is int ? value : int.parse('$value');
    double asDouble(Object? value) =>
        value is num ? value.toDouble() : double.parse('$value');

    return EventSummary(
      id: json['id'] as String,
      organizerId: json['organizer_id'] as String,
      organizerName: (json['organizer_name'] as String?) ?? 'Organizer',
      title: json['title'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
      venueName: json['venue_name'] as String,
      address: json['address'] as String,
      latitude: asDouble(json['latitude']),
      longitude: asDouble(json['longitude']),
      startAt: DateTime.parse(json['start_at'] as String).toLocal(),
      endAt: DateTime.parse(json['end_at'] as String).toLocal(),
      maxParticipants: asInt(json['max_participants']),
      joinedCount: asInt(json['joined_count']),
      tentativeCount: asInt(json['tentative_count']),
      distanceMeters: asDouble(json['distance_meters'] ?? 0),
      userRsvpStatus: json['user_rsvp_status'] as String?,
      eventStatus: (json['event_status'] as String?) ?? 'published',
      isSaved: json['is_saved'] == true,
      reminderAt: json['reminder_at'] is String
          ? DateTime.parse(json['reminder_at'] as String).toLocal()
          : null,
      waitlistPosition: json['waitlist_position'] == null
          ? null
          : asInt(json['waitlist_position']),
      viewerIsOrganizer: json['viewer_is_organizer'] == true,
      beginnerFriendly: json['beginner_friendly'] == true,
      wheelchairAccessible: json['wheelchair_accessible'] == true,
      eventSetting: (json['event_setting'] as String?) ?? 'unspecified',
      eventLanguage: (json['event_language'] as String?) ?? '',
      ageGuidance: (json['age_guidance'] as String?) ?? 'all_ages',
      whatToBring: (json['what_to_bring'] as String?) ?? '',
      attendeeVisible: json['attendee_visible'] == true,
      discussionNotificationsEnabled:
          json['discussion_notifications_enabled'] != false,
      reconfirmationDeadlineAt: json['reconfirmation_deadline_at'] is String
          ? DateTime.parse(
              json['reconfirmation_deadline_at'] as String,
            ).toLocal()
          : null,
      viewerReconfirmedAt: json['viewer_reconfirmed_at'] is String
          ? DateTime.parse(json['viewer_reconfirmed_at'] as String).toLocal()
          : null,
      eventVisibility: (json['event_visibility'] as String?) ?? 'public',
      eventSeriesId: json['event_series_id'] as String?,
      recommendationReason: (json['recommendation_reason'] as String?) ?? '',
    );
  }

  final String id;
  final String organizerId;
  final String organizerName;
  final String title;
  final String description;
  final String category;
  final String venueName;
  final String address;
  final double latitude;
  final double longitude;
  final DateTime startAt;
  final DateTime endAt;
  final int maxParticipants;
  final int joinedCount;
  final int tentativeCount;
  final double distanceMeters;
  final String? userRsvpStatus;
  final String eventStatus;
  final bool isSaved;
  final DateTime? reminderAt;
  final int? waitlistPosition;
  final bool viewerIsOrganizer;
  final bool beginnerFriendly;
  final bool wheelchairAccessible;
  final String eventSetting;
  final String eventLanguage;
  final String ageGuidance;
  final String whatToBring;
  final bool attendeeVisible;
  final bool discussionNotificationsEnabled;
  final DateTime? reconfirmationDeadlineAt;
  final DateTime? viewerReconfirmedAt;
  final String eventVisibility;
  final String? eventSeriesId;
  final String recommendationReason;

  Map<String, Object?> toJson() => {
    'id': id,
    'organizer_id': organizerId,
    'organizer_name': organizerName,
    'title': title,
    'description': description,
    'category': category,
    'venue_name': venueName,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'start_at': startAt.toUtc().toIso8601String(),
    'end_at': endAt.toUtc().toIso8601String(),
    'max_participants': maxParticipants,
    'joined_count': joinedCount,
    'tentative_count': tentativeCount,
    'distance_meters': distanceMeters,
    'user_rsvp_status': userRsvpStatus,
    'event_status': eventStatus,
    'is_saved': isSaved,
    'reminder_at': reminderAt?.toUtc().toIso8601String(),
    'waitlist_position': waitlistPosition,
    'viewer_is_organizer': viewerIsOrganizer,
    'beginner_friendly': beginnerFriendly,
    'wheelchair_accessible': wheelchairAccessible,
    'event_setting': eventSetting,
    'event_language': eventLanguage,
    'age_guidance': ageGuidance,
    'what_to_bring': whatToBring,
    'attendee_visible': attendeeVisible,
    'discussion_notifications_enabled': discussionNotificationsEnabled,
    'reconfirmation_deadline_at': reconfirmationDeadlineAt
        ?.toUtc()
        .toIso8601String(),
    'viewer_reconfirmed_at': viewerReconfirmedAt?.toUtc().toIso8601String(),
    'event_visibility': eventVisibility,
    'event_series_id': eventSeriesId,
    'recommendation_reason': recommendationReason,
  };

  bool get hasEnded => endAt.isBefore(DateTime.now());
  bool get isCancelled => eventStatus == 'cancelled';
  bool get needsReconfirmation =>
      userRsvpStatus == 'joined' &&
      reconfirmationDeadlineAt?.isAfter(DateTime.now()) == true &&
      viewerReconfirmedAt == null &&
      !viewerIsOrganizer;

  int get spotsLeft =>
      (maxParticipants - joinedCount).clamp(0, maxParticipants);

  EventSummary copyWith({
    int? joinedCount,
    int? tentativeCount,
    String? userRsvpStatus,
    bool clearRsvpStatus = false,
    String? eventStatus,
    bool? isSaved,
    DateTime? reminderAt,
    bool clearReminder = false,
    int? waitlistPosition,
    bool? viewerIsOrganizer,
    bool? attendeeVisible,
    bool? discussionNotificationsEnabled,
    DateTime? reconfirmationDeadlineAt,
    bool clearReconfirmationDeadline = false,
    DateTime? viewerReconfirmedAt,
    String? eventVisibility,
    String? eventSeriesId,
    String? recommendationReason,
  }) {
    return EventSummary(
      id: id,
      organizerId: organizerId,
      organizerName: organizerName,
      title: title,
      description: description,
      category: category,
      venueName: venueName,
      address: address,
      latitude: latitude,
      longitude: longitude,
      startAt: startAt,
      endAt: endAt,
      maxParticipants: maxParticipants,
      joinedCount: joinedCount ?? this.joinedCount,
      tentativeCount: tentativeCount ?? this.tentativeCount,
      distanceMeters: distanceMeters,
      userRsvpStatus: clearRsvpStatus
          ? null
          : userRsvpStatus ?? this.userRsvpStatus,
      eventStatus: eventStatus ?? this.eventStatus,
      isSaved: isSaved ?? this.isSaved,
      reminderAt: clearReminder ? null : reminderAt ?? this.reminderAt,
      waitlistPosition: waitlistPosition ?? this.waitlistPosition,
      viewerIsOrganizer: viewerIsOrganizer ?? this.viewerIsOrganizer,
      beginnerFriendly: beginnerFriendly,
      wheelchairAccessible: wheelchairAccessible,
      eventSetting: eventSetting,
      eventLanguage: eventLanguage,
      ageGuidance: ageGuidance,
      whatToBring: whatToBring,
      attendeeVisible: attendeeVisible ?? this.attendeeVisible,
      discussionNotificationsEnabled:
          discussionNotificationsEnabled ?? this.discussionNotificationsEnabled,
      reconfirmationDeadlineAt: clearReconfirmationDeadline
          ? null
          : reconfirmationDeadlineAt ?? this.reconfirmationDeadlineAt,
      viewerReconfirmedAt: viewerReconfirmedAt ?? this.viewerReconfirmedAt,
      eventVisibility: eventVisibility ?? this.eventVisibility,
      eventSeriesId: eventSeriesId ?? this.eventSeriesId,
      recommendationReason: recommendationReason ?? this.recommendationReason,
    );
  }
}
