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

  int get spotsLeft =>
      (maxParticipants - joinedCount).clamp(0, maxParticipants);

  EventSummary copyWith({
    int? joinedCount,
    int? tentativeCount,
    String? userRsvpStatus,
    bool clearRsvpStatus = false,
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
    );
  }
}
