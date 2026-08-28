import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/location/location_service.dart';
import 'package:gather2gether/features/assistant/data/assistant_repository.dart';
import 'package:gather2gether/features/assistant/domain/assistant_message.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:intl/intl.dart';

class AssistantPanel extends StatefulWidget {
  const AssistantPanel({required this.profile, this.repository, super.key});

  final UserProfile profile;
  final AssistantRepository? repository;

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _location = const LocationService();
  late final AssistantRepository _repository;

  List<AssistantMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AssistantRepository();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _repository.history();
      if (mounted) setState(() => _messages = history);
      _scrollToEnd();
    } on AssistantApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load your conversation.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send([String? suggestedMessage]) async {
    final message = (suggestedMessage ?? _controller.text).trim();
    if (message.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    _controller.clear();
    setState(() {
      _sending = true;
      _error = null;
    });

    var latitude = widget.profile.approximateLatitude;
    var longitude = widget.profile.approximateLongitude;
    if (latitude == null && _looksLocationAware(message)) {
      try {
        final position = await _location.currentPosition();
        latitude = position.latitude;
        longitude = position.longitude;
      } on LocationFailure {
        // The server will return useful profile/location guidance in its answer.
      } catch (_) {
        // The model can still give settings guidance without a location.
      }
    }
    if (!mounted) return;

    final optimistic = AssistantMessage(
      id: -DateTime.now().microsecondsSinceEpoch,
      role: 'user',
      content: message,
      createdAt: DateTime.now(),
    );
    setState(() {
      _messages = [..._messages, optimistic];
    });
    _scrollToEnd();

    try {
      final reply = await _repository.sendMessage(
        message: message,
        latitude: latitude,
        longitude: longitude,
        radiusKm: widget.profile.preferredRadiusKm,
      );
      if (mounted) {
        setState(() => _messages = [..._messages, reply.message]);
        _scrollToEnd();
      }
    } on AssistantApiException catch (error) {
      if (mounted) {
        setState(() {
          _messages = _messages
              .where((item) => item.id != optimistic.id)
              .toList();
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages = _messages
              .where((item) => item.id != optimistic.id)
              .toList();
          _error = 'Gather Guide could not answer right now.';
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _looksLocationAware(String message) => RegExp(
    r'\b(near me|nearby|around me|close by|local event|what.?s on|find.*event)\b',
    caseSensitive: false,
  ).hasMatch(message);

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
          'This permanently removes your Gather Guide chat history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.clearHistory();
      if (mounted) setState(() => _messages = const []);
    } on AssistantApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'G',
                    style: TextStyle(
                      color: colors.onPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gather Guide',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Events nearby & app help',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Clear history',
                  onPressed: _messages.isEmpty ? null : _clearHistory,
                  icon: const Icon(CupertinoIcons.trash, size: 20),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(CupertinoIcons.xmark, size: 20),
                ),
              ],
            ),
          ),
          Divider(color: colors.outlineVariant),
          Expanded(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator(radius: 13))
                : ListView(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    children: [
                      if (_messages.isEmpty) _WelcomeCard(onPrompt: _send),
                      for (final message in _messages)
                        _MessageBubble(message: message),
                      if (_sending) const _ThinkingBubble(),
                    ],
                  ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: colors.onErrorContainer, fontSize: 13),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              12 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 600,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Ask about events or the app…',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 9),
                IconButton.filled(
                  tooltip: 'Send',
                  onPressed: _sending ? null : _send,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(50, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: _sending
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : const Icon(CupertinoIcons.arrow_up, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const prompts = [
      'What events are nearby?',
      'What should I bring to an event?',
      'How do I join an event?',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A useful local, not a know-it-all.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Ask what is happening near you, what to prepare, or how something in Gather2Gether works.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          for (final prompt in prompts)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: OutlinedButton(
                onPressed: () => onPrompt(prompt),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  alignment: Alignment.centerLeft,
                  backgroundColor: colors.surface,
                ),
                child: Text(prompt),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
        decoration: BoxDecoration(
          color: isUser ? colors.primary : colors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(isUser ? 15 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 15),
          ),
          border: isUser ? null : Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isUser ? colors.onPrimary : colors.onSurface,
              ),
            ),
            if (message.eventMatches.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final event in message.eventMatches.take(3))
                _EventMatchCard(event: event),
            ],
          ],
        ),
      ),
    );
  }
}

class _EventMatchCard extends StatelessWidget {
  const _EventMatchCard({required this.event});

  final AssistantEventMatch event;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final distance = event.distanceMeters < 1000
        ? '${event.distanceMeters.round()} m'
        : '${(event.distanceMeters / 1000).toStringAsFixed(1)} km';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 3),
          Text(
            '${DateFormat('EEE, HH:mm').format(event.startAt)} · $distance · ${event.venueName}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoActivityIndicator(radius: 8),
          SizedBox(width: 9),
          Text('Checking…'),
        ],
      ),
    ),
  );
}
