import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/profile_connection.dart';
import 'package:gather2gether/features/profile/presentation/public_profile_screen.dart';

Future<void> showProfileConnectionsSheet({
  required BuildContext context,
  required ProfileConnectionKind kind,
  required ProfileRepository repository,
  String? profileId,
  int? initialCount,
}) => showAppSheet<void>(
  context: context,
  builder: (_) => _ProfileConnectionsSheet(
    kind: kind,
    repository: repository,
    profileId: profileId,
    initialCount: initialCount,
  ),
);

class _ProfileConnectionsSheet extends StatefulWidget {
  const _ProfileConnectionsSheet({
    required this.kind,
    required this.repository,
    this.profileId,
    this.initialCount,
  });
  final ProfileConnectionKind kind;
  final ProfileRepository repository;

  /// Null opens the authenticated account's list.
  final String? profileId;
  final int? initialCount;

  @override
  State<_ProfileConnectionsSheet> createState() =>
      _ProfileConnectionsSheetState();
}

class _ProfileConnectionsSheetState extends State<_ProfileConnectionsSheet> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final List<ProfileConnection> _members = [];
  Timer? _debounce;
  String _query = '';
  String? _nextCursor;
  String? _error;
  bool _canSearch = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _knownEmpty = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _knownEmpty = widget.initialCount == 0;
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _reload() {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _loading = !_knownEmpty || _query.isNotEmpty;
      _loadingMore = false;
      _error = null;
      _nextCursor = null;
      _members.clear();
    });
    return _loadFirst(generation);
  }

  void _searchChanged(String value) {
    _query = value.trim();
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _members.clear();
      _loading = true;
      _loadingMore = false;
      _error = null;
      _nextCursor = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadFirst(generation),
    );
  }

  Future<void> _loadFirst(int generation) async {
    try {
      final page = await widget.repository.fetchConnections(
        profileId: widget.profileId,
        kind: widget.kind,
        query: _canSearch ? _query : '',
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _members.addAll(page.members);
        _nextCursor = page.nextCursor;
        _canSearch = page.canSearch;
        if (_query.isEmpty) _knownEmpty = page.members.isEmpty;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        // Preserve a confirmed empty list if its background refresh fails.
        _error = _knownEmpty && _query.isEmpty
            ? null
            : 'Could not load ${widget.kind.label.toLowerCase()}. Please try again.';
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (_loading || _loadingMore || cursor == null || _error != null) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.repository.fetchConnections(
        profileId: widget.profileId,
        kind: widget.kind,
        query: _canSearch ? _query : '',
        cursor: cursor,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final existing = _members.map((member) => member.id).toSet();
        _members.addAll(
          page.members.where((member) => existing.add(member.id)),
        );
        _nextCursor = page.nextCursor == cursor ? null : page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _error = 'Could not load more people.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetScaffold(
      title: widget.kind.label,
      bodyBuilder: (context, scrollController) => Column(
        children: [
          if (_canSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: TextField(
                key: const Key('connections-search'),
                controller: _search,
                focusNode: _searchFocus,
                maxLength: 80,
                autocorrect: false,
                onChanged: _searchChanged,
                decoration: InputDecoration(
                  hintText: 'Name or username',
                  counterText: '',
                  prefixIcon: const Icon(CupertinoIcons.search, size: 20),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _search.clear();
                            _searchChanged('');
                          },
                          icon: const Icon(
                            CupertinoIcons.xmark_circle_fill,
                            size: 18,
                          ),
                        ),
                ),
              ),
            ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.depth == 0 &&
                    notification.metrics.extentAfter < 240) {
                  _loadMore();
                }
                return false;
              },
              child: RefreshIndicator.adaptive(
                onRefresh: _reload,
                child: CustomScrollView(
                  key: const Key('connections-list'),
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    if (_loading || _members.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _loading
                            ? const Center(
                                child: CircularProgressIndicator.adaptive(),
                              )
                            : _buildEmptyState(context),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          4,
                          20,
                          16 + MediaQuery.paddingOf(context).bottom,
                        ),
                        sliver: SliverList.separated(
                          itemCount: _members.length + 1,
                          separatorBuilder: (_, index) =>
                              index < _members.length - 1
                              ? const Divider(height: 1, indent: 62)
                              : const SizedBox.shrink(),
                          itemBuilder: (context, index) =>
                              index == _members.length
                              ? _buildFooter()
                              : _buildMember(context, _members[index]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _query.isNotEmpty
                  ? CupertinoIcons.search
                  : CupertinoIcons.person_2,
              size: 28,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _error ??
                  (_query.isNotEmpty
                      ? 'No people found'
                      : widget.kind == ProfileConnectionKind.followers
                      ? 'No followers yet'
                      : 'Not following anyone yet'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: _reload, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (_error != null) {
      return TextButton(
        onPressed: () {
          setState(() => _error = null);
          _loadMore();
        },
        child: Text('$_error Try again'),
      );
    }
    if (_nextCursor != null) {
      return TextButton(onPressed: _loadMore, child: const Text('Load more'));
    }
    return const SizedBox.shrink();
  }

  Widget _buildMember(BuildContext context, ProfileConnection member) {
    final theme = Theme.of(context);
    final initial = member.displayName.trim().characters.firstOrNull ?? '?';
    final fallback = Center(
      child: Text(
        initial.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.onPrimaryContainer,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return ListTile(
      key: ValueKey('connection-${member.id}'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: ClipOval(
        child: Container(
          width: 46,
          height: 46,
          color: theme.colorScheme.primaryContainer,
          child: member.hasAvatar
              ? Image.network(
                  widget.repository.connectionAvatarUrl(member),
                  headers: widget.repository.publicMediaHeaders(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                )
              : fallback,
        ),
      ),
      title: Text(
        member.displayName,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: member.username.isEmpty
          ? null
          : Text(
              '@${member.username}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Icon(
        CupertinoIcons.chevron_right,
        size: 16,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PublicProfileScreen(
            profileId: member.id,
            repository: widget.repository,
          ),
        ),
      ),
    );
  }
}
