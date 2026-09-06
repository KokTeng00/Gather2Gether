import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/edit_profile_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_widgets.dart';

const _profile = UserProfile(
  displayName: 'Maya',
  username: 'maya_local',
  city: 'Berlin',
  preferredRadiusKm: 10,
  approximateLatitude: null,
  approximateLongitude: null,
  assistantEnabled: true,
);

class _Repository extends ProfileRepository {
  _Repository(this.profile);
  UserProfile profile;
  var uploads = 0;

  @override
  Future<void> uploadAvatar(PreparedImage image) async {
    uploads++;
    profile = profile.copyWith(avatarImageKey: 'replacement.jpg');
  }

  @override
  Future<UserProfile> fetchOwnProfile() async => profile;
}

void main() {
  for (final hasPhoto in [false, true]) {
    testWidgets(
      'camera badge opens the picker ${hasPhoto ? 'with' : 'without'} a photo',
      (tester) async {
        final profile = hasPhoto
            ? _profile.copyWith(avatarImageKey: 'original.jpg')
            : _profile;
        final repository = _Repository(profile);
        var picks = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: hasPhoto ? AppTheme.dark : AppTheme.light,
            home: EditProfileScreen(
              profile: profile,
              repository: repository,
              avatarUrlBuilder: (_) => null,
              avatarPicker: () async {
                picks++;
                return null;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final badge = find.byKey(const Key('profile-photo-action'));
        final avatar = find.byKey(const Key('edit-profile-avatar'));
        expect(
          find.byTooltip(
            hasPhoto ? 'Change profile photo' : 'Add profile photo',
          ),
          findsOneWidget,
        );
        expect(find.text('Add photo'), findsNothing);
        expect(find.text('Change photo'), findsNothing);
        expect(find.text('Remove photo'), findsNothing);
        expect(tester.getRect(badge).overlaps(tester.getRect(avatar)), isTrue);
        expect(tester.getSize(badge).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(badge).height, greaterThanOrEqualTo(44));
        await tester.tap(badge);
        await tester.pumpAndSettle();
        expect(picks, 1);
        expect(repository.uploads, 0);
        expect(
          tester.widget<ProfileAvatar>(avatar).profile.avatarImageKey,
          profile.avatarImageKey,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'camera badge replaces an existing photo and updates the profile',
    (tester) async {
      final profile = _profile.copyWith(avatarImageKey: 'original.jpg');
      final repository = _Repository(profile);
      final updates = <UserProfile>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: EditProfileScreen(
            profile: profile,
            repository: repository,
            avatarUrlBuilder: (_) => null,
            avatarPicker: () async =>
                PreparedImage(bytes: Uint8List.fromList([1, 2, 3])),
            onProfileChanged: updates.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-photo-action')));
      await tester.pumpAndSettle();
      expect(repository.uploads, 1);
      expect(updates.single.avatarImageKey, 'replacement.jpg');
      expect(
        tester
            .widget<ProfileAvatar>(find.byKey(const Key('edit-profile-avatar')))
            .profile
            .avatarImageKey,
        'replacement.jpg',
      );
      expect(find.text('Remove photo'), findsNothing);
      expect(find.byTooltip('Change profile photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
