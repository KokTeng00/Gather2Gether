import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/assistant/presentation/assistant_panel.dart';
import 'package:gather2gether/features/events/presentation/create_event_screen.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/presentation/event_detail_screen.dart';
import 'package:gather2gether/features/events/presentation/discover_screen.dart';
import 'package:gather2gether/features/events/presentation/my_events_screen.dart';
import 'package:gather2gether/features/forum/presentation/forum_screen.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/profile_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({this.inviteLink, this.onInviteConsumed, super.key});

  final Uri? inviteLink;
  final VoidCallback? onInviteConsumed;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _discoverRevision = 0;
  int _plansRevision = 0;
  int _profileRevision = 0;
  final _profiles = ProfileRepository();
  final _events = EventRepository();
  UserProfile? _profile;
  bool _assistantEnabled = true;
  bool _assistantPreferenceLoaded = false;
  Offset? _assistantOffset;
  bool _assistantIsDragging = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    if (widget.inviteLink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInviteLink(widget.inviteLink!);
      });
    }
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.inviteLink != null &&
        widget.inviteLink != oldWidget.inviteLink) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInviteLink(widget.inviteLink!);
      });
    }
  }

  Future<void> _openInviteLink(Uri uri) async {
    if (uri.scheme != 'gather2gether' || uri.host != 'event') return;
    final eventId = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    if (eventId == null ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(eventId)) {
      widget.onInviteConsumed?.call();
      return;
    }
    try {
      final event = await _events.eventDetails(eventId);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(event: event, repository: _events),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This invitation is no longer available.'),
          ),
        );
      }
    } finally {
      widget.onInviteConsumed?.call();
    }
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _profiles.fetchOwnProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _assistantEnabled = profile.assistantEnabled;
          _assistantPreferenceLoaded = true;
        });
      }
    } catch (_) {
      // Individual screens retain their own safe loading/error states.
      if (mounted) setState(() => _assistantPreferenceLoaded = true);
    }
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => CreateEventScreen(
          onCreated: () {
            Navigator.of(routeContext).pop();
            setState(() {
              _selectedIndex = 0;
              _discoverRevision++;
              _plansRevision++;
            });
          },
        ),
      ),
    );
  }

  Future<void> _openAssistant() async {
    var profile = _profile;
    if (profile == null) {
      try {
        profile = await _profiles.fetchOwnProfile();
        if (mounted) setState(() => _profile = profile);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Gather Guide.')),
          );
        }
        return;
      }
    }
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 700;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(
        maxWidth: isWide ? 560 : size.width,
        maxHeight: size.height,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SizedBox(
        width: double.infinity,
        height: size.height * (isWide ? 0.78 : 0.92),
        child: AssistantPanel(profile: profile!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          const bubbleSize = 56.0;
          final safeInsets = MediaQuery.viewPaddingOf(context);
          final area = Size(constraints.maxWidth, constraints.maxHeight);
          final fallback = Offset(
            constraints.maxWidth - bubbleSize,
            constraints.maxHeight - bubbleSize - safeInsets.bottom - 14,
          );
          final proposedPosition = _assistantOffset ?? fallback;
          final position = _assistantIsDragging
              ? clampAssistantOffset(
                  proposedPosition,
                  area: area,
                  safeInsets: safeInsets,
                  bubbleSize: bubbleSize,
                )
              : dockAssistantOffset(
                  proposedPosition,
                  area: area,
                  safeInsets: safeInsets,
                  bubbleSize: bubbleSize,
                );
          final launcher = Semantics(
            button: true,
            label:
                'Open Gather Guide. Drag to move; it snaps to the nearest screen edge.',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openAssistant,
              onPanStart: (_) => setState(() {
                _assistantIsDragging = true;
                _assistantOffset = position;
              }),
              onPanUpdate: (details) {
                setState(() {
                  _assistantOffset = clampAssistantOffset(
                    position + details.delta,
                    area: area,
                    safeInsets: safeInsets,
                    bubbleSize: bubbleSize,
                  );
                });
              },
              onPanEnd: (_) => _dockAssistant(
                position,
                area: area,
                safeInsets: safeInsets,
                bubbleSize: bubbleSize,
              ),
              onPanCancel: () => _dockAssistant(
                position,
                area: area,
                safeInsets: safeInsets,
                bubbleSize: bubbleSize,
              ),
              child: _AssistantLauncher(isDragging: _assistantIsDragging),
            ),
          );
          return Stack(
            children: [
              IndexedStack(
                index: _selectedIndex,
                children: [
                  DiscoverScreen(
                    key: ValueKey(_discoverRevision),
                    onCreate: _openCreate,
                  ),
                  MyEventsScreen(key: ValueKey(_plansRevision)),
                  const ForumScreen(),
                  ProfileScreen(
                    key: ValueKey(_profileRevision),
                    assistantEnabled: _assistantEnabled,
                    onAssistantEnabledChanged: (enabled) {
                      setState(() => _assistantEnabled = enabled);
                    },
                    onProfileChanged: (profile) {
                      setState(() {
                        _profile = profile;
                        _assistantEnabled = profile.assistantEnabled;
                        _discoverRevision++;
                      });
                    },
                  ),
                ],
              ),
              if (_assistantPreferenceLoaded && _assistantEnabled)
                AnimatedPositioned(
                  duration: _assistantIsDragging
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  left: position.dx,
                  top: position.dy,
                  child: launcher,
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: FrostedContainer(
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              if (index == 3 && _selectedIndex != 3) {
                // Refresh contribution counts and the own-post grid whenever
                // the member returns after posting in Community.
                _profileRevision++;
              }
              _selectedIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(CupertinoIcons.location),
              selectedIcon: Icon(CupertinoIcons.location_fill),
              label: 'Discover',
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.calendar),
              selectedIcon: Icon(CupertinoIcons.calendar_today),
              label: 'Plans',
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.chat_bubble_2),
              selectedIcon: Icon(CupertinoIcons.chat_bubble_2_fill),
              label: 'Community',
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.person_crop_circle),
              selectedIcon: Icon(CupertinoIcons.person_crop_circle_fill),
              label: 'You',
            ),
          ],
        ),
      ),
    );
  }

  void _dockAssistant(
    Offset fallback, {
    required Size area,
    required EdgeInsets safeInsets,
    required double bubbleSize,
  }) {
    setState(() {
      _assistantIsDragging = false;
      _assistantOffset = dockAssistantOffset(
        _assistantOffset ?? fallback,
        area: area,
        safeInsets: safeInsets,
        bubbleSize: bubbleSize,
      );
    });
  }
}

