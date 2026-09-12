import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/create_event_screen.dart';
import 'package:gather2gether/features/events/presentation/event_detail_screen.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/forum/domain/planning_poll.dart';
import 'package:intl/intl.dart';

class PollDateEditor extends StatelessWidget {
  const PollDateEditor({
    required this.options,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });
  final List<PollDateOption> options;
  final ValueChanged<List<PollDateOption>> onChanged;
  final bool enabled;
  Future<void> _pick(BuildContext context, [int? index]) async {
    final now = DateTime.now();
    final original = index == null ? null : options[index];
    final date = await showDatePicker(
      context: context,
      initialDate: original?.startAt ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Propose a date',
    );
    if (date == null || !context.mounted) return;
    final start = await showTimePicker(
      context: context,
      initialTime: original == null
          ? const TimeOfDay(hour: 18, minute: 0)
          : TimeOfDay.fromDateTime(original.startAt),
      helpText: 'Starts',
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: original == null
          ? const TimeOfDay(hour: 20, minute: 0)
          : TimeOfDay.fromDateTime(original.endAt),
      helpText: 'Ends',
    );
    if (end == null || !context.mounted) return;
    final starts = DateTime(
      date.year,
      date.month,
      date.day,
      start.hour,
      start.minute,
    );
    final ends = DateTime(
      date.year,
      date.month,
      date.day,
      end.hour,
      end.minute,
    );
    if (!starts.isAfter(DateTime.now()) ||
        !ends.isAfter(starts) ||
        options.indexed.any(
          (item) => item.$1 != index && item.$2.startAt == starts,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose a different future time, with the end after the start.',
          ),
        ),
      );
      return;
    }
    final updated = [...options];
    final option = PollDateOption(startAt: starts, endAt: ends);
    if (index == null) {
      updated.add(option);
    } else {
      updated[index] = option;
    }
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) => AppSection(
    title: 'Find a date together',
    footer: options.isEmpty
        ? 'Optional · Add two or three dates for people to vote on.'
        : 'People can choose every date that works. You’ll pick one to make the event.',
    child: Column(
      children: [
        for (final entry in options.indexed)
          ListTile(
            leading: const Icon(CupertinoIcons.calendar),
            title: Text(DateFormat('EEE, d MMM').format(entry.$2.startAt)),
            subtitle: Text(
              '${DateFormat.Hm().format(entry.$2.startAt)}–${DateFormat.Hm().format(entry.$2.endAt)}',
            ),
            onTap: enabled ? () => _pick(context, entry.$1) : null,
            trailing: IconButton(
              tooltip: 'Remove date',
              onPressed: enabled
                  ? () => onChanged([...options]..removeAt(entry.$1))
                  : null,
              icon: const Icon(CupertinoIcons.minus_circle),
            ),
          ),
        if (options.length < 3)
          ListTile(
            key: const Key('add-poll-date'),
            leading: const Icon(CupertinoIcons.plus),
            title: Text(
              options.isEmpty ? 'Add a date poll' : 'Add another date',
            ),
            onTap: enabled ? () => _pick(context) : null,
          ),
        if (options.length == 1)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('Add one more date before publishing.'),
          ),
      ],
    ),
  );
}

class PlanningPollCard extends StatefulWidget {
  const PlanningPollCard({
    required this.post,
    required this.repository,
    required this.onPublished,
    super.key,
  });
  final ForumPost post;
  final ForumRepository repository;
  final Future<void> Function() onPublished;
  @override
  State<PlanningPollCard> createState() => _PlanningPollCardState();
}

class _PlanningPollCardState extends State<PlanningPollCard> {
  late PlanningPoll _poll = widget.post.poll!;
  bool _busy = false;
  @override
  void didUpdateWidget(covariant PlanningPollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.post.poll != null) _poll = widget.post.poll!;
  }

  Future<void> _vote(PollDateOption option) async {
    setState(() => _busy = true);
    try {
      final poll = await widget.repository.voteOnPoll(
        _poll.postId,
        option.id,
        !option.voted,
      );
      if (mounted) setState(() => _poll = poll);
    } on ForumApiException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) _message('Could not save your vote. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  Future<void> _publish(PollDateOption option) async {
    final post = widget.post;
    final template = EventSummary(
      id: '',
      organizerId: post.authorId,
      organizerName: post.authorName,
      title: post.title,
      description: post.body.length <= 2000
          ? post.body
          : post.body.substring(0, 2000),
      category: 'Other',
      venueName: post.placeName ?? '',
      address: post.placeAddress ?? '',
      latitude: 0,
      longitude: 0,
      startAt: option.startAt,
      endAt: option.endAt,
      maxParticipants: 12,
      joinedCount: 0,
      tentativeCount: 0,
      distanceMeters: 0,
      userRsvpStatus: null,
    );
    await showAppSheet<void>(
      context: context,
      builder: (sheetContext) => CreateEventScreen(
        asSheet: true,
        templateEvent: template,
        pollPostId: post.id,
        pollOptionId: option.id,
        onCreated: () => Navigator.pop(sheetContext),
      ),
    );
    await widget.onPublished();
  }

  Future<void> _openEvent() async {
    setState(() => _busy = true);
    try {
      final event = await EventRepository().eventDetails(_poll.eventId!);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
      );
    } catch (_) {
      if (mounted) _message('This event is no longer available.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppSection(
      title: _poll.closed ? 'The plan is set' : 'Which dates work for you?',
      footer: _poll.closed
          ? 'Voting is closed. Join the event to confirm your place.'
          : 'Choose all that work. Voting doesn’t reserve a place.',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final option in _poll.options) ...[
              Material(
                color: option.voted
                    ? colors.primaryContainer.withValues(alpha: .45)
                    : colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap:
                      _busy ||
                          !_poll.canVote ||
                          !option.startAt.isAfter(DateTime.now())
                      ? null
                      : () => _vote(option),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          option.voted
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          size: 22,
                          color: option.voted
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('EEE, d MMM').format(option.startAt),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${DateFormat.Hm().format(option.startAt)}–${DateFormat.Hm().format(option.endAt)}',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${option.voteCount}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'free',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_poll.viewerIsAuthor &&
                  _poll.canVote &&
                  option.startAt.isAfter(DateTime.now()))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : () => _publish(option),
                    child: const Text('Make an event on this date'),
                  ),
                ),
              const SizedBox(height: 8),
            ],
            if (_poll.eventId != null)
              FilledButton(
                onPressed: _busy ? null : _openEvent,
                child: const Text('View event & join'),
              ),
          ],
        ),
      ),
    );
  }
}
