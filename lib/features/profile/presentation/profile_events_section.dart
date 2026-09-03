import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/event_detail_screen.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:intl/intl.dart';

enum _ProfileEventView { hosting, past }

class ProfileEventsSection extends StatefulWidget {
  const ProfileEventsSection({
    required this.profileId,
    required this.pastEventsPublic,
    required this.viewerIsSelf,
    required this.repository,
    super.key,
  });

  final String profileId;
  final bool pastEventsPublic;
  final bool viewerIsSelf;
  final ProfileRepository repository;

  @override
  State<ProfileEventsSection> createState() => _ProfileEventsSectionState();
}

class _ProfileEventsSectionState extends State<ProfileEventsSection> {
  List<EventSummary> _hosting = const [];
  List<EventSummary> _past = const [];
  bool _loading = true;
  bool _failed = false;
  _ProfileEventView _selectedView = _ProfileEventView.hosting;

  bool get _canSeePast => widget.viewerIsSelf || widget.pastEventsPublic;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileEventsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId ||
        oldWidget.pastEventsPublic != widget.pastEventsPublic ||
        oldWidget.viewerIsSelf != widget.viewerIsSelf) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final hosting = await widget.repository.fetchProfileEvents(
        widget.profileId,
        'hosting',
      );
      final past = _canSeePast
          ? await widget.repository.fetchProfileEvents(widget.profileId, 'past')
          : const <EventSummary>[];
      if (!mounted) return;
      setState(() {
        _hosting = hosting;
        _past = past;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(EventSummary event) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      key: const Key('profile-events-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Events',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          'Hosting and past activity',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Container(
          key: const Key('profile-events-switcher'),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _EventTab(
                  title: 'Hosting',
                  count: _hosting.length,
                  selected: _selectedView == _ProfileEventView.hosting,
                  onTap: () =>
                      setState(() => _selectedView = _ProfileEventView.hosting),
                ),
              ),
              Expanded(
                child: _EventTab(
                  title: 'Past',
                  count: _past.length,
                  selected: _selectedView == _ProfileEventView.past,
                  locked: !_canSeePast,
                  onTap: () =>
                      setState(() => _selectedView = _ProfileEventView.past),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _buildSelectedContent(),
        ),
      ],
    );
  }

  Widget _buildSelectedContent() {
    if (_loading) {
      return const SizedBox(
        key: Key('profile-events-loading'),
        height: 92,
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (_failed) {
      return _EventsError(onRetry: _load);
    }
    if (_selectedView == _ProfileEventView.hosting) {
      return _EventCollection(
        key: const Key('profile-hosting-events'),
        subtitle: 'Upcoming events organized by this member.',
        events: _hosting,
        emptyText: 'No upcoming hosted events.',
        onOpen: _open,
      );
    }
    if (!_canSeePast) return const _PrivatePastNotice();
    return _EventCollection(
      key: const Key('profile-past-events'),
      subtitle: widget.viewerIsSelf
          ? widget.pastEventsPublic
                ? 'Visible to other members on your profile.'
                : 'Private — only you can see this history.'
          : 'Events this member hosted or confirmed attending.',
      events: _past,
      emptyText: 'No past events to show.',
      onOpen: _open,
    );
  }
}

class _EventTab extends StatelessWidget {
  const _EventTab({
    required this.title,
    required this.count,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final String title;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (locked)
                    Icon(
                      CupertinoIcons.lock_fill,
                      size: 12,
                      color: colors.onSurfaceVariant,
                    )
                  else
                    Text(
                      '$count',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              if (selected)
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 0,
                  child: Container(height: 2, color: colors.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventCollection extends StatelessWidget {
  const _EventCollection({
    required this.subtitle,
    required this.events,
    required this.emptyText,
    required this.onOpen,
    super.key,
  });

  final String subtitle;
  final List<EventSummary> events;
  final String emptyText;
  final ValueChanged<EventSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
        if (events.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 22),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.65),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.calendar,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    emptyText,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          )
        else
          ...events.map(
            (event) =>
                _ProfileEventCard(event: event, onTap: () => onOpen(event)),
          ),
      ],
    );
  }
}

class _EventsError extends StatelessWidget {
  const _EventsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('profile-events-error'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_circle,
            color: colors.onErrorContainer,
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('Profile events are unavailable.')),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ProfileEventCard extends StatelessWidget {
  const _ProfileEventCard({required this.event, required this.onTap});

  final EventSummary event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.72),
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('MMM').format(event.startAt).toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      DateFormat('d').format(event.startAt),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: colors.outlineVariant.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('HH:mm').format(event.startAt),
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.venueName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivatePastNotice extends StatelessWidget {
  const _PrivatePastNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('profile-past-events-private'),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.lock_fill, color: colors.onSurfaceVariant),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Past events are private',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'This member has chosen not to share their event history.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
