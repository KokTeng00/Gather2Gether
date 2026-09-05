import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';

class EventOfflineCache {
  EventOfflineCache({FlutterSecureStorage? storage, DateTime Function()? now})
    : _storage = storage ?? const FlutterSecureStorage(),
      _now = now ?? DateTime.now;

  static const _maximumAge = Duration(hours: 24);
  static const _maximumEvents = 30;
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;

  Future<void> writeEvents(
    String userId,
    String scope,
    List<EventSummary> events,
  ) async {
    try {
      await _storage.write(
        key: _key(userId, scope),
        value: jsonEncode({
          'saved_at': _now().toUtc().toIso8601String(),
          'events': events
              .take(_maximumEvents)
              .map((event) => event.toJson())
              .toList(growable: false),
        }),
      );
    } catch (_) {
      // Offline caching is best-effort and must never break a live request.
    }
  }

  Future<List<EventSummary>?> readEvents(String userId, String scope) async {
    try {
      final key = _key(userId, scope);
      final encoded = await _storage.read(key: key);
      if (encoded == null) return null;
      final payload = jsonDecode(encoded);
      if (payload is! Map) {
        await _storage.delete(key: key);
        return null;
      }
      final savedAt = DateTime.tryParse('${payload['saved_at']}');
      final rows = payload['events'];
      if (savedAt == null ||
          rows is! List ||
          _now().toUtc().difference(savedAt.toUtc()) > _maximumAge) {
        await _storage.delete(key: key);
        return null;
      }
      return rows
          .whereType<Map>()
          .map((row) => EventSummary.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  String _key(String userId, String scope) =>
      'g2g.events.v1.$userId.${scope.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
}
