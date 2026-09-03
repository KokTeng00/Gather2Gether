import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_comment.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/forum/presentation/forum_post_screen.dart';

void main() {
  testWidgets('a member can like a discussion from its detail page', (
    tester,
  ) async {
    final repository = _ForumRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ForumPostScreen(
          postId: repository.post.id,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0 likes'), findsOneWidget);

    await tester.tap(find.byKey(const Key('forum-like-action')));
    await tester.pumpAndSettle();

    expect(repository.requestedLike, isTrue);
    expect(find.text('1 like'), findsOneWidget);
    expect(find.byIcon(Icons.error), findsNothing);
  });
}

class _ForumRepository extends ForumRepository {
  _ForumRepository()
    : super(
        accessTokenProvider: () => 'test-token',
        edgeApiUrl: 'https://example.test/api/v1',
      );

  final post = ForumPost(
    id: '33333333-3333-4333-8333-333333333333',
    authorId: '11111111-1111-4111-8111-111111111111',
    authorName: 'Alex',
    category: 'Local tips',
    title: 'A quiet place to read',
    body: 'The garden beside the library has shaded benches.',
    status: 'active',
    createdAt: DateTime(2026, 9, 1),
    lastActivityAt: DateTime(2026, 9, 1),
    commentCount: 0,
    viewerIsAuthor: false,
  );

  bool? requestedLike;

  @override
  Future<ForumPost> getPost(String postId) async => post;

  @override
  Future<List<ForumComment>> listComments(String postId) async => const [];

  @override
  Future<ForumLikeState> setPostLike({
    required String postId,
    required bool liked,
  }) async {
    requestedLike = liked;
    return ForumLikeState(liked: liked, likeCount: liked ? 1 : 0);
  }
}
