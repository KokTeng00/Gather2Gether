import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/app.dart';

void main() {
  testWidgets('shows safe configuration guidance without client keys', (
    tester,
  ) async {
    await tester.pumpWidget(const Gather2GetherApp(isConfigured: false));

    expect(find.text('Configuration required'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.textContaining('Never put an admin key'), findsOneWidget);
  });
}
