import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:intl/intl.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({required this.event, super.key});

  final EventSummary event;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final _events = EventRepository();
  late EventSummary _event;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final event = await _events.eventDetails(_event.id);
      if (mounted) setState(() => _event = event);
    } catch (_) {
      // Keep the summary from discovery when a refresh is temporarily unavailable.
    }
  }

  Future<void> _setRsvp(String status) async {
    setState(() => _loading = true);
    try {
      await _events.setRsvp(_event.id, status);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (status) {
              'cancelled' => 'Your response was removed.',
              'joined' => 'You are going!',
              _ => 'Saved as maybe.',
            }),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$error'.contains('event_full')
                  ? 'This event is already full.'
                  : 'Could not update your response.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _report() async {
    final reason = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Report Event'),
        message: const Text(
          'Choose the reason that best describes the problem.',
        ),
        actions: [
          for (final entry in const {
            'spam': 'Spam',
            'unsafe_behaviour': 'Unsafe behaviour',
            'inappropriate_content': 'Inappropriate content',
            'misleading': 'Misleading information',
            'other': 'Something else',
          }.entries)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (reason == null) return;
    try {
      await _events.reportEvent(eventId: _event.id, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted for review.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not submit the report.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _event.userRsvpStatus;
    final colors = Theme.of(context).colorScheme;
    final progress = _event.maxParticipants == 0
        ? 0.0
        : _event.joinedCount / _event.maxParticipants;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event'),
        actions: [
          IconButton(
            tooltip: 'More',
            onPressed: _report,
            icon: const Icon(CupertinoIcons.ellipsis_circle),
          ),
        ],
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
          children: [
            AppHeroArt(
              label: _event.category,
              title: _event.title,
              subtitle: 'Hosted by ${_event.organizerName}',
              height: 270,
            ),
            const SizedBox(height: 24),
            AppSection(
              title: 'Details',
              child: Column(
                children: [
                  _DetailRow(
                    icon: CupertinoIcons.calendar,
                    title: DateFormat('EEEE, d MMMM').format(_event.startAt),
                    subtitle:
                        '${DateFormat.Hm().format(_event.startAt)}–${DateFormat.Hm().format(_event.endAt)}',
                  ),
                  const Divider(indent: 56),
                  _DetailRow(
                    icon: CupertinoIcons.location_fill,
                    title: _event.venueName,
                    subtitle: _event.address,
                  ),
                  const Divider(indent: 56),
                  _DetailRow(
                    icon: CupertinoIcons.person_2_fill,
                    title: '${_event.joinedCount} going',
                    subtitle:
                        '${_event.spotsLeft} spots left · ${_event.tentativeCount} maybe',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AppSection(
              title: 'Attendance',
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${_event.joinedCount} of ${_event.maxParticipants}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          '${_event.spotsLeft} available',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 7,
                        value: progress.clamp(0, 1),
                        backgroundColor: colors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            AppSection(
              title: 'About',
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  _event.description,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.checkmark_shield_fill,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'This event is free. Never send payment outside the app.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: FrostedContainer(
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              if (status == 'joined' || status == 'tentative')
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton.outlined(
                    tooltip: 'Remove response',
                    onPressed: _loading ? null : () => _setRsvp('cancelled'),
                    icon: const Icon(CupertinoIcons.xmark),
                  ),
                ),
              Expanded(
                child: OutlinedButton(
                  onPressed: _loading ? null : () => _setRsvp('tentative'),
                  child: Text(status == 'tentative' ? 'Maybe ✓' : 'Maybe'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed:
                      _loading || (_event.spotsLeft == 0 && status != 'joined')
                      ? null
                      : () => _setRsvp('joined'),
                  child: _loading
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Text(status == 'joined' ? 'Going ✓' : 'I’m Going'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Icon(
            icon,
            size: 21,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
