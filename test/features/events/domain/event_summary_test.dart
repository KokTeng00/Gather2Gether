import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';

void main() {
  test('parses an event RPC response and calculates capacity', () {
    final event = EventSummary.fromJson({
      'id': 'event-id',
      'organizer_id': 'organizer-id',
      'organizer_name': 'Alex',
      'title': 'Morning Run',
      'description': 'An easy social run.',
      'category': 'Running',
      'venue_name': 'City Park',
      'address': 'Main entrance',
      'latitude': 52.52,
      'longitude': 13.405,
      'start_at': '2026-09-01T08:00:00Z',
      'end_at': '2026-09-01T09:00:00Z',
      'max_participants': 10,
      'joined_count': 4,
      'tentative_count': 2,
      'distance_meters': 850.5,
      'user_rsvp_status': 'tentative',
    });

    expect(event.organizerName, 'Alex');
    expect(event.spotsLeft, 6);
    expect(event.userRsvpStatus, 'tentative');
  });
}
