import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/forum/presentation/create_forum_post_screen.dart';
import 'package:gather2gether/features/forum/presentation/forum_format.dart';
import 'package:gather2gether/features/forum/presentation/forum_post_attachments.dart';
import 'package:gather2gether/features/forum/presentation/forum_post_screen.dart';

class ForumScreen extends StatefulWidget {
  const ForumScreen({super.key, ForumRepository? repository})
    : _repository = repository;

  final ForumRepository? _repository;

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  late final ForumRepository _repository;
  final _interestController = TextEditingController();
  List<ForumPost> _posts = const [];
  bool _loading = true;
  String? _error;
  String? _interest;

  @override
  void dispose() {
    _interestController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _repository = widget._repository ?? ForumRepository();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final posts = _interest == null
          ? await _repository.listPosts()
          : await _repository.searchPosts(_interest!);
      if (mounted) {
        setState(() {
          _posts = posts;
          _error = null;
        });
      }
    } on ForumApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Community discussions are temporarily unavailable.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final id = await showAppSheet<String>(
      context: context,
      builder: (_) =>
          CreateForumPostScreen(repository: _repository, asSheet: true),
    );
    if (id == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ForumPostScreen(postId: id, repository: _repository),
      ),
    );
    await _load();
  }

  Future<void> _applyInterest(String value) async {
    final normalized = value.trim();
    setState(() => _interest = normalized.isEmpty ? null : normalized);
    FocusScope.of(context).unfocus();
    await _load();
  }

  void _clearInterest() {
    _interestController.clear();
    _applyInterest('');
  }

  Future<void> _open(ForumPost post) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ForumPostScreen(postId: post.id, repository: _repository),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              sliver: SliverToBoxAdapter(
                child: AppPageHeader(
                  title: 'Community',
                  subtitle: 'Ask, share, and make local connections.',
                  actions: _posts.isEmpty
                      ? const []
                      : [
                          AppCircleButton(
                            key: const Key('new-discussion-action'),
                            icon: CupertinoIcons.square_pencil,
                            tooltip: 'New discussion',
                            onPressed: _create,
                          ),
                        ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              sliver: SliverToBoxAdapter(
                child: AppInterestSearch(
                  key: const Key('forum-interest-search'),
                  controller: _interestController,
                  enabled: !_loading,
                  hintText: 'Search discussions',
                  onSubmitted: _applyInterest,
                  onClear: _clearInterest,
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CupertinoActivityIndicator(radius: 14)),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ForumMessage(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  title: 'Couldn’t load discussions',
                  message: _error!,
                  action: 'Try Again',
                  onPressed: _load,
                ),
              )
            else if (_posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ForumMessage(
                  icon: CupertinoIcons.chat_bubble_2,
                  title: 'Start the conversation',
                  message:
                      'Ask a question or share an idea with people nearby.',
                  action: 'New discussion',
                  onPressed: _create,
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverList.separated(
                  itemCount: _posts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, index) => _PostRow(
                    post: _posts[index],
                    repository: _repository,
                    onTap: () => _open(_posts[index]),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  const _PostRow({
    required this.post,
    required this.repository,
    required this.onTap,
  });

  final ForumPost post;
  final ForumRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = CategoryVisual.resolve(context, post.category);
    final colors = Theme.of(context).colorScheme;
    return AppSurface(
      onTap: onTap,
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: visual.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: visual.ink.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(visual.icon, color: visual.ink, size: 14),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            post.hasPoll
                                ? '${post.category} · Date poll'
                                : post.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: visual.ink,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (post.isLocked) ...[
                Tooltip(
                  message: 'Discussion locked',
                  child: Icon(
                    CupertinoIcons.lock_fill,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                forumTimeAgo(post.lastActivityAt),
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          if (post.hasImage) ...[
            const SizedBox(height: 12),
            ForumPostImage(
              postId: post.id,
              title: post.title,
              repository: repository,
              aspectRatio: 16 / 9,
              borderRadius: 14,
            ),
          ],
          const SizedBox(height: 12),
          Text(
            post.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            post.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (post.hasPlace) ...[
            const SizedBox(height: 11),
            ForumPlaceCard(
              name: post.placeName!,
              address: post.placeAddress!,
              compact: true,
            ),
          ],
          const SizedBox(height: 13),
          Row(
            children: [
              Icon(
                CupertinoIcons.person_crop_circle,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  post.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chat_bubble,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                '${post.commentCount}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 14,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ForumMessage extends StatelessWidget {
  const _ForumMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 28, color: colors.onPrimaryContainer),
            ),
            const SizedBox(height: 17),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: onPressed, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
