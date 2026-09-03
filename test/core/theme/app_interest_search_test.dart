import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';

void main() {
  testWidgets('interest search uses conventional search controls', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    String? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 60,
            child: AppInterestSearch(
              controller: controller,
              onSubmitted: (value) => submitted = value,
              onClear: controller.clear,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(CupertinoIcons.search), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.sparkles), findsNothing);
    expect(find.text('Search'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('interest-search-field')),
      'outdoor yoga',
    );
    await tester.tap(find.byKey(const Key('interest-search-submit')));
    expect(submitted, 'outdoor yoga');
  });
}
