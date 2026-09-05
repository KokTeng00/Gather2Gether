import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/events/domain/event_filters.dart';

void main() {
  test('today and tomorrow use exact local-day boundaries', () {
    final now = DateTime(2026, 9, 3, 14, 30);

    final today = const EventDiscoveryFilters(
      dateFilter: 'today',
    ).dateRange(now);
    final tomorrow = const EventDiscoveryFilters(
      dateFilter: 'tomorrow',
    ).dateRange(now);

    expect(today.startFrom, DateTime(2026, 9, 3));
    expect(today.startBefore, DateTime(2026, 9, 4));
    expect(tomorrow.startFrom, DateTime(2026, 9, 4));
    expect(tomorrow.startBefore, DateTime(2026, 9, 5));
  });

  test('this weekend includes the upcoming Saturday and Sunday', () {
    final range = const EventDiscoveryFilters(
      dateFilter: 'weekend',
    ).dateRange(DateTime(2026, 9, 3));

    expect(range.startFrom, DateTime(2026, 9, 5));
    expect(range.startBefore, DateTime(2026, 9, 7));
  });

  test('filter activity includes practical accessibility choices', () {
    expect(const EventDiscoveryFilters().isActive, isFalse);
    expect(
      const EventDiscoveryFilters(
        spotsOnly: true,
        followingOnly: true,
        beginnerFriendlyOnly: true,
        wheelchairAccessibleOnly: true,
        eventSetting: 'outdoor',
        eventLanguage: 'English',
        ageGuidance: 'adults',
      ).isActive,
      isTrue,
    );
  });

  test('saved search restores every practical filter', () {
    final search = SavedEventSearch.fromJson({
      'id': '88888888-8888-4888-8888-888888888888',
      'name': 'Accessible outdoors',
      'interest': 'walking',
      'radius_km': 10,
      'category': 'Hiking',
      'date_filter': 'weekend',
      'time_filter': 'morning',
      'spots_only': true,
      'following_only': false,
      'beginner_friendly_only': true,
      'wheelchair_accessible_only': true,
      'event_setting': 'outdoor',
      'event_language': 'English',
      'age_guidance': 'all_ages',
      'alerts_enabled': false,
      'created_at': '2026-09-04T08:00:00Z',
    });

    expect(search.filters.beginnerFriendlyOnly, isTrue);
    expect(search.filters.wheelchairAccessibleOnly, isTrue);
    expect(search.filters.eventSetting, 'outdoor');
    expect(search.filters.eventLanguage, 'English');
    expect(search.filters.ageGuidance, 'all_ages');
    expect(search.alertsEnabled, isFalse);
  });
}
