import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/assistant/presentation/assistant_panel.dart';
import 'package:gather2gether/features/events/presentation/create_event_screen.dart';
import 'package:gather2gether/features/events/presentation/discover_screen.dart';
import 'package:gather2gether/features/forum/presentation/forum_screen.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';
import 'package:gather2gether/features/profile/presentation/profile_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _discoverRevision = 0;
  final _profiles = ProfileRepository();
  UserProfile? _profile;
  bool _assistantEnabled = true;
  bool _assistantPreferenceLoaded = false;
  Offset? _assistantOffset;

  @override
  void initState() {
    super.initState();
    _loadProfile();
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.84,
        child: AssistantPanel(profile: profile!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          const bubbleSize = 58.0;
          final fallback = Offset(
            constraints.maxWidth - bubbleSize - 16,
            constraints.maxHeight - bubbleSize - 20,
          );
          final position = Offset(
            (_assistantOffset?.dx ?? fallback.dx).clamp(
              12.0,
              constraints.maxWidth - bubbleSize - 12,
            ),
            (_assistantOffset?.dy ?? fallback.dy).clamp(
              12.0,
              constraints.maxHeight - bubbleSize - 12,
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
                  const ForumScreen(),
                  ProfileScreen(
                    assistantEnabled: _assistantEnabled,
                    onAssistantEnabledChanged: (enabled) {
                      setState(() => _assistantEnabled = enabled);
                    },
                  ),
                ],
              ),
              if (_assistantPreferenceLoaded && _assistantEnabled)
                Positioned(
                  left: position.dx,
                  top: position.dy,
                  child: Semantics(
                    button: true,
                    label: 'Open Gather Guide. Drag to move.',
                    child: GestureDetector(
                      onTap: _openAssistant,
                      onPanUpdate: (details) {
                        setState(() {
                          _assistantOffset = Offset(
                            (position.dx + details.delta.dx).clamp(
                              12.0,
                              constraints.maxWidth - bubbleSize - 12,
                            ),
                            (position.dy + details.delta.dy).clamp(
                              12.0,
                              constraints.maxHeight - bubbleSize - 12,
                            ),
                          );
                        });
                      },
                      child: const _AssistantLauncher(),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: FrostedContainer(
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(CupertinoIcons.location),
              selectedIcon: Icon(CupertinoIcons.location_fill),
              label: 'Discover',
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
}

class _AssistantLauncher extends StatelessWidget {
  const _AssistantLauncher();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Gather Guide',
      child: Material(
        color: colors.primary,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(18),
        child: SizedBox.square(
          dimension: 58,
          child: Stack(
            children: [
              Center(
                child: Icon(
                  CupertinoIcons.chat_bubble_text_fill,
                  color: colors.onPrimary,
                  size: 27,
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.primary, width: 2),
                  ),
                ),
              ),
              Positioned(
                left: 7,
                top: 20,
                child: Icon(
                  CupertinoIcons.ellipsis_vertical,
                  size: 11,
                  color: colors.onPrimary.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
