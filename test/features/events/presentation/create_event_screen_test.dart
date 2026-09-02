import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/events/presentation/create_event_screen.dart';

void main() {
  testWidgets('event category uses the simple app choice sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CreateEventScreen(onCreated: () {})),
    );
    await tester.pump();

    expect(find.byKey(const Key('event-category-field')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    await tester.tap(find.byKey(const Key('event-category-field')));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(
      find.byKey(const Key('app-choice-sheet-title')),
    );
    expect(title.data, 'Category');

    await tester.tap(find.byKey(const ValueKey('app-choice-Running')));
    await tester.pumpAndSettle();
    expect(find.text('Running'), findsOneWidget);
  });
}
