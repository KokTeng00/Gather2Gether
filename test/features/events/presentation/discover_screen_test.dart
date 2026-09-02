import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/events/presentation/discover_screen.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';

class _UnavailableProfileRepository extends ProfileRepository {
  @override
  Future<UserProfile> fetchOwnProfile() async {
    throw StateError('schema detail hidden from UI');
  }
}

void main() {
  testWidgets('saved-area failures use neutral maintenance messaging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DiscoverScreen(
            onCreate: () {},
            profileRepository: _UnavailableProfileRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discover-maintenance-state')), findsOneWidget);
    expect(find.text('MAINTENANCE'), findsOneWidget);
    expect(find.text('We’ll be back soon'), findsOneWidget);
    expect(find.text('We could not load your saved area.'), findsNothing);
    expect(find.text('schema detail hidden from UI'), findsNothing);
    expect(find.text('Check again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
