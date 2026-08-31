import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/assistant/data/assistant_repository.dart';
import 'package:gather2gether/features/assistant/domain/assistant_message.dart';
import 'package:gather2gether/features/assistant/presentation/assistant_panel.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/shell/presentation/app_shell.dart';

void main() {
  group('assistant launcher docking', () {
    const area = Size(400, 800);
    const safeInsets = EdgeInsets.only(top: 44, bottom: 34);

    test('snaps a middle position to the nearest screen edge', () {
      final position = dockAssistantOffset(
        const Offset(200, 400),
        area: area,
        safeInsets: safeInsets,
      );

      expect(position, const Offset(339, 400));
    });

    test('keeps the launcher inside safe screen bounds', () {
      final position = clampAssistantOffset(
        const Offset(-100, 900),
        area: area,
        safeInsets: safeInsets,
      );

      expect(position, const Offset(5, 705));
    });

    test('can dock to the top edge when that is closest', () {
      final position = dockAssistantOffset(
        const Offset(180, 60),
        area: area,
        safeInsets: safeInsets,
      );

      expect(position, const Offset(180, 49));
    });
  });

  test('assistant formatting renders emphasis and bullets without markers', () {
    final span = buildAssistantTextSpan(
      'Choose **Join** when you are ready.\n- Bring water',
      const TextStyle(fontSize: 15),
    );

    expect(
      span.toPlainText(),
      'Choose Join when you are ready.\n• Bring water',
    );
    final boldSpan = span.children!.whereType<TextSpan>().firstWhere(
      (child) => child.text == 'Join',
    );
    expect(boldSpan.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('conversation stays usable on a compact phone screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AssistantPanel(
            profile: const UserProfile(
              displayName: 'Taylor',
              city: 'Berlin',
              preferredRadiusKm: 10,
              approximateLatitude: 52.52,
              approximateLongitude: 13.4,
              assistantEnabled: true,
            ),
            repository: _PreviewAssistantRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gather Guide'), findsWidgets);
    expect(find.text('How do I join an event?'), findsOneWidget);
    expect(find.text('Message Gather Guide…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _PreviewAssistantRepository extends AssistantRepository {
  @override
  Future<List<AssistantMessage>> history() async => [
    AssistantMessage(
      id: 1,
      role: 'user',
      content: 'How do I join an event?',
      createdAt: DateTime(2026, 8, 28, 16, 9),
    ),
    AssistantMessage(
      id: 2,
      role: 'assistant',
      content:
          'Open the event details, then choose **Join** or **Tentative** to save your spot.',
      createdAt: DateTime(2026, 8, 28, 16, 9),
    ),
  ];
}
