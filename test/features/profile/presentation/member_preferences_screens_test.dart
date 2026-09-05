import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/member_controls.dart';
import 'package:gather2gether/features/profile/presentation/notification_preferences_screen.dart';
import 'package:gather2gether/features/profile/presentation/recommendation_settings_screen.dart';

class _PreferencesRepository extends ProfileRepository {
  NotificationPreferences notificationValue = const NotificationPreferences();
  RecommendationPreferences recommendationValue =
      const RecommendationPreferences(
        enabled: true,
        hiddenCategories: [],
        hiddenCount: 2,
      );
  NotificationPreferences? savedNotifications;
  bool? savedRecommendationEnabled;
  List<String>? savedHiddenCategories;

  @override
  Future<NotificationPreferences> notificationPreferences() async =>
      notificationValue;

  @override
  Future<void> updateNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    savedNotifications = preferences;
    notificationValue = preferences;
  }

  @override
  Future<RecommendationPreferences> recommendationPreferences() async =>
      recommendationValue;

  @override
  Future<void> updateRecommendationPreferences({
    required bool enabled,
    required List<String> hiddenCategories,
  }) async {
    savedRecommendationEnabled = enabled;
    savedHiddenCategories = hiddenCategories;
    recommendationValue = RecommendationPreferences(
      enabled: enabled,
      hiddenCategories: hiddenCategories,
      hiddenCount: recommendationValue.hiddenCount,
    );
  }
}

void main() {
  testWidgets('notification settings use one app-bar Save action', (
    tester,
  ) async {
    final repository = _PreferencesRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: NotificationPreferencesScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    final saveFinder = find.byKey(
      const Key('save-notification-preferences-button'),
    );
    expect(saveFinder, findsOneWidget);
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNull);
    expect(find.text('Save preferences'), findsNothing);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Event reminders'));
    await tester.pump();
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNotNull);

    await tester.tap(saveFinder);
    await tester.pumpAndSettle();
    expect(repository.savedNotifications?.remindersEnabled, isFalse);
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNull);
  });

  testWidgets('recommendation changes wait for the same Save placement', (
    tester,
  ) async {
    final repository = _PreferencesRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: RecommendationSettingsScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    final saveFinder = find.byKey(
      const Key('save-recommendation-preferences-button'),
    );
    expect(saveFinder, findsOneWidget);
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNull);
    expect(find.text('Save hidden categories'), findsNothing);

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Personalized ordering'),
    );
    await tester.pump();
    expect(repository.savedRecommendationEnabled, isNull);
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNotNull);

    await tester.tap(saveFinder);
    await tester.pumpAndSettle();
    expect(repository.savedRecommendationEnabled, isFalse);
    expect(repository.savedHiddenCategories, isEmpty);
    expect(find.text('Reset recommendations'), findsOneWidget);
  });
}
