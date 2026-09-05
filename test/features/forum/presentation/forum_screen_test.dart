import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/forum/presentation/forum_screen.dart';

class _ForumRepository extends ForumRepository {
  _ForumRepository(this.posts);

  final List<ForumPost> posts;

  @override
  Future<List<ForumPost>> listPosts() async => posts;
}

void main() {
  testWidgets('empty community keeps one clear creation action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ForumScreen(repository: _ForumRepository(const [])),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Neighbourhood notes'), findsNothing);
    expect(find.byTooltip('New discussion'), findsNothing);
    expect(find.text('Start the conversation'), findsOneWidget);
    expect(find.text('New discussion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('populated community has one labelled creation action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime(2026, 9, 2);
    final post = ForumPost(
      id: 'post-1',
      authorId: 'member-1',
      authorName: 'Neighbour',
      category: 'General',
      title: 'A simple community post',
      body: 'A short message for nearby people.',
      status: 'active',
      createdAt: now,
      lastActivityAt: now,
      commentCount: 0,
      viewerIsAuthor: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ForumScreen(repository: _ForumRepository([post]))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-discussion-action')), findsOneWidget);
    expect(find.byTooltip('New discussion'), findsOneWidget);
    expect(find.text('New discussion'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
