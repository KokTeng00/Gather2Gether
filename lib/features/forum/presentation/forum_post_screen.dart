import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/constants/forum_constants.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_comment.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/forum/presentation/forum_format.dart';
import 'package:gather2gether/features/forum/presentation/forum_post_attachments.dart';
import 'package:gather2gether/features/profile/presentation/public_profile_screen.dart';

class ForumPostScreen extends StatefulWidget {
  const ForumPostScreen({
    required this.postId,
    super.key,
    ForumRepository? repository,
  }) : _repository = repository;

  final String postId;
  final ForumRepository? _repository;

  @override
  State<ForumPostScreen> createState() => _ForumPostScreenState();
}

class _ForumPostScreenState extends State<ForumPostScreen> {
  late final ForumRepository _repository;
  final _comment = TextEditingController();
  ForumPost? _post;
  List<ForumComment> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? ForumRepository();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([
        _repository.getPost(widget.postId),
        _repository.listComments(widget.postId),
      ]);
      if (mounted) {
        setState(() {
          _post = values[0] as ForumPost;
          _comments = values[1] as List<ForumComment>;
        });
      }
    } on ForumApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Could not load this discussion.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAuthor(ForumPost post) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PublicProfileScreen(profileId: post.authorId),
    ),
  );

  Future<void> _sendComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty || body.length > 1200) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      await _repository.createComment(postId: widget.postId, body: body);
      _comment.clear();
      await _load();
    } on ForumApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not add your reply. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reportPost() async {
    final reason = await _chooseReportReason();
    if (reason == null) return;
    try {
      await _repository.reportPost(widget.postId, reason);
      if (mounted) {
        _showMessage('Thank you. The discussion was reported for review.');
      }
    } on ForumApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _reportComment(ForumComment comment) async {
    final reason = await _chooseReportReason();
    if (reason == null) return;
    try {
      await _repository.reportComment(comment.id, reason);
      if (mounted) {
        _showMessage('Thank you. The reply was reported for review.');
      }
    } on ForumApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<String?> _chooseReportReason() => showCupertinoModalPopup<String>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      title: const Text('Report Content'),
      message: const Text('Choose the reason that best describes the problem.'),
      actions: [
        for (final entry in forumReportReasons.entries)
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(entry.key),
            child: Text(entry.value),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ),
  );

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discussion'),
        actions: [
          if (post != null && !post.viewerIsAuthor)
            IconButton(
              tooltip: 'Report discussion',
              onPressed: _reportPost,
              icon: const Icon(CupertinoIcons.ellipsis_circle),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator.adaptive(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                children: [
                  _PostHeader(
                    post: post!,
                    repository: _repository,
                    onAuthorTap: () => _openAuthor(post),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Text(
                        '${_comments.length} ${_comments.length == 1 ? 'reply' : 'replies'}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      if (post.isLocked)
                        const Row(
                          children: [
                            Icon(CupertinoIcons.lock_fill, size: 15),
                            SizedBox(width: 5),
                            Text('Locked'),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_comments.isEmpty)
                    const _NoReplies()
                  else
                    for (final comment in _comments) ...[
                      _CommentCard(
                        comment: comment,
                        onReport: comment.viewerIsAuthor
                            ? null
                            : () => _reportComment(comment),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
      bottomNavigationBar: post != null && !post.isLocked && _error == null
          ? _CommentComposer(
              controller: _comment,
              sending: _sending,
              onSend: _sendComment,
            )
          : null,
    );
  }
}

class _PostHeader extends StatelessWidget {
  const _PostHeader({
    required this.post,
    required this.repository,
    required this.onAuthorTap,
  });

  final ForumPost post;
  final ForumRepository repository;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppHeroArt(
          label: post.category,
          title: post.title,
          subtitle: '${post.authorName} · ${forumTimeAgo(post.createdAt)}',
          height: 210,
        ),
        if (post.hasImage) ...[
          const SizedBox(height: 14),
          ForumPostImage(
            postId: post.id,
            title: post.title,
            repository: repository,
          ),
        ],
        const SizedBox(height: 14),
        AppSurface(
          borderRadius: 18,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(post.body, style: Theme.of(context).textTheme.bodyLarge),
              if (post.hasPlace) ...[
                const SizedBox(height: 18),
                ForumPlaceCard(
                  name: post.placeName!,
                  address: post.placeAddress!,
                ),
              ],
              const SizedBox(height: 18),
              InkWell(
                key: const Key('forum-author-profile'),
                borderRadius: BorderRadius.circular(14),
                onTap: onAuthorTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: colors.primaryContainer,
                        child: Text(
                          post.authorName.isEmpty
                              ? '?'
                              : post.authorName.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          post.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (post.viewerIsAuthor) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'You',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.onSecondaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ] else
                        Icon(
                          CupertinoIcons.chevron_forward,
                          size: 14,
                          color: colors.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.comment, required this.onReport});

  final ForumComment comment;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  comment.viewerIsAuthor
                      ? '${comment.authorName} · You'
                      : comment.authorName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                forumTimeAgo(comment.createdAt),
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
              if (onReport != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Report reply',
                  onPressed: onReport,
                  icon: const Icon(CupertinoIcons.ellipsis, size: 20),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(comment.body, style: const TextStyle(height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return FrostedContainer(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !sending,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1200,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Write a respectful reply…',
                    counterText: '',
                    isDense: true,
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send reply',
                onPressed: sending ? null : onSend,
                icon: sending
                    ? SizedBox.square(
                        dimension: 18,
                        child: CupertinoActivityIndicator(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(CupertinoIcons.arrow_up),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoReplies extends StatelessWidget {
  const _NoReplies();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Text(
        'No replies yet. Be the first to help.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 46),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
