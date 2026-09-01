import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/forum/presentation/forum_post_attachments.dart';
import 'package:gather2gether/features/forum/presentation/forum_post_screen.dart';

/// The signed-in member's community posts, presented as a compact media grid.
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
      child: GridView.builder(
        key: const Key('profile-activity-grid'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _posts.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
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
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        children: [
          for (var index = 0; index < 6; index++)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(
                  colors.surfaceContainerHighest,
                  colors.surface,
                  index.isEven ? 0.1 : 0.28,
                ),
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 42, 28, 46),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.55),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: colors.primary, size: 27),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: onAction,
              icon: const Icon(CupertinoIcons.refresh, size: 17),
              label: Text(actionLabel!),
            ),
          ],
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
      child: Material(
        color: visual.background,
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (post.hasImage)
                ForumPostImage(
                  postId: post.id,
                  title: post.title,
                  repository: repository,
                  aspectRatio: 1,
                  borderRadius: 0,
                )
              else ...[
                Positioned(
                  right: -12,
                  top: -10,
                  child: Icon(
                    visual.icon,
                    color: visual.ink.withValues(alpha: 0.12),
                    size: 72,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(visual.icon, color: visual.ink, size: 18),
                      const Spacer(),
                      Text(
                        post.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: visual.ink,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (post.hasPlace)
                Positioned(
                  top: 7,
                  left: 7,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: post.hasImage
                          ? const Color(0xB8000000)
                          : visual.ink.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.location_fill,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (post.isLocked)
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: post.hasImage
                          ? const Color(0xB8000000)
                          : visual.ink.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.lock_fill,
                      color: Colors.white,
                      size: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
