import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/app.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/core/theme/appearance_controller.dart';
import 'package:gather2gether/features/profile/presentation/appearance_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'appearance survives a new controller and supports system fallback',
    () async {
      final first = AppearanceController();
      await first.setMode(ThemeMode.dark);
      final next = AppearanceController();
      await next.load();
      expect(next.mode, ThemeMode.dark);
      await next.setMode(ThemeMode.system);
      await first.load();
      expect(first.mode, ThemeMode.system);
      FlutterSecureStorage.setMockInitialValues({
        AppearanceController.storageKey: 'unknown',
      });
      await next.load();
      expect(next.mode, ThemeMode.system);
      first.dispose();
      next.dispose();
    },
  );

  testWidgets(
    'appearance changes the whole app without losing the current page',
    (tester) async {
      final controller = AppearanceController.instance;
      await controller.load();
      addTearDown(() async => controller.setMode(ThemeMode.system));
      await tester.pumpWidget(const Gather2GetherApp(isConfigured: false));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push<void>(
        MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('appearance-dark')));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Color theme'))).brightness,
        Brightness.dark,
      );
      expect(find.text('Appearance'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(
        Theme.of(
          tester.element(find.text('Configuration required')),
        ).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('visibility label stays on one line beside a short value', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              // The test font uses wide, square glyphs; leave enough room for both texts.
              width: 460,
              child: AppChoiceField(
                label: 'Who can find it',
                value: 'Public',
                options: const ['Public', 'Unlisted'],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.text('Who can find it')).height, lessThan(30));
    expect(
      (tester.getCenter(find.text('Public')).dy -
              tester.getCenter(find.text('Who can find it')).dy)
          .abs(),
      lessThan(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large type moves the picker value below its complete label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: AppChoiceField(
                  label: 'Who can find it',
                  value: 'People with the link',
                  options: const ['Public', 'People with the link'],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('People with the link')).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.text('Who can find it')).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
