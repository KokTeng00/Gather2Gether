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

  testWidgets(
    'hidden category search keeps selections until the parent saves',
    (tester) async {
      final repository = _PreferencesRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RecommendationSettingsScreen(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('recommendation-hidden-categories')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Coffee');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-option-Coffee')));
      await tester.enterText(find.byType(TextField), 'Running');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-option-Running')));
      await tester.tap(find.byKey(const Key('settings-picker-done')));
      await tester.pumpAndSettle();
      expect(repository.savedHiddenCategories, isNull);
      await tester.tap(
        find.byKey(const Key('save-recommendation-preferences-button')),
      );
      await tester.pumpAndSettle();
      expect(
        repository.savedHiddenCategories,
        unorderedEquals(['Coffee', 'Running']),
      );

      await tester.tap(
        find.byKey(const Key('recommendation-hidden-categories')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-option-Badminton')));
      await tester.pageBack();
      await tester.pumpAndSettle();
      final save = tester.widget<TextButton>(
        find.byKey(const Key('save-recommendation-preferences-button')),
      );
      expect(save.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

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
      find.widgetWithText(SwitchListTile, 'Personalize my feed'),
    );
    await tester.pump();
    expect(repository.savedRecommendationEnabled, isNull);
    expect(tester.widget<TextButton>(saveFinder).onPressed, isNotNull);

    await tester.tap(saveFinder);
    await tester.pumpAndSettle();
    expect(repository.savedRecommendationEnabled, isFalse);
    expect(repository.savedHiddenCategories, isEmpty);
    await tester.scrollUntilVisible(
      find.byKey(const Key('reset-recommendations-button')),
      200,
    );
    expect(find.text('Reset recommendations'), findsOneWidget);
  });
}
