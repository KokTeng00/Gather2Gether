import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/media/app_image_picker.dart';
import 'package:gather2gether/core/media/prepared_image.dart';
import 'package:gather2gether/features/forum/presentation/create_forum_post_screen.dart';

void main() {
  testWidgets('photo can be chosen, previewed, changed, and removed', (
    tester,
  ) async {
    final picker = _FakeImagePicker(_testImage());
    await tester.pumpWidget(
      MaterialApp(home: CreateForumPostScreen(imagePicker: picker)),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('forum-add-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-add-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-photo-gallery')));
    await tester.pumpAndSettle();

    expect(picker.sources, [AppImageSource.gallery]);
    expect(find.byKey(const Key('forum-photo-preview')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('forum-change-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-change-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-photo-camera')));
    await tester.pumpAndSettle();

    expect(picker.sources, [AppImageSource.gallery, AppImageSource.camera]);

    await tester.ensureVisible(find.byKey(const Key('forum-remove-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-remove-photo')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-photo-preview')), findsNothing);
    expect(find.byKey(const Key('forum-add-photo')), findsOneWidget);
  });

  testWidgets('public place sheet validates, saves, edits, and removes a tag', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CreateForumPostScreen(imagePicker: _FakeImagePicker())),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('forum-add-place')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-add-place')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Never tag a home address'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('forum-save-place')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-save-place')));
    await tester.pump();
    expect(find.text('Use at least 2 characters.'), findsOneWidget);
    expect(find.text('Use at least 3 characters.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('forum-place-name')),
      'Community Garden',
    );
    await tester.enterText(
      find.byKey(const Key('forum-place-address')),
      '12 Linden Street, Berlin',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-selected-place')), findsOneWidget);
    expect(find.text('Community Garden'), findsOneWidget);
    expect(find.text('12 Linden Street, Berlin'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('forum-edit-place')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-edit-place')));
    await tester.pumpAndSettle();
    expect(find.text('Edit public place'), findsOneWidget);
    final nameField = tester.widget<TextFormField>(
      find.byKey(const Key('forum-place-name')),
    );
    expect(nameField.controller?.text, 'Community Garden');
    await tester.enterText(
      find.byKey(const Key('forum-place-name')),
      'Riverside Garden',
    );
    await tester.ensureVisible(find.byKey(const Key('forum-save-place')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-save-place')));
    await tester.pumpAndSettle();
    expect(find.text('Riverside Garden'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('forum-remove-place')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-remove-place')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('forum-selected-place')), findsNothing);
    expect(find.byKey(const Key('forum-add-place')), findsOneWidget);
  });
}

PreparedImage _testImage() => PreparedImage(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

class _FakeImagePicker implements AppImagePicker {
  _FakeImagePicker([this.image]);

  final PreparedImage? image;
  final List<AppImageSource> sources = [];

  @override
  Future<PreparedImage?> pickImage(AppImageSource source) async {
    sources.add(source);
    return image;
  }

  @override
  Future<PreparedImage?> recoverLostImage() async => null;
}
