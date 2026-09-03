import 'package:flutter/services.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';

/// Mirrors server-owned reminder choices into the device notification system.
/// The private in-app inbox remains the fallback when permission is declined.
class EventReminderService {
  const EventReminderService();

  static const _channel = MethodChannel('com.gather2gether/reminders');

  Future<bool> schedule(EventSummary event, DateTime remindAt) async {
    if (!remindAt.isAfter(DateTime.now())) return false;
    try {
      return await _channel.invokeMethod<bool>('schedule', {
            'id': _notificationId(event.id),
            'eventId': event.id,
            'at': remindAt.millisecondsSinceEpoch,
            'title': 'Event reminder',
            'body': '${event.title} starts soon.',
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> cancel(String eventId) async {
    try {
      await _channel.invokeMethod<void>('cancel', {
        'id': _notificationId(eventId),
      });
    } on PlatformException {
      // The server reminder/inbox remains authoritative.
    } on MissingPluginException {
      // Widget tests and unsupported platforms use the in-app fallback.
    }
  }

  int _notificationId(String eventId) =>
      int.parse(eventId.substring(0, 8), radix: 16) & 0x7fffffff;
}
