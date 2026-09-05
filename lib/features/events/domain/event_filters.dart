class EventDiscoveryFilters {
  const EventDiscoveryFilters({
    this.category,
    this.dateFilter = 'any',
    this.timeFilter = 'any',
    this.spotsOnly = false,
    this.followingOnly = false,
    this.beginnerFriendlyOnly = false,
    this.wheelchairAccessibleOnly = false,
    this.eventSetting = 'any',
    this.eventLanguage = '',
    this.ageGuidance = 'any',
  });

  final String? category;
  final String dateFilter;
  final String timeFilter;
  final bool spotsOnly;
  final bool followingOnly;
  final bool beginnerFriendlyOnly;
  final bool wheelchairAccessibleOnly;
  final String eventSetting;
  final String eventLanguage;
  final String ageGuidance;

  bool get isActive =>
      category != null ||
      dateFilter != 'any' ||
      timeFilter != 'any' ||
      spotsOnly ||
      followingOnly ||
      beginnerFriendlyOnly ||
      wheelchairAccessibleOnly ||
      eventSetting != 'any' ||
      eventLanguage.trim().isNotEmpty ||
      ageGuidance != 'any';

  ({DateTime? startFrom, DateTime? startBefore}) dateRange(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (dateFilter) {
      'today' => (
        startFrom: today,
        startBefore: today.add(const Duration(days: 1)),
      ),
      'tomorrow' => (
        startFrom: today.add(const Duration(days: 1)),
        startBefore: today.add(const Duration(days: 2)),
      ),
      'weekend' => _weekendRange(today),
      _ => (startFrom: null, startBefore: null),
    };
  }

  static ({DateTime startFrom, DateTime startBefore}) _weekendRange(
    DateTime today,
  ) {
    final daysUntilSaturday = (DateTime.saturday - today.weekday) % 7;
    final start = today.weekday == DateTime.sunday
        ? today
        : today.add(Duration(days: daysUntilSaturday));
    final end = today.weekday == DateTime.sunday
        ? today.add(const Duration(days: 1))
        : start.add(const Duration(days: 2));
    return (startFrom: start, startBefore: end);
  }

  EventDiscoveryFilters copyWith({
    String? category,
    bool clearCategory = false,
    String? dateFilter,
    String? timeFilter,
    bool? spotsOnly,
    bool? followingOnly,
    bool? beginnerFriendlyOnly,
    bool? wheelchairAccessibleOnly,
    String? eventSetting,
    String? eventLanguage,
    String? ageGuidance,
  }) => EventDiscoveryFilters(
    category: clearCategory ? null : category ?? this.category,
    dateFilter: dateFilter ?? this.dateFilter,
    timeFilter: timeFilter ?? this.timeFilter,
    spotsOnly: spotsOnly ?? this.spotsOnly,
    followingOnly: followingOnly ?? this.followingOnly,
    beginnerFriendlyOnly: beginnerFriendlyOnly ?? this.beginnerFriendlyOnly,
    wheelchairAccessibleOnly:
        wheelchairAccessibleOnly ?? this.wheelchairAccessibleOnly,
    eventSetting: eventSetting ?? this.eventSetting,
    eventLanguage: eventLanguage ?? this.eventLanguage,
    ageGuidance: ageGuidance ?? this.ageGuidance,
  );
}

class SavedEventSearch {
  const SavedEventSearch({
    required this.id,
    required this.name,
    required this.interest,
    required this.radiusKm,
    required this.filters,
    required this.alertsEnabled,
    required this.createdAt,
  });

  factory SavedEventSearch.fromJson(Map<String, dynamic> json) {
    final radius = json['radius_km'];
    return SavedEventSearch(
      id: json['id'] as String,
      name: json['name'] as String,
      interest: (json['interest'] as String?) ?? '',
      radiusKm: radius is num ? radius.toDouble() : double.parse('$radius'),
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
      alertsEnabled: json['alerts_enabled'] != false,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  final String id;
  final String name;
  final String interest;
  final double radiusKm;
  final EventDiscoveryFilters filters;
  final bool alertsEnabled;
  final DateTime createdAt;
}

String eventDateFilterLabel(String value) => switch (value) {
  'today' => 'Today',
  'tomorrow' => 'Tomorrow',
  'weekend' => 'This weekend',
  _ => 'Any date',
};

String eventTimeFilterLabel(String value) => switch (value) {
  'morning' => 'Morning',
  'afternoon' => 'Afternoon',
  'evening' => 'Evening',
  _ => 'Any time',
};

String eventSettingFilterLabel(String value) => switch (value) {
  'indoor' => 'Indoor',
  'outdoor' => 'Outdoor',
  'mixed' => 'Mixed',
  _ => 'Any setting',
};

String eventAgeFilterLabel(String value) => switch (value) {
  'all_ages' => 'All ages',
  'families' => 'Family friendly',
  'teens' => 'Teens',
  'adults' => 'Adults only',
  _ => 'Any age guidance',
};
