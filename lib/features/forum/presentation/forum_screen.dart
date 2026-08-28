import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/forum/presentation/create_forum_post_screen.dart';
import 'package:gather2gether/features/forum/presentation/forum_format.dart';
import 'package:gather2gether/features/forum/presentation/forum_post_screen.dart';

class ForumScreen extends StatefulWidget {
  const ForumScreen({super.key});

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  final _repository = ForumRepository();
  List<ForumPost> _posts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final posts = await _repository.listPosts();
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
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CreateForumPostScreen(),
      ),
    );
    if (id == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ForumPostScreen(postId: id)),
    );
    await _load();
  }

  Future<void> _open(ForumPost post) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ForumPostScreen(postId: post.id)),
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
                  actions: [
                    AppCircleButton(
                      icon: CupertinoIcons.square_pencil,
                      tooltip: 'New discussion',
                      filled: true,
                      onPressed: _create,
                    ),
                  ],
                ),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 22),
              sliver: SliverToBoxAdapter(child: _CommunityBanner()),
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
                  action: 'New Discussion',
                  onPressed: _create,
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Latest',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                sliver: SliverList.separated(
                  itemCount: _posts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => _PostRow(
                    post: _posts[index],
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

class _CommunityBanner extends StatelessWidget {
  const _CommunityBanner();

  @override
  Widget build(BuildContext context) => Container(
    height: 132,
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF5E5CE6), Color(0xFF0A84FF)],
      ),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -4,
          bottom: -20,
          child: Icon(
            CupertinoIcons.chat_bubble_2_fill,
            size: 118,
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(CupertinoIcons.person_3_fill, color: Colors.white, size: 24),
            SizedBox(height: 10),
            Text(
              'A space for good neighbours',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'Be kind · Keep personal details private',
              style: TextStyle(color: Color(0xDFFFFFFF), fontSize: 13),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PostRow extends StatelessWidget {
  const _PostRow({required this.post, required this.onTap});

  final ForumPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = CategoryVisual.forName(post.category);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: visual.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: visual.ink.withValues(alpha: 0.18)),
                ),
                child: Icon(visual.icon, color: visual.ink, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            post.category,
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          forumTimeAgo(post.lastActivityAt),
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            post.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (post.isLocked)
                          const Padding(
                            padding: EdgeInsets.only(left: 5),
                            child: Icon(CupertinoIcons.lock_fill, size: 14),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${post.authorName}  ·  ${post.commentCount} ${post.commentCount == 1 ? 'reply' : 'replies'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.tonal(onPressed: onPressed, child: Text(action)),
        ],
      ),
    ),
  );
}
