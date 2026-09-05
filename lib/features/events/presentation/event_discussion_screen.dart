import 'dart:async';

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
  bool _summarizing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    unawaited(
      widget.repository.markDiscussionSeen(widget.event.id).catchError((_) {}),
    );
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

  Future<void> _summarize() async {
    if (_summarizing) return;
    setState(() => _summarizing = true);
    try {
      final summary = await widget.repository.summarizeDiscussion(
        widget.event.id,
      );
      if (!mounted) return;
      setState(() => _summarizing = false);
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Discussion summary'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  summary.summary,
                  key: const Key('event-discussion-summary-result'),
                ),
                if (summary.actionItems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Action items',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  for (final item in summary.actionItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text('• $item'),
                    ),
                ],
              ],
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
      if (mounted) _show(error.message);
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Future<void> _summarizeChanges() async {
    if (_summarizing) return;
    setState(() => _summarizing = true);
    try {
      final changes = await widget.repository.discussionChanges(
        widget.event.id,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('What changed · ${changes.messageCount} new'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  changes.summary,
                  key: const Key('event-discussion-changes-result'),
                ),
                if (changes.actionItems.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final item in changes.actionItems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text('• $item'),
                    ),
                ],
              ],
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
      if (mounted) _show(error.message);
    } finally {
      if (mounted) setState(() => _summarizing = false);
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
      appBar: AppBar(
        title: Text(widget.event.title),
        actions: [
          IconButton(
            key: const Key('event-discussion-changes-action'),
            tooltip: 'What changed since last visit',
            onPressed: _messages.isEmpty || _summarizing
                ? null
                : _summarizeChanges,
            icon: const Icon(CupertinoIcons.clock),
          ),
          IconButton(
            key: const Key('event-discussion-summary-action'),
            tooltip: 'Summarize discussion',
            onPressed: _messages.length < 2 || _summarizing ? null : _summarize,
            icon: _summarizing
                ? const CupertinoActivityIndicator()
                : const Icon(CupertinoIcons.sparkles),
          ),
        ],
      ),
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
