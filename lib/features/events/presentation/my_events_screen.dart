import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/data/event_reminder_service.dart';
import 'package:gather2gether/features/events/domain/event_lifecycle.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/event_detail_screen.dart';
import 'package:intl/intl.dart';

const _planFilters = <String>['going', 'tentative', 'hosting', 'saved', 'past'];

const _planLabels = <String>['Going', 'Maybe', 'Hosting', 'Saved', 'Past'];

class MyEventsScreen extends StatefulWidget {
  const MyEventsScreen({this.repository, super.key});

  final EventRepository? repository;

  @override
  State<MyEventsScreen> createState() => _MyEventsScreenState();
}

class _MyEventsScreenState extends State<MyEventsScreen>
    with SingleTickerProviderStateMixin {
  late final EventRepository _repository;
  late final TabController _tabs;
  final _deviceReminders = const EventReminderService();
  List<EventSummary> _events = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? EventRepository();
    _tabs = TabController(length: _planFilters.length, vsync: this)
      ..addListener(_tabChanged);
    _load();
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_tabChanged)
      ..dispose();
    super.dispose();
  }

  void _tabChanged() {
    if (!_tabs.indexIsChanging) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await _repository.myEvents(_planFilters[_tabs.index]);
      for (final event in events) {
        if (event.isCancelled || event.reminderAt == null) {
          if (event.isCancelled) await _deviceReminders.cancel(event.id);
        } else {
          await _deviceReminders.schedule(event, event.reminderAt!);
        }
      }
      if (mounted) setState(() => _events = events);
    } on EdgeApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Your plans are unavailable.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEvent(EventSummary event) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            EventDetailScreen(event: event, repository: _repository),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EventNotificationsScreen(repository: _repository),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 12, 10),
            child: Row(
              children: [
                const Expanded(
                  child: AppPageHeader(
                    title: 'Plans',
                    subtitle: 'Everything you saved, joined, or host.',
                  ),
                ),
                IconButton(
                  key: const Key('event-notifications-action'),
                  tooltip: 'Event notifications',
                  onPressed: _openNotifications,
                  icon: const Icon(CupertinoIcons.bell),
                ),
              ],
            ),
          ),
          TabBar(
            key: const Key('my-events-tabs'),
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: [for (final label in _planLabels) Tab(text: label)],
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }
    if (_error != null) {
      return AppMaintenanceState(
        key: const Key('my-events-error'),
        onRetry: _load,
      );
    }
    if (_events.isEmpty) {
      return _EmptyPlans(filter: _planFilters[_tabs.index]);
    }
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView.separated(
        key: const Key('my-events-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        itemCount: _events.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final event = _events[index];
          return _PlanCard(event: event, onTap: () => _openEvent(event));
        },
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.event, required this.onTap});

  final EventSummary event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visual = CategoryVisual.resolve(context, event.category);
    final status = switch (event.userRsvpStatus) {
      'waitlisted' => 'Waitlist #${event.waitlistPosition ?? '—'}',
      'tentative' => 'Maybe',
      'joined' => 'Going',
      'attended' => 'Attended',
      _ when event.viewerIsOrganizer => 'Hosting',
      _ when event.isSaved => 'Saved',
      _ => null,
    };
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 64,
                decoration: BoxDecoration(
                  color: visual.background,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(visual.icon, color: visual.ink, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEE, d MMM · HH:mm').format(event.startAt),
                      style: TextStyle(
                        color: event.isCancelled
                            ? colors.error
                            : colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      event.isCancelled
                          ? 'Cancelled'
                          : '${event.venueName}${status == null ? '' : ' · $status'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: event.isCancelled
                            ? colors.error
                            : colors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (event.reminderAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 22, right: 6),
                  child: Icon(
                    CupertinoIcons.bell_fill,
                    size: 15,
                    color: colors.primary,
                  ),
                ),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlans extends StatelessWidget {
  const _EmptyPlans({required this.filter});

  final String filter;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      'going' => 'Events you join will appear here.',
      'tentative' => 'Maybe responses and waitlists will appear here.',
      'hosting' => 'Events you create will appear here.',
      'saved' => 'Save an event to keep it here without committing.',
      _ => 'Completed plans will appear here.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.calendar, size: 48),
            const SizedBox(height: 14),
            Text(
              'Nothing here yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class EventNotificationsScreen extends StatefulWidget {
  const EventNotificationsScreen({required this.repository, super.key});

  final EventRepository repository;

  @override
  State<EventNotificationsScreen> createState() =>
      _EventNotificationsScreenState();
}

class _EventNotificationsScreenState extends State<EventNotificationsScreen> {
  List<MemberNotification> _notifications = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final notifications = await widget.repository.notifications();
      if (mounted) setState(() => _notifications = notifications);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    await widget.repository.markAllNotificationsRead();
    if (mounted) {
      setState(() {
        _notifications = [
          for (final notification in _notifications)
            notification.copyWith(isRead: true),
        ];
      });
    }
  }

  Future<void> _open(MemberNotification notification) async {
    if (!notification.isRead) {
      await widget.repository.markNotificationRead(notification.id);
    }
    final eventId = notification.eventId;
    if (!mounted || eventId == null) return;
    try {
      final event = await widget.repository.eventDetails(eventId);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              EventDetailScreen(event: event, repository: widget.repository),
        ),
      );
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This event is no longer available.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Updates'),
        actions: [
          TextButton(
            onPressed: _notifications.any((item) => !item.isRead)
                ? _markAllRead
                : null,
            child: const Text('Read all'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : _notifications.isEmpty
          ? const Center(child: Text('No event updates yet.'))
          : RefreshIndicator.adaptive(
              onRefresh: _load,
              child: ListView.separated(
                itemCount: _notifications.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final notification = _notifications[index];
                  return ListTile(
                    onTap: () => _open(notification),
                    leading: Icon(
                      notification.isRead
                          ? CupertinoIcons.bell
                          : CupertinoIcons.bell_fill,
                    ),
                    title: Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: notification.isRead
                            ? FontWeight.w500
                            : FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      '${notification.body}\n${DateFormat.MMMd().add_Hm().format(notification.createdAt)}',
                    ),
                    isThreeLine: true,
                  );
                },
              ),
            ),
    );
  }
}
