import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/profile/domain/profile_stats.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';

void main() {
  test(
    'profile parses public identity, private preferences, and avatar state',
    () {
      final profile = UserProfile.fromJson({
        'display_name': 'Maya Chen',
        'username': 'maya_chen',
        'bio': 'Local walks and coffee.',
        'city': 'Berlin',
        'preferred_radius_km': 25,
        'approximate_latitude': 52.52,
        'approximate_longitude': 13.4,
        'assistant_enabled': false,
        'avatar_image_key': 'avatars/maya-v2',
        'updated_at': '2026-08-31T10:30:00Z',
      });

      expect(profile.username, 'maya_chen');
      expect(profile.bio, 'Local walks and coffee.');
      expect(profile.preferredRadiusKm, 25);
      expect(profile.assistantEnabled, isFalse);
      expect(profile.hasAvatar, isTrue);
      expect(
        profile.updatedAt,
        DateTime.parse('2026-08-31T10:30:00Z').toLocal(),
      );
    },
  );

  test('profile additions remain safe for older or partial responses', () {
    final profile = UserProfile.fromJson({'display_name': 'Maya'});

    expect(profile.username, isEmpty);
    expect(profile.bio, isEmpty);
    expect(profile.hasAvatar, isFalse);
    expect(profile.preferredRadiusKm, 10);
    expect(profile.assistantEnabled, isTrue);
  });

  test('profile stats accepts PostgREST numeric representations', () {
    final stats = ProfileStats.fromJson({
      'posts_count': '12',
      'hosted_count': 4,
      'going_count': 7,
    });

    expect(stats.postsCount, 12);
    expect(stats.hostedCount, 4);
    expect(stats.goingCount, 7);
  });
}
