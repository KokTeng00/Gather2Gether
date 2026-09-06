import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/media/app_image_picker.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/events/presentation/create_event_screen.dart';
import 'package:gather2gether/features/forum/presentation/create_forum_post_screen.dart';

class _ImagePicker implements AppImagePicker {
  @override
  Future<PreparedImage?> pickImage(AppImageSource source) async => null;

  @override
  Future<PreparedImage?> recoverLostImage() async => null;
}

Future<void> _openSheet(
  WidgetTester tester,
  WidgetBuilder builder, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              const Text('Page behind sheet'),
              TextButton(
                onPressed: () =>
                    showAppSheet<void>(context: context, builder: builder),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final event in [true, false]) {
    testWidgets(
      '${event ? 'event' : 'discussion'} form keeps edits while resizing and scrolling',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await _openSheet(
          tester,
          (context) => event
              ? CreateEventScreen(
                  asSheet: true,
                  onCreated: () => Navigator.pop(context),
                )
              : CreateForumPostScreen(
                  asSheet: true,
                  imagePicker: _ImagePicker(),
                ),
          theme: event ? AppTheme.light : AppTheme.dark,
        );
        final sheet = find.byKey(const Key('app-sheet'));
        final header = find.byKey(const Key('app-sheet-header'));
        expect(tester.getTopLeft(sheet).dy, closeTo(844 * 0.4, 1));
        expect(find.text('Page behind sheet'), findsOneWidget);
        expect(find.byTooltip('Close'), findsNothing);

        final title = find.widgetWithText(
          TextFormField,
          event ? 'Event title' : 'Give it a clear title',
        );
        await tester.ensureVisible(title);
        await tester.enterText(title, 'An evening together');
        tester.view.viewInsets = const FakeViewPadding(bottom: 330);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(sheet).dy, closeTo(0, 1));
        expect(tester.getBottomRight(sheet).dy, closeTo(514, 1));
        expect(tester.takeException(), isNull);
        FocusManager.instance.primaryFocus?.unfocus();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();

        await tester.drag(header, const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(sheet).dy, closeTo(844 * 0.4, 1));
        expect(
          tester.widget<TextFormField>(title).controller!.text,
          'An evening together',
        );
        await tester.drag(header, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(sheet).dy, closeTo(0, 1));

        final publish = event
            ? find.byKey(const Key('publish-event-button'))
            : find.byKey(const Key('publish-discussion-button'));
        await tester.scrollUntilVisible(
          publish,
          300,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(publish.hitTestable(), findsOneWidget);
        await tester.drag(header, const Offset(0, 300));
        await tester.pumpAndSettle();
        await tester.drag(header, const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(find.text('Page behind sheet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a busy sheet blocks drag, outside tap, and back dismissal', (
    tester,
  ) async {
    final busy = ValueNotifier(true);
    addTearDown(busy.dispose);
    await _openSheet(
      tester,
      (_) => ValueListenableBuilder(
        valueListenable: busy,
        builder: (context, submitting, _) => AppSheetScaffold(
          title: 'Publishing',
          canDismiss: !submitting,
          bodyBuilder: (_, scroll) => ListView(
            controller: scroll,
            children: const [Text('Saving the form')],
          ),
        ),
      ),
    );
    final sheet = find.byKey(const Key('app-sheet'));
    final header = find.byKey(const Key('app-sheet-header'));
    await tester.tapAt(const Offset(300, 80));
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    await tester.drag(header, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    busy.value = false;
    await tester.pumpAndSettle();
    await tester.drag(header, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
