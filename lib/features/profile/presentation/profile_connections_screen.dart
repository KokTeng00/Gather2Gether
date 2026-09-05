import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/profile_connection.dart';
import 'package:gather2gether/features/profile/presentation/public_profile_screen.dart';

class ProfileConnectionsScreen extends StatefulWidget {
  const ProfileConnectionsScreen({
    required this.kind,
    required this.repository,
    this.profileId,
    super.key,
  });
  final ProfileConnectionKind kind;
  final ProfileRepository repository;

  /// Null opens the authenticated account's list.
  final String? profileId;

  @override
  State<ProfileConnectionsScreen> createState() =>
      _ProfileConnectionsScreenState();
}

class _ProfileConnectionsScreenState extends State<ProfileConnectionsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final List<ProfileConnection> _members = [];
  Timer? _debounce;
  String _query = '';
  String? _nextCursor;
  String? _error;
  bool _canSearch = false;
  bool _loading = true;
  bool _loadingMore = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 240) _loadMore();
  }

  Future<void> _reload() {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _loading = true;
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
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load ${widget.kind.label.toLowerCase()}. Please try again.';
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
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.kind.label)),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              children: [
                if (_canSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: TextField(
                      key: const Key('connections-search'),
                      controller: _search,
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
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : RefreshIndicator.adaptive(
                          onRefresh: _reload,
                          child: _members.isEmpty
                              ? LayoutBuilder(
                                  builder: (context, constraints) => ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    children: [
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: constraints.maxHeight,
                                        ),
                                        child: Center(
                                          child: Padding(
                                            padding: const EdgeInsets.all(32),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  _query.isNotEmpty
                                                      ? CupertinoIcons.search
                                                      : CupertinoIcons.person_2,
                                                  size: 32,
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                                const SizedBox(height: 14),
                                                Text(
                                                  _error ??
                                                      (_query.isNotEmpty
                                                          ? 'No people found'
                                                          : widget.kind ==
                                                                ProfileConnectionKind
                                                                    .followers
                                                          ? 'No followers yet'
                                                          : 'Not following anyone yet'),
                                                  textAlign: TextAlign.center,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleMedium,
                                                ),
                                                if (_error != null) ...[
                                                  const SizedBox(height: 12),
                                                  TextButton(
                                                    onPressed: _reload,
                                                    child: const Text(
                                                      'Try again',
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  controller: _scroll,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    4,
                                    20,
                                    24,
                                  ),
                                  itemCount: _members.length + 1,
                                  separatorBuilder: (_, index) =>
                                      index < _members.length - 1
                                      ? const Divider(height: 1, indent: 62)
                                      : const SizedBox.shrink(),
                                  itemBuilder: (context, index) {
                                    if (index == _members.length) {
                                      if (_loadingMore) {
                                        return const Padding(
                                          padding: EdgeInsets.all(20),
                                          child: Center(
                                            child:
                                                CircularProgressIndicator.adaptive(),
                                          ),
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
                                        return TextButton(
                                          onPressed: _loadMore,
                                          child: const Text('Load more'),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    }
                                    final member = _members[index];
                                    final initial =
                                        member.displayName
                                            .trim()
                                            .characters
                                            .firstOrNull ??
                                        '?';
                                    final fallback = Center(
                                      child: Text(
                                        initial.toUpperCase(),
                                        style: TextStyle(
                                          color: colors.onPrimaryContainer,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                    return ListTile(
                                      key: ValueKey('connection-${member.id}'),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                      leading: ClipOval(
                                        child: Container(
                                          width: 46,
                                          height: 46,
                                          color: colors.primaryContainer,
                                          child: member.hasAvatar
                                              ? Image.network(
                                                  widget.repository
                                                      .connectionAvatarUrl(
                                                        member,
                                                      ),
                                                  headers: widget.repository
                                                      .publicMediaHeaders(),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) =>
                                                      fallback,
                                                )
                                              : fallback,
                                        ),
                                      ),
                                      title: Text(
                                        member.displayName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      subtitle: member.username.isEmpty
                                          ? null
                                          : Text(
                                              '@${member.username}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                  ),
                                            ),
                                      trailing: Icon(
                                        CupertinoIcons.chevron_right,
                                        size: 16,
                                        color: colors.onSurfaceVariant,
                                      ),
                                      onTap: () =>
                                          Navigator.of(context).push<void>(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  PublicProfileScreen(
                                                    profileId: member.id,
                                                    repository:
                                                        widget.repository,
                                                  ),
                                            ),
                                          ),
                                    );
                                  },
                                ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
