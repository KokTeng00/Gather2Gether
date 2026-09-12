import 'package:add_2_calendar/add_2_calendar.dart' as calendar;
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';
import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/data/event_reminder_service.dart';
import 'package:gather2gether/features/events/domain/event_lifecycle.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/create_event_screen.dart';
import 'package:gather2gether/features/events/presentation/event_discussion_screen.dart';
import 'package:gather2gether/features/events/presentation/event_host_dashboard_screen.dart';
import 'package:gather2gether/features/profile/presentation/public_profile_screen.dart';
import 'package:intl/intl.dart';
import 'package:gather2gether/features/events/presentation/event_planning_widgets.dart';
import 'package:gather2gether/features/events/domain/event_operations.dart';
import 'package:url_launcher/url_launcher.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({required this.event, this.repository, super.key});

  final EventSummary event;
  final EventRepository? repository;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  static const _shareChannel = MethodChannel('com.gather2gether/share');
  late final EventRepository _events;
  final _deviceReminders = const EventReminderService();
  late EventSummary _event;
  List<EventAnnouncement> _announcements = const [];
  bool _loading = false;
  bool _translating = false;
  bool _offline = false;
  int _selectedGuests = 0;
  bool _partyEdited = false;

  @override
  void initState() {
    super.initState();
    _events = widget.repository ?? EventRepository();
    _event = widget.event;
    _selectedGuests = _event.guestCount;
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final event = await _events.eventDetails(_event.id);
      List<EventAnnouncement> announcements = const [];
      try {
        announcements = await _events.announcements(_event.id);
      } catch (_) {
        // Event details remain useful when announcements are unavailable.
      }
      if (mounted) {
        setState(() {
          _event = event;
          if (!_partyEdited) _selectedGuests = event.guestCount;
          _announcements = announcements;
          _offline = _events.lastReadWasOffline;
        });
      }
      if (event.isCancelled) await _deviceReminders.cancel(event.id);
    } catch (_) {
      // Keep the summary from discovery when a refresh is temporarily unavailable.
    }
  }

  Future<void> _setRsvp(String status) async {
    if (_loading || _offline) return;
    setState(() => _loading = true);
    if (status == 'joined' && _event.userRsvpStatus != 'joined') {
      final proceed = await _checkConflicts();
      if (!mounted) return;
      if (!proceed) {
        setState(() => _loading = false);
        return;
      }
    }
    try {
      final savedStatus = _event.allowGuest || _event.guestCount > 0
          ? await _events.updateRsvpWithGuest(
              _event.id,
              status,
              status == 'cancelled' ? 0 : _selectedGuests,
            )
          : await _events.updateRsvp(_event.id, status);
      _partyEdited = false;
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (status) {
              'cancelled' => 'Your response was removed.',
              'joined' when savedStatus == 'waitlisted' =>
                'The event is full. You joined the waitlist.',
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
              error is EdgeApiException
                  ? error.message
                  : 'Could not update your response.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _checkConflicts() async {
    List<EventConflict> conflicts;
    try {
      conflicts = await _events.conflicts(_event.id);
    } catch (_) {
      if (!mounted) return false;
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Couldn’t check your other plans'),
              content: const Text(
                'You can still join, or go back and try again.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Go back'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Join anyway'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (conflicts.isEmpty) return true;
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('You have another plan then'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('This event overlaps with:'),
                  const SizedBox(height: 12),
                  for (final event in conflicts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            '${DateFormat.MMMd().format(event.startAt)} · ${DateFormat.Hm().format(event.startAt)}–${DateFormat.Hm().format(event.endAt)}',
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Go back'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Join anyway'),
              ),
            ],
          ),
        ) ??
        false;
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

  Future<void> _openOrganizer() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PublicProfileScreen(profileId: _event.organizerId),
    ),
  );

  Future<void> _setSaved() async {
    try {
      final saved = await _events.setSaved(_event.id, !_event.isSaved);
      if (mounted) setState(() => _event = _event.copyWith(isSaved: saved));
    } on EdgeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _hideRecommendation() async {
    try {
      await _events.hideEventRecommendation(_event.id);
      if (!mounted) return;
      _showMessage('This event will no longer appear in recommendations.');
      Navigator.of(context).pop();
    } on EdgeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _setReminder() async {
    if (_event.reminderAt != null) {
      await _events.clearReminder(_event.id);
      await _deviceReminders.cancel(_event.id);
      if (mounted) {
        setState(() => _event = _event.copyWith(clearReminder: true));
        _showMessage('Reminder removed.');
      }
      return;
    }
    final choices =
        <({String label, Duration before})>[
              (label: '1 day before', before: const Duration(days: 1)),
              (label: '1 hour before', before: const Duration(hours: 1)),
              (label: '15 minutes before', before: const Duration(minutes: 15)),
            ]
            .where(
              (choice) => _event.startAt
                  .subtract(choice.before)
                  .isAfter(DateTime.now()),
            )
            .toList();
    if (choices.isEmpty) {
      _showMessage('This event starts too soon to set a reminder.');
      return;
    }
    final selected = await showCupertinoModalPopup<Duration>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Remind me'),
        actions: [
          for (final choice in choices)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, choice.before),
              child: Text(choice.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (selected == null) return;
    try {
      final remindAt = await _events.setReminder(
        _event.id,
        _event.startAt.subtract(selected),
      );
      await _deviceReminders.schedule(_event, remindAt);
      if (mounted) {
        setState(() => _event = _event.copyWith(reminderAt: remindAt));
        _showMessage(
          'Reminder set for ${DateFormat.MMMd().add_Hm().format(remindAt)}.',
        );
      }
    } on EdgeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _addToCalendar() async {
    try {
      final opened = await calendar.Add2Calendar.addEvent2Cal(
        calendar.Event(
          title: _event.title,
          description: _event.description,
          location: '${_event.venueName}, ${_event.address}',
          startDate: _event.startAt,
          endDate: _event.endAt,
        ),
      );
      if (!opened && mounted) _showMessage('Could not open your calendar.');
    } on MissingPluginException {
      if (mounted) _showMessage('Calendar is unavailable on this device.');
    }
  }

  Future<void> _openDirections() async {
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query':
          '${_event.meetingLatitude ?? _event.latitude},${_event.meetingLongitude ?? _event.longitude}',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _showMessage('Could not open directions.');
    }
  }

  Future<void> _share() async {
    final base = AppConfig.edgeApiUrl.replaceFirst(RegExp(r'/api/v1/?$'), '');
    final link = '$base/invite/${_event.id}';
    final text =
        '${_event.title}\n${DateFormat.yMMMd().add_Hm().format(_event.startAt)}\n$link';
    try {
      await _shareChannel.invokeMethod<bool>('shareText', {'text': text});
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _showMessage('Invite copied. Share it with anyone.');
    } on PlatformException {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _showMessage('Invite copied. Share it with anyone.');
    }
  }

  Future<void> _openDiscussion() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            EventDiscussionScreen(event: _event, repository: _events),
      ),
    );
  }

  Future<void> _translateDetails() async {
    if (_translating) return;
    final language = await showDialog<String>(
      context: context,
      builder: (_) => const _TargetLanguageDialog(),
    );
    if (language == null || !mounted) return;
    setState(() => _translating = true);
    try {
      final translation = await _events.translateEvent(_event.id, language);
      if (!mounted) return;
      setState(() => _translating = false);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('$language translation'),
          content: SingleChildScrollView(
            child: SelectableText(
              translation,
              key: const Key('event-translation-result'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on EdgeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _editEvent() async {
    var scope = 'this';
    if (_event.eventSeriesId != null) {
      final selected = await showCupertinoModalPopup<String>(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: const Text('Edit recurring event'),
          message: const Text('Choose which upcoming occurrences to update.'),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'this'),
              child: const Text('This event only'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'future'),
              child: const Text('This and future events'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'all'),
              child: const Text('All upcoming events'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      scope = selected;
    }
    await showAppSheet<void>(
      context: context,
      builder: (routeContext) => CreateEventScreen(
        asSheet: true,
        initialEvent: _event,
        editScope: scope,
        eventRepository: _events,
        onCreated: () => Navigator.pop(routeContext),
      ),
    );
    await _refresh();
  }

  Future<void> _announce() async {
    final body = await showDialog<String>(
      context: context,
      builder: (_) => const _AnnouncementDialog(),
    );
    if (body == null || body.isEmpty) return;
    try {
      await _events.createAnnouncement(_event.id, body);
      await _refresh();
      if (mounted) _showMessage('Announcement sent to attendees.');
    } on EdgeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _cancelEvent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this event?'),
        content: const Text(
          'Everyone going, waiting, or marked maybe will receive an update.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Event'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Event'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _events.cancelEvent(_event.id);
      await _refresh();
      if (mounted) _showMessage('Event cancelled.');
    } on EdgeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _leaveFeedback() async {
    final feedback = await showDialog<_FeedbackResult>(
      context: context,
      builder: (_) => const _FeedbackDialog(),
    );
    if (feedback == null) return;
    try {
      await _events.submitFeedback(
        eventId: _event.id,
        attended: feedback.attended,
        rating: feedback.rating,
        comment: feedback.comment,
      );
      await _refresh();
      if (mounted) _showMessage('Thanks for updating your attendance.');
    } on EdgeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _openFeedback() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _EventFeedbackScreen(event: _event, repository: _events),
    ),
  );

  Future<void> _openAttendees() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _EventAttendeesScreen(event: _event, repository: _events),
    ),
  );

  Future<void> _openCohosts() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _EventCohostsScreen(event: _event, repository: _events),
    ),
  );

  Future<void> _openHostDashboard() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          EventHostDashboardScreen(event: _event, repository: _events),
    ),
  );

  Future<void> _createAgain() async {
    await showAppSheet<void>(
      context: context,
      builder: (routeContext) => CreateEventScreen(
        asSheet: true,
        templateEvent: _event,
        eventRepository: _events,
        onCreated: () => Navigator.pop(routeContext),
      ),
    );
  }

  Future<void> _setAttendeeVisibility(bool visible) async {
    try {
      final saved = await _events.setAttendeeVisibility(_event.id, visible);
      if (mounted) {
        setState(() => _event = _event.copyWith(attendeeVisible: saved));
      }
    } on EdgeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _setDiscussionNotifications(bool enabled) async {
    try {
      final saved = await _events.setDiscussionNotifications(
        _event.id,
        enabled,
      );
      if (mounted) {
        setState(
          () => _event = _event.copyWith(discussionNotificationsEnabled: saved),
        );
        _showMessage(
          saved
              ? 'Discussion notifications on.'
              : 'Discussion notifications muted.',
        );
      }
    } on EdgeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _requestReconfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ask attendees to reconfirm?'),
        content: const Text(
          'People who are going will have up to 24 hours to confirm. Unconfirmed places are released to the waitlist.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Request confirmations'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final deadline = await _events.requestRsvpReconfirmation(_event.id);
      if (mounted) {
        setState(
          () => _event = _event.copyWith(reconfirmationDeadlineAt: deadline),
        );
        _showMessage(
          'Confirmation requested by ${DateFormat.MMMd().add_Hm().format(deadline)}.',
        );
      }
    } on EdgeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _confirmRsvp() async {
    try {
      final confirmedAt = await _events.confirmRsvp(_event.id);
      if (mounted) {
        setState(
          () => _event = _event.copyWith(viewerReconfirmedAt: confirmedAt),
        );
        _showMessage('Your place is confirmed.');
      }
    } on EdgeApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
            key: const Key('event-save-action'),
            tooltip: _event.isSaved ? 'Remove saved event' : 'Save event',
            onPressed: _event.hasEnded || _event.isCancelled ? null : _setSaved,
            icon: Icon(
              _event.isSaved
                  ? CupertinoIcons.bookmark_fill
                  : CupertinoIcons.bookmark,
            ),
          ),
          IconButton(
            key: const Key('event-share-action'),
            tooltip: 'Share invitation',
            onPressed: _share,
            icon: const Icon(CupertinoIcons.share),
          ),
          IconButton(
            tooltip: 'Report event',
            onPressed: _event.viewerIsOrganizer ? null : _report,
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
            EventIntroduction(event: _event),
            if (_offline) ...[
              const SizedBox(height: 10),
              MaterialBanner(
                content: const Text(
                  'This is the latest saved copy. Actions need a connection.',
                ),
                actions: [
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            ],
            if (_event.recommendationReason.isNotEmpty &&
                !_event.viewerIsOrganizer) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    CupertinoIcons.sparkles,
                    size: 16,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _event.recommendationReason,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    key: const Key('event-hide-recommendation-action'),
                    onPressed: _hideRecommendation,
                    child: const Text('Not for me'),
                  ),
                ],
              ),
            ],
            if (_event.isCancelled) ...[
              const SizedBox(height: 16),
              Container(
                key: const Key('event-cancelled-banner'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.xmark_circle_fill, color: colors.error),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('This event was cancelled by the host.'),
                    ),
                  ],
                ),
              ),
            ],
            if (_event.needsReconfirmation) ...[
              const SizedBox(height: 16),
              Container(
                key: const Key('event-reconfirmation-banner'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Are you still going?',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Confirm by ${DateFormat.MMMd().add_Hm().format(_event.reconfirmationDeadlineAt!)} to keep your place.',
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      key: const Key('event-confirm-rsvp-action'),
                      onPressed: _confirmRsvp,
                      child: const Text('Yes, I’m still going'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _event.description,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: 24),
            if (_event.meetingInstructions.isNotEmpty ||
                _event.hasMeetingImage ||
                _event.meetingLatitude != null) ...[
              AppSection(
                title: 'Where to meet',
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_event.hasMeetingImage) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            _events.meetingImageUrl(_event.id),
                            headers: _events.mediaHeaders(),
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            semanticLabel: 'Entrance or meeting spot',
                            errorBuilder: (_, _, _) => const SizedBox(
                              height: 60,
                              child: Center(
                                child: Text('Meeting photo unavailable'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_event.meetingInstructions.isNotEmpty)
                        Text(
                          _event.meetingInstructions,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      if (_event.meetingLatitude != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _openDirections,
                            icon: const Icon(
                              CupertinoIcons.map_pin_ellipse,
                              size: 18,
                            ),
                            label: const Text(
                              'Directions to the meeting point',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (_event.allowGuest &&
                !_event.hasEnded &&
                !_event.isCancelled &&
                !_event.viewerIsOrganizer) ...[
              AppSection(
                title: 'Who’s coming?',
                footer:
                    'Your friend takes one place. You can update this later.',
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Just me')),
                        ButtonSegment(value: 1, label: Text('Me + 1')),
                      ],
                      selected: {_selectedGuests},
                      onSelectionChanged: _loading || _offline
                          ? null
                          : (selected) async {
                              setState(() {
                                _selectedGuests = selected.first;
                                _partyEdited = true;
                              });
                              if (const [
                                'joined',
                                'waitlisted',
                                'tentative',
                              ].contains(_event.userRsvpStatus)) {
                                await _setRsvp(
                                  _event.userRsvpStatus == 'tentative'
                                      ? 'tentative'
                                      : 'joined',
                                );
                                if (mounted) {
                                  setState(() {
                                    _selectedGuests = _event.guestCount;
                                    _partyEdited = false;
                                  });
                                }
                              }
                            },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            AppSection(
              title: 'Plan',
              child: Column(
                children: [
                  _DetailActionRow(
                    key: const Key('event-calendar-action'),
                    icon: CupertinoIcons.calendar_badge_plus,
                    title: 'Add to calendar',
                    onTap: _addToCalendar,
                  ),
                  const Divider(indent: 56),
                  _DetailActionRow(
                    key: const Key('event-directions-action'),
                    icon: CupertinoIcons.location,
                    title: 'Directions',
                    onTap: _openDirections,
                  ),
                  if (!_event.hasEnded && !_event.isCancelled) ...[
                    const Divider(indent: 56),
                    _DetailActionRow(
                      key: const Key('event-reminder-action'),
                      icon: _event.reminderAt == null
                          ? CupertinoIcons.bell
                          : CupertinoIcons.bell_fill,
                      title: _event.reminderAt == null
                          ? 'Set reminder'
                          : 'Reminder ${DateFormat.MMMd().add_Hm().format(_event.reminderAt!)}',
                      onTap: _setReminder,
                    ),
                  ],
                  if (_event.viewerIsOrganizer ||
                      const [
                        'joined',
                        'tentative',
                        'waitlisted',
                        'attended',
                      ].contains(status)) ...[
                    const Divider(indent: 56),
                    _DetailActionRow(
                      key: const Key('event-discussion-action'),
                      icon: CupertinoIcons.chat_bubble_2,
                      title: 'Attendee questions',
                      onTap: _openDiscussion,
                    ),
                    const Divider(indent: 56),
                    _DetailActionRow(
                      key: const Key('event-discussion-notifications-action'),
                      icon: _event.discussionNotificationsEnabled
                          ? CupertinoIcons.bell_fill
                          : CupertinoIcons.bell_slash,
                      title: _event.discussionNotificationsEnabled
                          ? 'Discussion notifications on'
                          : 'Discussion notifications muted',
                      onTap: () => _setDiscussionNotifications(
                        !_event.discussionNotificationsEnabled,
                      ),
                    ),
                  ],
                  if (_event.viewerIsOrganizer && _event.hasEnded) ...[
                    const Divider(indent: 56),
                    _DetailActionRow(
                      key: const Key('event-view-feedback-action'),
                      icon: CupertinoIcons.star,
                      title: 'Attendance & feedback',
                      onTap: _openFeedback,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            AppSection(
              title: 'Host',
              child: InkWell(
                key: const Key('event-organizer-profile'),
                onTap: _openOrganizer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: colors.primaryContainer,
                        child: Text(
                          _event.organizerName.trim().isEmpty
                              ? '?'
                              : String.fromCharCode(
                                  _event.organizerName.trim().runes.first,
                                ).toUpperCase(),
                          style: TextStyle(
                            color: colors.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _event.organizerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'View profile and follow',
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
                        color: colors.onSurfaceVariant,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
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
                  if (_event.beginnerFriendly) ...[
                    const Divider(indent: 56),
                    const _DetailRow(
                      icon: CupertinoIcons.hand_thumbsup_fill,
                      title: 'Beginner-friendly',
                      subtitle: 'No previous experience needed',
                    ),
                  ],
                  if (_event.wheelchairAccessible) ...[
                    const Divider(indent: 56),
                    const _DetailRow(
                      icon: CupertinoIcons.person_crop_circle,
                      title: 'Wheelchair accessible',
                      subtitle: 'The host marked this venue as accessible',
                    ),
                  ],
                  if (_event.eventSetting != 'unspecified') ...[
                    const Divider(indent: 56),
                    _DetailRow(
                      icon: _event.eventSetting == 'outdoor'
                          ? CupertinoIcons.sun_max_fill
                          : CupertinoIcons.house_fill,
                      title: switch (_event.eventSetting) {
                        'indoor' => 'Indoor',
                        'outdoor' => 'Outdoor',
                        _ => 'Indoor and outdoor',
                      },
                      subtitle: 'Event setting',
                    ),
                  ],
                  if (_event.eventLanguage.trim().isNotEmpty) ...[
                    const Divider(indent: 56),
                    _DetailRow(
                      icon: CupertinoIcons.globe,
                      title: _event.eventLanguage,
                      subtitle: 'Event language',
                    ),
                  ],
                  const Divider(indent: 56),
                  _DetailRow(
                    icon: CupertinoIcons.person_3_fill,
                    title: switch (_event.ageGuidance) {
                      'families' => 'Family friendly',
                      'teens' => 'Suitable for teens',
                      'adults' => 'Adults only',
                      _ => 'All ages',
                    },
                    subtitle: 'Age guidance',
                  ),
                  if (_event.whatToBring.trim().isNotEmpty) ...[
                    const Divider(indent: 56),
                    _DetailRow(
                      icon: CupertinoIcons.bag_fill,
                      title: 'What to bring',
                      subtitle: _event.whatToBring,
                    ),
                  ],
                  const Divider(indent: 56),
                  _DetailActionRow(
                    key: const Key('event-translate-action'),
                    icon: CupertinoIcons.globe,
                    title: _translating
                        ? 'Translating details…'
                        : 'Translate event details',
                    onTap: _translating ? null : _translateDetails,
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
                    if (_event.viewerIsOrganizer ||
                        const [
                          'joined',
                          'tentative',
                          'waitlisted',
                          'attended',
                        ].contains(status)) ...[
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        key: const Key('event-attendees-action'),
                        onPressed: _openAttendees,
                        icon: const Icon(CupertinoIcons.person_2),
                        label: Text(
                          _event.viewerIsOrganizer
                              ? 'View participant roster'
                              : 'See who’s going',
                        ),
                      ),
                    ],
                    if (!_event.viewerIsOrganizer &&
                        const [
                          'joined',
                          'tentative',
                          'waitlisted',
                          'attended',
                        ].contains(status))
                      SwitchListTile.adaptive(
                        key: const Key('event-attendee-visibility'),
                        contentPadding: EdgeInsets.zero,
                        value: _event.attendeeVisible,
                        title: const Text('Show me to other attendees'),
                        subtitle: const Text(
                          'The host can always see the full roster.',
                        ),
                        onChanged: _setAttendeeVisibility,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_announcements.isNotEmpty) ...[
              const SizedBox(height: 24),
              AppSection(
                title: 'Host updates',
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < _announcements.length;
                      index++
                    ) ...[
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(_announcements[index].body),
                            const SizedBox(height: 6),
                            Text(
                              DateFormat.MMMd().add_Hm().format(
                                _announcements[index].createdAt,
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (index != _announcements.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ],
            if (_event.viewerIsOrganizer) ...[
              const SizedBox(height: 24),
              AppSection(
                title: 'Host tools',
                child: Column(
                  children: [
                    _DetailActionRow(
                      key: const Key('event-host-dashboard-action'),
                      icon: CupertinoIcons.chart_bar_alt_fill,
                      title: 'Dashboard & check-in',
                      onTap: _openHostDashboard,
                    ),
                    const Divider(indent: 56),
                    if (!_event.hasEnded && !_event.isCancelled) ...[
                      _DetailActionRow(
                        key: const Key('event-edit-action'),
                        icon: CupertinoIcons.pencil,
                        title: 'Edit event',
                        onTap: _editEvent,
                      ),
                      const Divider(indent: 56),
                      _DetailActionRow(
                        key: const Key('event-announce-action'),
                        icon: CupertinoIcons.speaker_2,
                        title: 'Message attendees',
                        onTap: _announce,
                      ),
                      const Divider(indent: 56),
                      _DetailActionRow(
                        key: const Key('event-cohosts-action'),
                        icon: CupertinoIcons.person_2,
                        title: 'Co-hosts',
                        onTap: _openCohosts,
                      ),
                      const Divider(indent: 56),
                      _DetailActionRow(
                        key: const Key('event-request-reconfirmation-action'),
                        icon: CupertinoIcons.checkmark_seal,
                        title: _event.reconfirmationDeadlineAt == null
                            ? 'Ask attendees to reconfirm'
                            : 'Confirmations due ${DateFormat.MMMd().add_Hm().format(_event.reconfirmationDeadlineAt!)}',
                        onTap: _event.reconfirmationDeadlineAt == null
                            ? _requestReconfirmation
                            : null,
                      ),
                      const Divider(indent: 56),
                    ],
                    _DetailActionRow(
                      key: const Key('event-create-again-action'),
                      icon: CupertinoIcons.arrow_clockwise,
                      title: 'Create again',
                      onTap: _createAgain,
                    ),
                    if (!_event.hasEnded && !_event.isCancelled) ...[
                      const Divider(indent: 56),
                      _DetailActionRow(
                        key: const Key('event-cancel-action'),
                        icon: CupertinoIcons.xmark_circle,
                        title: 'Cancel event',
                        destructive: true,
                        onTap: _cancelEvent,
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
      bottomNavigationBar: _event.viewerIsOrganizer || _event.isCancelled
          ? null
          : _event.hasEnded
          ? (_event.viewerIsOrganizer ||
                    !const [
                      'joined',
                      'tentative',
                      'attended',
                      'no_show',
                    ].contains(status)
                ? null
                : FrostedContainer(
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.all(12),
                      child: FilledButton.icon(
                        key: const Key('event-feedback-action'),
                        onPressed: _leaveFeedback,
                        icon: const Icon(CupertinoIcons.star),
                        label: const Text('Confirm Attendance & Feedback'),
                      ),
                    ),
                  ))
          : FrostedContainer(
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    if (status == 'joined' ||
                        status == 'tentative' ||
                        status == 'waitlisted')
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: IconButton.outlined(
                          tooltip: 'Remove response',
                          onPressed: _loading || _offline
                              ? null
                              : () => _setRsvp('cancelled'),
                          icon: const Icon(CupertinoIcons.xmark),
                        ),
                      ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _loading || _offline
                            ? null
                            : () => _setRsvp('tentative'),
                        child: Text(
                          status == 'tentative' ? 'Maybe ✓' : 'Maybe',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _loading || _offline
                            ? null
                            : () => _setRsvp('joined'),
                        child: _loading
                            ? CupertinoActivityIndicator(
                                color: colors.onPrimary,
                              )
                            : Text(
                                status == 'joined'
                                    ? 'Going ✓'
                                    : status == 'waitlisted'
                                    ? 'Waitlist #${_event.waitlistPosition ?? '—'}'
                                    : _event.spotsLeft == 0
                                    ? 'Join Waitlist'
                                    : 'I’m Going',
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

class _AnnouncementDialog extends StatefulWidget {
  const _AnnouncementDialog();

  @override
  State<_AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<_AnnouncementDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Message attendees'),
    content: TextField(
      key: const Key('event-announcement-field'),
      controller: _controller,
      maxLength: 1000,
      minLines: 3,
      maxLines: 6,
      decoration: const InputDecoration(hintText: 'Share a useful update…'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Send'),
      ),
    ],
  );
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

class _DetailActionRow extends StatelessWidget {
  const _DetailActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final color = destructive
        ? colors.error
        : enabled
        ? colors.primary
        : colors.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(width: 28, child: Icon(icon, size: 21, color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: destructive
                      ? colors.error
                      : enabled
                      ? null
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
            if (enabled)
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class _TargetLanguageDialog extends StatefulWidget {
  const _TargetLanguageDialog();

  @override
  State<_TargetLanguageDialog> createState() => _TargetLanguageDialogState();
}

class _TargetLanguageDialogState extends State<_TargetLanguageDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Translate event'),
    content: TextField(
      key: const Key('event-translation-language-field'),
      controller: _controller,
      autofocus: true,
      maxLength: 60,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(hintText: 'German, Spanish, Japanese…'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('event-translate-confirm'),
        onPressed: () {
          final language = _controller.text.trim();
          Navigator.pop(context, language.length >= 2 ? language : null);
        },
        child: const Text('Translate'),
      ),
    ],
  );
}

class _EventCohostsScreen extends StatefulWidget {
  const _EventCohostsScreen({required this.event, required this.repository});

  final EventSummary event;
  final EventRepository repository;

  @override
  State<_EventCohostsScreen> createState() => _EventCohostsScreenState();
}

class _EventCohostsScreenState extends State<_EventCohostsScreen> {
  final _usernameController = TextEditingController();
  List<EventCohost>? _people;
  String? _error;
  bool _saving = false;

  bool get _viewerCanEdit =>
      _people?.any((person) => person.viewerCanEdit) == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _people = null;
      _error = null;
    });
    try {
      final people = await widget.repository.cohosts(widget.event.id);
      if (mounted) setState(() => _people = people);
    } on EdgeApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load co-hosts.');
    }
  }

  Future<void> _add() async {
    final username = _usernameController.text.trim();
    if (username.length < 3 || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.repository.setCohost(widget.event.id, username, true);
      _usernameController.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Co-host added.')));
      }
    } on EdgeApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(EventCohost person) async {
    if (_saving || person.username.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.repository.setCohost(
        widget.event.id,
        person.username,
        false,
      );
      if (!mounted) return;
      setState(() {
        _people = _people
            ?.where((item) => item.profileId != person.profileId)
            .toList(growable: false);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${person.displayName} removed.')));
    } on EdgeApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Co-hosts')),
    body: _people == null && _error == null
        ? const Center(child: CupertinoActivityIndicator())
        : _error != null
        ? AppMaintenanceState(onRetry: _load)
        : ListView(
            key: const Key('event-cohosts-list'),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text(
                _viewerCanEdit
                    ? 'Add up to five people by username. Co-hosts can edit the event, message attendees, and manage the plan.'
                    : 'The event owner controls who can co-host this plan.',
              ),
              if (_viewerCanEdit) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('event-cohost-username-field'),
                        controller: _usernameController,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: '@username',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      key: const Key('event-add-cohost-button'),
                      onPressed: _saving ? null : _add,
                      child: Text(_saving ? 'Adding…' : 'Add'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              for (final person in _people!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    child: Text(
                      person.displayName.trim().isEmpty
                          ? '?'
                          : String.fromCharCode(
                              person.displayName.trim().runes.first,
                            ).toUpperCase(),
                    ),
                  ),
                  title: Text(person.displayName),
                  subtitle: Text(
                    '${person.username.isEmpty ? '' : '@${person.username} · '}${person.role}',
                  ),
                  trailing: _viewerCanEdit && person.role == 'Co-host'
                      ? TextButton(
                          onPressed: _saving ? null : () => _remove(person),
                          child: const Text('Remove'),
                        )
                      : null,
                ),
            ],
          ),
  );
}

class _EventAttendeesScreen extends StatefulWidget {
  const _EventAttendeesScreen({required this.event, required this.repository});

  final EventSummary event;
  final EventRepository repository;

  @override
  State<_EventAttendeesScreen> createState() => _EventAttendeesScreenState();
}

class _EventAttendeesScreenState extends State<_EventAttendeesScreen> {
  List<EventAttendee>? _attendees;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final attendees = await widget.repository.attendees(widget.event.id);
      if (mounted) setState(() => _attendees = attendees);
    } on EdgeApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _openProfile(EventAttendee attendee) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PublicProfileScreen(profileId: attendee.profileId),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.event.viewerIsOrganizer ? 'Participant roster' : 'Who’s going',
      ),
    ),
    body: _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          )
        : _attendees == null
        ? const Center(child: CupertinoActivityIndicator())
        : _attendees!.isEmpty
        ? const Center(child: Text('No visible attendees yet.'))
        : RefreshIndicator.adaptive(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _attendees!.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, index) {
                final attendee = _attendees![index];
                final status = switch (attendee.rsvpStatus) {
                  'tentative' => 'Maybe',
                  'waitlisted' => 'Waitlisted',
                  'attended' => 'Attended',
                  _ => 'Going',
                };
                final confirmation =
                    widget.event.viewerIsOrganizer &&
                        widget.event.reconfirmationDeadlineAt != null &&
                        attendee.rsvpStatus == 'joined'
                    ? attendee.reconfirmedAt == null
                          ? ' · Awaiting confirmation'
                          : ' · Confirmed'
                    : '';
                return ListTile(
                  key: ValueKey('event-attendee-${attendee.profileId}'),
                  leading: CircleAvatar(
                    child: Text(
                      attendee.displayName.trim().isEmpty
                          ? '?'
                          : String.fromCharCode(
                              attendee.displayName.trim().runes.first,
                            ).toUpperCase(),
                    ),
                  ),
                  title: Text(
                    attendee.isSelf
                        ? '${attendee.displayName} (you)'
                        : attendee.displayName,
                  ),
                  subtitle: Text(
                    '${attendee.username.isEmpty ? status : '@${attendee.username} · $status'}$confirmation',
                  ),
                  trailing:
                      !attendee.visibleToAttendees &&
                          widget.event.viewerIsOrganizer &&
                          !attendee.isSelf
                      ? const Tooltip(
                          message: 'Hidden from other attendees',
                          child: Icon(CupertinoIcons.eye_slash, size: 18),
                        )
                      : const Icon(CupertinoIcons.chevron_forward, size: 16),
                  onTap: () => _openProfile(attendee),
                );
              },
            ),
          ),
  );
}

class _FeedbackResult {
  const _FeedbackResult({
    required this.attended,
    required this.rating,
    required this.comment,
  });

  final bool attended;
  final int? rating;
  final String comment;
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _comment = TextEditingController();
  bool _attended = true;
  int _rating = 5;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('How did it go?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('I attended')),
                ButtonSegment(value: false, label: Text('Missed it')),
              ],
              selected: {_attended},
              onSelectionChanged: (value) {
                setState(() => _attended = value.single);
              },
            ),
            if (_attended) ...[
              const SizedBox(height: 18),
              const Text('Your rating'),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var value = 1; value <= 5; value++)
                    IconButton(
                      tooltip: '$value stars',
                      onPressed: () => setState(() => _rating = value),
                      icon: Icon(
                        value <= _rating
                            ? CupertinoIcons.star_fill
                            : CupertinoIcons.star,
                      ),
                    ),
                ],
              ),
              TextField(
                controller: _comment,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Optional private feedback for the host',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _FeedbackResult(
              attended: _attended,
              rating: _attended ? _rating : null,
              comment: _attended ? _comment.text.trim() : '',
            ),
          ),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _EventFeedbackScreen extends StatefulWidget {
  const _EventFeedbackScreen({required this.event, required this.repository});

  final EventSummary event;
  final EventRepository repository;

  @override
  State<_EventFeedbackScreen> createState() => _EventFeedbackScreenState();
}

class _EventFeedbackScreenState extends State<_EventFeedbackScreen> {
  List<EventFeedbackEntry> _feedback = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final feedback = await widget.repository.eventFeedback(widget.event.id);
      if (mounted) {
        setState(() {
          _feedback = feedback;
          _error = null;
        });
      }
    } on EdgeApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratings = _feedback.where((item) => item.rating != null).toList();
    final attended = _feedback.where((item) => item.attended).length;
    final average = ratings.isEmpty
        ? null
        : ratings.fold<int>(0, (sum, item) => sum + item.rating!) /
              ratings.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Event Feedback')),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                AppSection(
                  title: widget.event.title,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _FeedbackMetric(
                            value: '$attended',
                            label: 'confirmed',
                          ),
                        ),
                        Expanded(
                          child: _FeedbackMetric(
                            value: average?.toStringAsFixed(1) ?? '—',
                            label: 'average rating',
                          ),
                        ),
                        Expanded(
                          child: _FeedbackMetric(
                            value: '${_feedback.length}',
                            label: 'responses',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (_feedback.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No attendee feedback yet.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final entry in _feedback) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  entry.attended
                                      ? CupertinoIcons.checkmark_circle_fill
                                      : CupertinoIcons.xmark_circle,
                                  size: 18,
                                ),
                                const SizedBox(width: 7),
                                Text(entry.attended ? 'Attended' : 'Missed it'),
                                const Spacer(),
                                if (entry.rating != null)
                                  Text('${entry.rating} ★'),
                              ],
                            ),
                            if (entry.comment.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(entry.comment),
                            ],
                            const SizedBox(height: 7),
                            Text(
                              DateFormat.yMMMd().format(entry.createdAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
    );
  }
}

class _FeedbackMetric extends StatelessWidget {
  const _FeedbackMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 3),
      Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
