import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/constants/forum_constants.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_lifecycle.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/profile/presentation/public_profile_screen.dart';
import 'package:intl/intl.dart';

class EventDiscussionScreen extends StatefulWidget {
  const EventDiscussionScreen({
    required this.event,
    required this.repository,
    super.key,
  });

  final EventSummary event;
  final EventRepository repository;

  @override
  State<EventDiscussionScreen> createState() => _EventDiscussionScreenState();
}

class _EventDiscussionScreenState extends State<EventDiscussionScreen> {
  final _controller = TextEditingController();
  List<EventDiscussionMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final messages = await widget.repository.eventDiscussion(widget.event.id);
      if (mounted) {
        setState(() {
          _messages = messages;
          _error = null;
        });
      }
    } on EdgeApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load this discussion.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty || body.length > 1200 || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.repository.createDiscussionMessage(widget.event.id, body);
      _controller.clear();
      await _load();
    } on EdgeApiException catch (error) {
      if (mounted) _show(error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _report(EventDiscussionMessage message) async {
    final reason = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Report message'),
        actions: [
          for (final entry in forumReportReasons.entries)
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
      await widget.repository.reportDiscussionMessage(
        widget.event.id,
        message.id,
        reason,
      );
      if (mounted) _show('Message reported for review.');
    } on EdgeApiException catch (error) {
      if (mounted) _show(error.message);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.event.title)),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator.adaptive(
              onRefresh: _load,
              child: _messages.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 180),
                        Icon(CupertinoIcons.chat_bubble_2, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'Ask the host or help other attendees.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      itemCount: _messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: () =>
                                            Navigator.of(context).push<void>(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    PublicProfileScreen(
                                                      profileId:
                                                          message.authorId,
                                                    ),
                                              ),
                                            ),
                                        child: Text(
                                          message.authorName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(message.body),
                                      const SizedBox(height: 7),
                                      Text(
                                        DateFormat.MMMd().add_Hm().format(
                                          message.createdAt,
                                        ),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                if (!message.viewerIsAuthor)
                                  IconButton(
                                    tooltip: 'Report message',
                                    onPressed: () => _report(message),
                                    icon: const Icon(
                                      CupertinoIcons.ellipsis,
                                      size: 18,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
      bottomNavigationBar: _error == null && !widget.event.isCancelled
          ? SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  8,
                  12,
                  8 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('event-discussion-field'),
                        controller: _controller,
                        maxLength: 1200,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Ask a question…',
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send message',
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const CupertinoActivityIndicator()
                          : const Icon(CupertinoIcons.arrow_up),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
