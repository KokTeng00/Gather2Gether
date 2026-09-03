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

  test('filter activity includes following and availability choices', () {
    expect(const EventDiscoveryFilters().isActive, isFalse);
    expect(
      const EventDiscoveryFilters(
        spotsOnly: true,
        followingOnly: true,
      ).isActive,
      isTrue,
    );
  });
}
