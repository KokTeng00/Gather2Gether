import 'dart:math' as math;

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

  Widget _buildConversation(BuildContext context) {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 13));
    }
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
            child: Column(
              mainAxisAlignment: _messages.isEmpty
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.end,
              children: [
                if (_messages.isEmpty) _WelcomeCard(onPrompt: _send),
                for (final message in _messages)
                  _MessageBubble(message: message),
                if (_sending) const _ThinkingBubble(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom > 0
        ? mediaQuery.viewInsets.bottom + 8
        : mediaQuery.padding.bottom + 10;
    return SafeArea(
      top: false,
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: colors.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 10, 13),
            child: Row(
              children: [
                const _AssistantMark(size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gather Guide',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Your local event concierge',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _PanelIconButton(
                  tooltip: 'Clear history',
                  onPressed: _messages.isEmpty ? null : _clearHistory,
                  icon: CupertinoIcons.trash,
                ),
                const SizedBox(width: 4),
                _PanelIconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: CupertinoIcons.xmark,
                ),
              ],
            ),
          ),
          Divider(color: colors.outlineVariant.withValues(alpha: 0.7)),
          Expanded(
            child: ColoredBox(
              color: colors.surfaceContainerLowest,
              child: _buildConversation(context),
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_circle_fill,
                    size: 17,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: colors.onErrorContainer,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(14, 10, 14, bottomInset),
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
                    decoration: InputDecoration(
                      hintText: 'Message Gather Guide…',
                      counterText: '',
                      filled: true,
                      fillColor: colors.surfaceContainerLow,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 17,
                        vertical: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(23),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(23),
                        borderSide: BorderSide(
                          color: colors.outlineVariant.withValues(alpha: 0.75),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(23),
                        borderSide: BorderSide(
                          color: colors.primary,
                          width: 1.4,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 9),
                IconButton.filled(
                  tooltip: 'Send',
                  onPressed: _sending ? null : _send,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    maximumSize: const Size(48, 48),
                    shape: const CircleBorder(),
                  ),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: _sending
                        ? const CupertinoActivityIndicator(
                            key: ValueKey('sending'),
                            color: Colors.white,
                          )
                        : const Icon(
                            CupertinoIcons.arrow_up,
                            key: ValueKey('send'),
                            size: 20,
                          ),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
        child: Column(
          children: [
            const _AssistantMark(size: 48),
            const SizedBox(height: 13),
            Text(
              'How can I help?',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ask about nearby events or get help with the app.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 17),
            for (var index = 0; index < prompts.length; index++) ...[
              _PromptTile(
                label: prompts[index],
                icon: switch (index) {
                  0 => CupertinoIcons.location_fill,
                  1 => CupertinoIcons.bag_fill,
                  _ => CupertinoIcons.person_2_fill,
                },
                onTap: () => onPrompt(prompts[index]),
              ),
              if (index != prompts.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _PromptTile extends StatelessWidget {
  const _PromptTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: isUser ? colors.onPrimary : colors.onSurface,
      height: 1.45,
    );
    final timeStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant.withValues(alpha: 0.82),
      fontSize: 10.5,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.min(constraints.maxWidth * 0.88, 520.0);
        final bubble = Container(
          padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
          decoration: BoxDecoration(
            color: isUser ? colors.primary : colors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 5),
              bottomRight: Radius.circular(isUser ? 5 : 18),
            ),
            border: isUser
                ? null
                : Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.72),
                  ),
            boxShadow: isUser
                ? null
                : [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.035),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isUser)
                Text(message.content, style: textStyle)
              else
                SelectableText.rich(
                  buildAssistantTextSpan(message.content, textStyle),
                ),
              if (message.eventMatches.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final event in message.eventMatches.take(3))
                  _EventMatchCard(event: event),
              ],
            ],
          ),
        );

        if (isUser) {
          return Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    bubble,
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        DateFormat('HH:mm').format(message.createdAt),
                        style: timeStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: maxWidth,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 18),
                    child: _AssistantMark(size: 28),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 3, bottom: 5),
                          child: Text(
                            'Gather Guide',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.15,
                                ),
                          ),
                        ),
                        bubble,
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            DateFormat('HH:mm').format(message.createdAt),
                            style: timeStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                CupertinoIcons.calendar,
                size: 14,
                color: colors.onPrimaryContainer.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${DateFormat('EEE, HH:mm').format(event.startAt)} · $distance · ${event.venueName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onPrimaryContainer.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const _AssistantMark(size: 28),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(17),
                  topRight: Radius.circular(17),
                  bottomRight: Radius.circular(17),
                  bottomLeft: Radius.circular(5),
                ),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.72),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoActivityIndicator(radius: 8),
                  SizedBox(width: 9),
                  Text('Finding the best answer…'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantMark extends StatelessWidget {
  const _AssistantMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(size * 0.34),
        boxShadow: size > 30
            ? [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Icon(
        CupertinoIcons.sparkles,
        size: size * 0.48,
        color: colors.onPrimary,
      ),
    );
  }
}

class _PanelIconButton extends StatelessWidget {
  const _PanelIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onPressed == null
            ? Colors.transparent
            : colors.surfaceContainerLow,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 38,
            child: Icon(
              icon,
              size: 18,
              color: onPressed == null
                  ? colors.onSurfaceVariant.withValues(alpha: 0.35)
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
TextSpan buildAssistantTextSpan(String source, TextStyle? style) {
  final normalized = source
      .replaceAllMapped(
        RegExp(r'^[ \t]*[-*][ \t]+', multiLine: true),
        (_) => '• ',
      )
      .replaceAllMapped(
        RegExp(r'^[ \t]{0,3}#{1,3}[ \t]+', multiLine: true),
        (_) => '',
      );
  final children = <InlineSpan>[];
  var cursor = 0;
  while (cursor < normalized.length) {
    final opening = normalized.indexOf('**', cursor);
    if (opening == -1) {
      children.add(TextSpan(text: normalized.substring(cursor)));
      break;
    }
    final closing = normalized.indexOf('**', opening + 2);
    if (closing == -1) {
      children.add(TextSpan(text: normalized.substring(cursor)));
      break;
    }
    if (opening > cursor) {
      children.add(TextSpan(text: normalized.substring(cursor, opening)));
    }
    children.add(
      TextSpan(
        text: normalized.substring(opening + 2, closing),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    cursor = closing + 2;
  }
  if (children.isEmpty) children.add(const TextSpan(text: ''));
  return TextSpan(style: style, children: children);
}