class _AssistantLauncher extends StatelessWidget {
  const _AssistantLauncher({required this.isDragging});

  final bool isDragging;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Gather Guide',
      child: AnimatedScale(
        scale: isDragging ? 1.08 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Material(
          color: colors.primary.withValues(alpha: 0.94),
          elevation: isDragging ? 8 : 4,
          shadowColor: Colors.black.withValues(alpha: 0.28),
          shape: CircleBorder(
            side: BorderSide(color: colors.onPrimary.withValues(alpha: 0.24)),
          ),
          child: SizedBox.square(
            dimension: 56,
            child: Center(
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.onPrimary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.onPrimary.withValues(alpha: 0.72),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  CupertinoIcons.bubble_left_fill,
                  color: colors.onPrimary,
                  size: 19,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Offset clampAssistantOffset(
  Offset proposed, {
  required Size area,
  required EdgeInsets safeInsets,
  double bubbleSize = 56,
  double edgeInset = 5,
}) {
  final minX = safeInsets.left + edgeInset;
  final minY = safeInsets.top + edgeInset;
  final maxX = math.max(
    minX,
    area.width - safeInsets.right - bubbleSize - edgeInset,
  );
  final maxY = math.max(
    minY,
    area.height - safeInsets.bottom - bubbleSize - edgeInset,
  );
  return Offset(
    proposed.dx.clamp(minX, maxX).toDouble(),
    proposed.dy.clamp(minY, maxY).toDouble(),
  );
}

@visibleForTesting
Offset dockAssistantOffset(
  Offset proposed, {
  required Size area,
  required EdgeInsets safeInsets,
  double bubbleSize = 56,
  double edgeInset = 5,
}) {
  final clamped = clampAssistantOffset(
    proposed,
    area: area,
    safeInsets: safeInsets,
    bubbleSize: bubbleSize,
    edgeInset: edgeInset,
  );
  final minX = safeInsets.left + edgeInset;
  final minY = safeInsets.top + edgeInset;
  final maxX = math.max(
    minX,
    area.width - safeInsets.right - bubbleSize - edgeInset,
  );
  final maxY = math.max(
    minY,
    area.height - safeInsets.bottom - bubbleSize - edgeInset,
  );
  final distances = <({double distance, Offset position})>[
    (distance: clamped.dx - minX, position: Offset(minX, clamped.dy)),
    (distance: maxX - clamped.dx, position: Offset(maxX, clamped.dy)),
    (distance: clamped.dy - minY, position: Offset(clamped.dx, minY)),
    (distance: maxY - clamped.dy, position: Offset(clamped.dx, maxY)),
  ]..sort((a, b) => a.distance.compareTo(b.distance));
  return distances.first.position;
}
