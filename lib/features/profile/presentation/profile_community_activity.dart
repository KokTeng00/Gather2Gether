import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/forum/presentation/forum_post_attachments.dart';
import 'package:gather2gether/features/forum/presentation/forum_post_screen.dart';

/// The signed-in member's community posts, presented as readable updates.
class ProfileCommunityActivity extends StatefulWidget {
  const ProfileCommunityActivity({this.repository, super.key});

  final ForumRepository? repository;

  @override
  State<ProfileCommunityActivity> createState() =>
      _ProfileCommunityActivityState();
}

class _ProfileCommunityActivityState extends State<ProfileCommunityActivity> {
  late ForumRepository _repository;
  List<ForumPost> _posts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ForumRepository();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileCommunityActivity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository == widget.repository) return;
    _repository = widget.repository ?? ForumRepository();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final posts = await _repository.listOwnPosts();
      if (!mounted) return;
      setState(() => _posts = posts);
    } on ForumApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Your community posts are unavailable.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPost(ForumPost post) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ForumPostScreen(postId: post.id, repository: _repository),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ActivityLoading();
    if (_error != null) {
      return _ActivityMessage(
        key: const Key('profile-activity-error'),
        icon: CupertinoIcons.exclamationmark_triangle,
        title: 'Couldn’t load your posts',
        message: _error!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    if (_posts.isEmpty) {
      return const _ActivityMessage(
        key: Key('profile-activity-empty'),
        icon: CupertinoIcons.photo_on_rectangle,
        title: 'No community posts yet',
        message:
            'Photos, places, and ideas you share will collect here on your profile.',
      );
    }

    return Semantics(
      label: '${_posts.length} community posts',
      child: ListView.separated(
        key: const Key('profile-activity-list'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _posts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final post = _posts[index];
          return _ActivityTile(
            key: ValueKey('profile-post-${post.id}'),
            post: post,
            repository: _repository,
            onTap: () => _openPost(post),
          );
        },
      ),
    );
  }
}

class _ActivityLoading extends StatelessWidget {
  const _ActivityLoading();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: const Key('profile-activity-loading'),
      label: 'Loading your community posts',
      child: Column(
        children: [
          for (var index = 0; index < 3; index++) ...[
            AppSurface(
              borderRadius: 18,
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                height: 58,
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 86,
                            height: 10,
                            color: colors.surfaceContainerHighest,
                          ),
                          const SizedBox(height: 9),
                          Container(
                            height: 13,
                            color: Color.lerp(
                              colors.surfaceContainerHighest,
                              colors.surface,
                              0.16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (index != 2) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ActivityMessage extends StatelessWidget {
  const _ActivityMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      borderRadius: 18,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: colors.onPrimaryContainer, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: onAction,
                    icon: const Icon(CupertinoIcons.refresh, size: 16),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.post,
    required this.repository,
    required this.onTap,
    super.key,
  });

  final ForumPost post;
  final ForumRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = CategoryVisual.resolve(context, post.category);
    return Semantics(
      button: true,
      label: 'Open community post: ${post.title}',
      child: AppSurface(
        borderRadius: 18,
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            if (!post.hasImage) ...[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: visual.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(visual.icon, color: visual.ink, size: 21),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: visual.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      _PostMeta(
                        icon: CupertinoIcons.chat_bubble,
                        label:
                            '${post.commentCount} ${post.commentCount == 1 ? 'reply' : 'replies'}',
                      ),
                      if (post.hasPlace)
                        _PostMeta(
                          icon: CupertinoIcons.location,
                          label: post.placeName!,
                        ),
                      if (post.isLocked)
                        const _PostMeta(
                          icon: CupertinoIcons.lock,
                          label: 'Closed',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (post.hasImage)
              SizedBox(
                width: 100,
                child: ForumPostImage(
                  postId: post.id,
                  title: post.title,
                  repository: repository,
                  aspectRatio: 1,
                  borderRadius: 14,
                ),
              )
            else
              Icon(
                CupertinoIcons.chevron_right,
                size: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class _PostMeta extends StatelessWidget {
  const _PostMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
