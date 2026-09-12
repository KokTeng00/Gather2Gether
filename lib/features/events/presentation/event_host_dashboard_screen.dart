import 'package:flutter/material.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_operations.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';

class EventHostDashboardScreen extends StatefulWidget {
  const EventHostDashboardScreen({
    required this.event,
    required this.repository,
    super.key,
  });

  final EventSummary event;
  final EventRepository repository;

  @override
  State<EventHostDashboardScreen> createState() =>
      _EventHostDashboardScreenState();
}

class _EventHostDashboardScreenState extends State<EventHostDashboardScreen> {
  EventHostDashboard? _dashboard;
  List<EventHostAttendee>? _attendees;
  String? _updatingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        widget.repository.hostDashboard(widget.event.id),
        widget.repository.hostAttendees(widget.event.id),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = values[0] as EventHostDashboard;
        _attendees = values[1] as List<EventHostAttendee>;
      });
    } catch (_) {
      if (mounted) setState(() => _attendees = const []);
    }
  }

  Future<void> _setStatus(EventHostAttendee attendee, String status) async {
    setState(() => _updatingId = attendee.profileId);
    try {
      await widget.repository.setAttendance(
        widget.event.id,
        attendee.profileId,
        status,
      );
      await _load();
    } on EdgeApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _updatingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final attendees = _attendees;
    return Scaffold(
      appBar: AppBar(title: const Text('Host dashboard')),
      body: attendees == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (dashboard != null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Stat(label: 'Going', value: dashboard.joined),
                        _Stat(label: 'Maybe', value: dashboard.tentative),
                        _Stat(label: 'Waiting', value: dashboard.waitlisted),
                        _Stat(label: 'Checked in', value: dashboard.attended),
                        _Stat(label: 'No-show', value: dashboard.noShow),
                        _Stat(label: 'Saved', value: dashboard.saved),
                      ],
                    ),
                  if (dashboard?.averageRating != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${dashboard!.averageRating!.toStringAsFixed(1)} ★ from ${dashboard.feedbackCount} feedback responses',
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Fast check-in',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Attendance changes open six hours before the event.',
                  ),
                  const SizedBox(height: 8),
                  if (attendees.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No attendees yet.')),
                    ),
                  for (final attendee in attendees)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${attendee.displayName}${attendee.guestCount == 1 ? ' + 1 friend' : ''}',
                        ),
                        subtitle: Text(
                          attendee.username.isEmpty
                              ? attendee.status
                              : '@${attendee.username} · ${attendee.status}',
                        ),
                        trailing: _updatingId == attendee.profileId
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : PopupMenuButton<String>(
                                tooltip: 'Update attendance',
                                onSelected: (status) =>
                                    _setStatus(attendee, status),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'attended',
                                    child: Text('Checked in'),
                                  ),
                                  PopupMenuItem(
                                    value: 'no_show',
                                    child: Text('No-show'),
                                  ),
                                  PopupMenuItem(
                                    value: 'joined',
                                    child: Text('Going'),
                                  ),
                                ],
                              ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Chip(label: Text('$label $value'));
}
