import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/events/presentation/create_event_screen.dart';
import 'package:gather2gether/features/events/presentation/discover_screen.dart';
import 'package:gather2gether/features/forum/presentation/forum_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _discoverRevision = 0;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          DiscoverScreen(
            key: ValueKey(_discoverRevision),
            onCreate: _openCreate,
          ),
          const ForumScreen(),
          const ProfileScreen(),
        ],
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
