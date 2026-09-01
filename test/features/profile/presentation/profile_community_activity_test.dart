import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_comment.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/forum/presentation/forum_post_attachments.dart';
import 'package:gather2gether/features/profile/presentation/profile_community_activity.dart';

void main() {
  testWidgets('shows a three-column own-post grid with authenticated media', (
    tester,
  ) async {
    final pending = Completer<List<ForumPost>>();
    final repository = _FakeForumRepository(pending: pending);
    await _pumpActivity(tester, repository);

    expect(find.byKey(const Key('profile-activity-loading')), findsOneWidget);

    pending.complete([
      _post(id: 'photo-post', title: 'Garden afternoon', hasImage: true),
      _post(id: 'text-post', title: 'Coffee walk'),
      _post(id: 'place-post', title: 'Park notes', hasPlace: true),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-activity-grid')), findsOneWidget);
    expect(find.byType(ForumPostImage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-post-photo-post')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-post-text-post')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-post-place-post')),
      findsOneWidget,
    );

    final first = tester.getRect(
      find.byKey(const ValueKey('profile-post-photo-post')),
    );
    final last = tester.getRect(
      find.byKey(const ValueKey('profile-post-place-post')),
    );
    expect(first.left, 0);
    expect(last.right, closeTo(360, 0.01));
    expect(first.width, closeTo((360 - 4) / 3, 0.01));
  });

  testWidgets('empty and error states remain actionable', (tester) async {
    final repository = _FakeForumRepository(failuresRemaining: 1);
    await _pumpActivity(tester, repository);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-activity-error')), findsOneWidget);
    expect(find.text('Couldn’t load your posts'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(repository.listCalls, 2);
    expect(find.byKey(const Key('profile-activity-empty')), findsOneWidget);
    expect(find.text('No community posts yet'), findsOneWidget);
  });

  testWidgets('tapping a tile opens the full discussion', (tester) async {
    final post = _post(id: 'open-post', title: 'Sunday market finds');
    final repository = _FakeForumRepository(posts: [post]);
    await _pumpActivity(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-post-open-post')));
    await tester.pumpAndSettle();

    expect(find.text('Discussion'), findsOneWidget);
    expect(find.text('Sunday market finds'), findsOneWidget);
  });
}

Future<void> _pumpActivity(
  WidgetTester tester,
  ForumRepository repository,
) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProfileCommunityActivity(repository: repository),
        ),
      ),
    ),
  );
  await tester.pump();
}

ForumPost _post({
  required String id,
  required String title,
  bool hasImage = false,
  bool hasPlace = false,
}) => ForumPost(
  id: id,
  authorId: '11111111-1111-4111-8111-111111111111',
  authorName: 'Maya',
  category: 'Local tips',
  title: title,
  body: 'A useful update for neighbours in the community.',
  status: 'active',
  createdAt: DateTime(2026, 8, 31, 10),
  lastActivityAt: DateTime(2026, 8, 31, 11),
  commentCount: 2,
  viewerIsAuthor: true,
  hasImage: hasImage,
  placeName: hasPlace ? 'Community Garden' : null,
  placeAddress: hasPlace ? '12 Linden Street, Berlin' : null,
);

class _FakeForumRepository extends ForumRepository {
  _FakeForumRepository({
    this.posts = const [],
    this.pending,
    this.failuresRemaining = 0,
  }) : super(
         accessTokenProvider: () => 'access-token',
         edgeApiUrl: 'https://example.test/api/v1',
       );

  final List<ForumPost> posts;
  final Completer<List<ForumPost>>? pending;
  int failuresRemaining;
  int listCalls = 0;

  @override
  Future<List<ForumPost>> listOwnPosts() async {
    listCalls++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const ForumApiException(
        statusCode: 503,
        code: 'database_unavailable',
        message: 'Community is temporarily unavailable.',
      );
    }
    return pending?.future ?? posts;
  }

  @override
  Future<ForumPost> getPost(String postId) async =>
      posts.firstWhere((post) => post.id == postId);

  @override
  Future<List<ForumComment>> listComments(String postId) async => const [];
}
