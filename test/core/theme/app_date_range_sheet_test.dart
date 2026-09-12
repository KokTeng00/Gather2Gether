import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_date_range_sheet.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';
import 'package:gather2gether/core/theme/app_theme.dart';

Future<void> _openCalendar(
  WidgetTester tester, {
  DateTimeRange? initial,
  required ValueChanged<DateTimeRange?> onClosed,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onClosed(
              await showAppSheet<DateTimeRange>(
                context: context,
                builder: (_) => AppDateRangeSheet(
                  firstDate: DateTime(2028, 2, 20),
                  lastDate: DateTime(2028, 3, 2),
                  initialDateRange: initial,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _day(WidgetTester tester, int month, int day) async {
  final cell = find.byKey(ValueKey('calendar-day-2028-$month-$day'));
  await tester.scrollUntilVisible(
    cell,
    200,
    scrollable: find.descendant(
      of: find.byKey(const Key('date-range-calendar')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(cell);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'calendar drag expands the sheet and ranges cross a leap-day month boundary',
    (tester) async {
      DateTimeRange? selected;
      await _openCalendar(tester, onClosed: (value) => selected = value);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('use-calendar-dates')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<InkWell>(
              find.byKey(const ValueKey('calendar-day-2028-2-19')),
            )
            .onTap,
        isNull,
      );
      await tester.drag(
        find.byKey(const Key('date-range-calendar')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const Key('app-sheet'))).dy,
        closeTo(0, 1),
      );
      await _day(tester, 2, 28);
      await _day(tester, 2, 27); // Earlier selection becomes the new start.
      await _day(tester, 3, 1);
      expect(
        tester
            .widget<InkWell>(
              find.byKey(const ValueKey('calendar-day-2028-3-3')),
            )
            .onTap,
        isNull,
      );
      await tester.tap(find.byKey(const Key('use-calendar-dates')));
      await tester.pumpAndSettle();
      expect(
        selected,
        DateTimeRange(start: DateTime(2028, 2, 27), end: DateTime(2028, 3, 1)),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clearing a range permits choosing just one day', (tester) async {
    DateTimeRange? selected;
    await _openCalendar(
      tester,
      initial: DateTimeRange(
        start: DateTime(2028, 2, 27),
        end: DateTime(2028, 3, 1),
      ),
      onClosed: (value) => selected = value,
    );
    await tester.tap(find.byKey(const Key('clear-calendar-dates')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('use-calendar-dates')))
          .onPressed,
      isNull,
    );
    await tester.drag(
      find.byKey(const Key('app-sheet-header')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await _day(tester, 2, 29);
    await tester.tap(find.byKey(const Key('use-calendar-dates')));
    await tester.pumpAndSettle();
    expect(
      selected,
      DateTimeRange(start: DateTime(2028, 2, 29), end: DateTime(2028, 2, 29)),
    );
  });
}
