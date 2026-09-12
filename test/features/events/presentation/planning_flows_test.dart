import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_filters.dart';
import 'package:gather2gether/features/events/domain/event_lifecycle.dart';
import 'package:gather2gether/features/events/domain/event_operations.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/discover_screen.dart';
import 'package:gather2gether/features/events/presentation/create_event_screen.dart';
import 'package:gather2gether/features/events/presentation/event_detail_screen.dart';
import 'package:gather2gether/features/forum/data/forum_repository.dart';
import 'package:gather2gether/features/forum/domain/forum_post.dart';
import 'package:gather2gether/features/forum/domain/planning_poll.dart';
import 'package:gather2gether/features/forum/presentation/planning_poll_card.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';

import 'package:gather2gether/features/auth/presentation/sign_in_screen.dart';
import 'package:gather2gether/features/events/presentation/my_events_screen.dart';
import 'package:gather2gether/features/forum/presentation/forum_screen.dart';
import 'package:gather2gether/features/forum/presentation/create_forum_post_screen.dart';
import 'package:gather2gether/features/profile/domain/profile_stats.dart';
import 'package:gather2gether/features/profile/presentation/profile_screen.dart';
import 'package:gather2gether/features/profile/presentation/onboarding_screen.dart';
import 'package:gather2gether/features/profile/presentation/profile_settings_screen.dart';

import 'package:gather2gether/features/shell/presentation/app_shell.dart';
import 'package:gather2gether/features/forum/presentation/forum_post_screen.dart';
import 'package:gather2gether/features/forum/domain/forum_comment.dart';

EventSummary fixture({String? status}) => EventSummary(
  id: '22222222-2222-4222-8222-222222222222',
  organizerId: '11111111-1111-4111-8111-111111111111',
  organizerName: 'Sophie',
  title: 'Coffee & a walk by the river',
  description:
      'An easy Sunday walk along the Neckar, with a coffee stop on the way. Come as you are; we’ll keep a relaxed pace.',
  category: 'Hiking',
  venueName: 'Neckarwiese',
  address: 'Neckarpromenade, Mannheim',
  latitude: 49.49,
  longitude: 8.47,
  startAt: DateTime(2099, 9, 20, 10),
  endAt: DateTime(2099, 9, 20, 12),
  maxParticipants: 12,
  joinedCount: 5,
  tentativeCount: 1,
  distanceMeters: 1400,
  userRsvpStatus: status,
  allowGuest: true,
  meetingInstructions:
      'Meet at the steps beside the café. I’ll have a blue backpack.',
  meetingLatitude: 49.491,
  meetingLongitude: 8.471,
  beginnerFriendly: true,
);

class PlansRepository extends EventRepository {
  PlansRepository(this.event, {this.overlap = false})
    : super(
        accessTokenProvider: () => 'test',
        edgeApiUrl: 'https://test.invalid/api/v1',
      );
  EventSummary event;
  final bool overlap;
  final reservations = <({String status, int guests})>[];
  @override
  Future<EventSummary> eventDetails(
    String eventId, {
    bool viaInvite = false,
  }) async => event;
  @override
  Future<List<EventAnnouncement>> announcements(String eventId) async => [];
  @override
  Future<List<EventConflict>> conflicts(String eventId) async => overlap
      ? [
          EventConflict(
            id: 'another',
            title: 'Badminton with Alex',
            startAt: event.startAt,
            endAt: event.endAt,
          ),
        ]
      : [];
  @override
  Future<String> updateRsvpWithGuest(
    String eventId,
    String status,
    int guestCount,
  ) async {
    reservations.add((status: status, guests: guestCount));
    event = EventSummary.fromJson({
      ...event.toJson(),
      'guest_count': guestCount,
      'user_rsvp_status': status,
    });
    return status;
  }

  @override
  Future<List<EventSummary>> myEvents(String filter) async => switch (filter) {
    'going' => [event.copyWith(userRsvpStatus: 'joined')],
    'tentative' => [
      EventSummary.fromJson({
        ...event.toJson(),
        'id': 'second-plan',
        'title': 'Board games at the café',
        'venue_name': 'Café Nord',
        'user_rsvp_status': 'tentative',
        'start_at': DateTime(2099, 9, 21, 18).toUtc().toIso8601String(),
      }),
    ],
    _ => [],
  };
  @override
  Future<List<EventSummary>> nearbyEvents({
    required double latitude,
    required double longitude,
    required double radiusKm,
    String? interest,
    EventDiscoveryFilters filters = const EventDiscoveryFilters(),
  }) async => [
    event,
    EventSummary.fromJson({
      ...event.toJson(),
      'id': '33333333-3333-4333-8333-333333333333',
      'title': 'A few friendly games of badminton',
      'venue_name': 'Sporthalle Mannheim',
      'category': 'Badminton',
      'start_at': DateTime(2099, 9, 21, 18).toUtc().toIso8601String(),
    }),
  ];
}

const previewProfile = UserProfile(
  displayName: 'Alex Morgan',
  username: 'alexmorgan',
  bio: 'Coffee, weekend walks and a good game of badminton.',
  city: 'Mannheim',
  approximateLatitude: 49.49,
  approximateLongitude: 8.47,
  preferredRadiusKm: 10,
  assistantEnabled: false,
);

class PreviewProfile extends ProfileRepository {
  @override
  Future<UserProfile> fetchOwnProfile() async => previewProfile;
  @override
  Future<ProfileStats> fetchStats() async => const ProfileStats(
    postsCount: 2,
    hostedCount: 3,
    goingCount: 5,
    followersCount: 18,
    followingCount: 24,
  );
  @override
  Future<bool> isModerator() async => false;
}

class PreviewForum extends ForumRepository {
  @override
  Future<ForumPost> getPost(String postId) async => postFixture();
  @override
  Future<List<ForumComment>> listComments(String postId) async => const [];
  @override
  Future<List<ForumPost>> listPosts() async => [
    postFixture(),
    ForumPost(
      id: 'second-post',
      authorId: 'alex',
      authorName: 'Alex',
      category: 'Local tips',
      title: 'A quiet café with room for a few friends?',
      body:
          'Looking for somewhere around the river for coffee on Saturday. Any favourites?',
      status: 'active',
      createdAt: DateTime(2099, 9, 1),
      lastActivityAt: DateTime(2099, 9, 1),
      commentCount: 4,
      viewerIsAuthor: false,
    ),
  ];
  @override
  Future<List<ForumPost>> listOwnPosts() => listPosts();
}

PlanningPoll pollFixture({bool voted = false}) => PlanningPoll(
  postId: 'post',
  closed: false,
  canVote: true,
  viewerIsAuthor: false,
  options: [
    PollDateOption(
      id: 'one',
      startAt: DateTime(2099, 9, 20, 10),
      endAt: DateTime(2099, 9, 20, 12),
      voteCount: voted ? 5 : 4,
      voted: voted,
    ),
    PollDateOption(
      id: 'two',
      startAt: DateTime(2099, 9, 21, 10),
      endAt: DateTime(2099, 9, 21, 12),
      voteCount: 2,
    ),
  ],
);
ForumPost postFixture() => ForumPost(
  id: 'post',
  authorId: 'sophie',
  authorName: 'Sophie',
  category: 'Event ideas',
  title: 'A weekend walk?',
  body: 'Let’s find a day for a walk by the river.',
  status: 'active',
  createdAt: DateTime(2099, 9, 1),
  lastActivityAt: DateTime(2099, 9, 1),
  commentCount: 0,
  viewerIsAuthor: false,
  poll: pollFixture(),
  hasPoll: true,
);

class PollRepository extends ForumRepository {
  int votes = 0;
  @override
  Future<PlanningPoll> voteOnPoll(
    String postId,
    String optionId,
    bool available,
  ) async {
    votes++;
    return pollFixture(voted: available);
  }
}

// Widget tests normally draw unresolved platform fonts as squares. Preview-only
// font substitution keeps measurements and controls readable without app assets.
ThemeData previewTheme(ThemeData theme) {
  ButtonStyle? font(ButtonStyle? style) => style?.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) =>
          style.textStyle?.resolve(states)?.copyWith(fontFamily: 'Roboto'),
    ),
  );
  return theme.copyWith(
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: 'Roboto',
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: font(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: font(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: font(theme.textButtonTheme.style),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: font(theme.segmentedButtonTheme.style),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const previewDirectory = String.fromEnvironment('GATHER_PREVIEW_DIR');
  setUpAll(() async {
    if (previewDirectory.isNotEmpty) {
      final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
      if (await font.exists()) {
        final bytes = ByteData.sublistView(await font.readAsBytes());
        for (final family in [
          'Roboto',
          'Ahem',
          '.SF UI Text',
          '.SF UI Display',
          '.SF Pro Text',
          '.SF Pro Display',
          'CupertinoSystemDisplay',
          'CupertinoSystemText',
        ]) {
          await (FontLoader(family)..addFont(Future.value(bytes))).load();
        }
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
    }
  });
  testWidgets('overlap is reviewed before a reservation is written', (
    tester,
  ) async {
    final repository = PlansRepository(fixture(), overlap: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EventDetailScreen(
          event: repository.event,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('I’m Going'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Badminton with Alex'), findsOneWidget);
    expect(repository.reservations, isEmpty);
    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(repository.reservations, isEmpty);
    await tester.tap(find.text('I’m Going'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Join anyway'));
    await tester.pumpAndSettle();
    expect(repository.reservations.single, (status: 'joined', guests: 0));
  });
  testWidgets('bringing a friend updates an existing reservation', (
    tester,
  ) async {
    final repository = PlansRepository(fixture(status: 'joined'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: EventDetailScreen(
          event: repository.event,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Me + 1'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Me + 1'));
    await tester.pumpAndSettle();
    expect(repository.reservations.single.guests, 1);
  });
  testWidgets('voting changes availability without creating an event or RSVP', (
    tester,
  ) async {
    final repository = PollRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PlanningPollCard(
            post: postFixture(),
            repository: repository,
            onPublished: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    expect(repository.votes, 1);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('View event & join'), findsNothing);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'planning screens fit a phone in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = PlansRepository(fixture());
        final boundary = GlobalKey();
        final screens = <String, Widget>{
          'sign-in': const SignInScreen(),
          'discussion': ForumPostScreen(
            postId: 'post',
            repository: PreviewForum(),
          ),
          'community': Scaffold(body: ForumScreen(repository: PreviewForum())),
          'plans': Scaffold(body: MyEventsScreen(repository: repository)),
          'new-discussion': CreateForumPostScreen(repository: PreviewForum()),
          'onboarding': OnboardingScreen(
            profile: previewProfile,
            repository: PreviewProfile(),
            onCompleted: (_) {},
          ),
          'profile': Scaffold(
            body: ProfileScreen(
              assistantEnabled: false,
              onAssistantEnabledChanged: (_) {},
              repository: PreviewProfile(),
              forumRepository: PreviewForum(),
              avatarHeadersOverride: const {},
            ),
          ),
          'settings': ProfileSettingsScreen(
            profile: previewProfile,
            repository: PreviewProfile(),
            onAssistantEnabledChanged: (_) {},
            avatarHeadersOverride: const {},
            emailOverride: 'alex@example.test',
          ),
          'discover': Scaffold(
            body: DiscoverScreen(
              onCreate: () {},
              profileRepository: PreviewProfile(),
              eventRepository: repository,
            ),
          ),
          'filters': Scaffold(
            body: DiscoverScreen(
              onCreate: () {},
              profileRepository: PreviewProfile(),
              eventRepository: repository,
            ),
          ),
          'filters-full': Scaffold(
            body: DiscoverScreen(
              onCreate: () {},
              profileRepository: PreviewProfile(),
              eventRepository: repository,
            ),
          ),
          'filters-dates': Scaffold(
            body: DiscoverScreen(
              onCreate: () {},
              profileRepository: PreviewProfile(),
              eventRepository: repository,
            ),
          ),
          'filters-calendar': Scaffold(
            body: DiscoverScreen(
              onCreate: () {},
              profileRepository: PreviewProfile(),
              eventRepository: repository,
            ),
          ),
          'filters-calendar-compact': Scaffold(
            body: DiscoverScreen(
              onCreate: () {},
              profileRepository: PreviewProfile(),
              eventRepository: repository,
            ),
          ),
          'filters-compact': Scaffold(
            body: DiscoverScreen(
              onCreate: () {},
              profileRepository: PreviewProfile(),
              eventRepository: repository,
            ),
          ),
          'create': CreateEventScreen(onCreated: () {}),
          'create-options': CreateEventScreen(onCreated: () {}),
          'create-datetime': CreateEventScreen(onCreated: () {}),
          'create-datetime-compact': CreateEventScreen(onCreated: () {}),
          'event': EventDetailScreen(
            event: repository.event,
            repository: repository,
          ),
          'poll': Scaffold(
            appBar: AppBar(title: const Text('Discussion')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A weekend walk?',
                    style: (dark ? AppTheme.dark : AppTheme.light)
                        .textTheme
                        .headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text('Let’s find a day for a walk by the river.'),
                  const SizedBox(height: 28),
                  PlanningPollCard(
                    post: postFixture(),
                    repository: PollRepository(),
                    onPublished: () async {},
                  ),
                ],
              ),
            ),
          ),
        };
        for (final (name, index) in [
          ('discover', 0),
          ('plans', 1),
          ('community', 2),
          ('profile', 3),
        ]) {
          final screen = screens[name]! as Scaffold;
          screens[name] = Scaffold(
            body: screen.body,
            bottomNavigationBar: AppNavigationBar(
              selectedIndex: index,
              onDestinationSelected: (_) {},
            ),
          );
        }
        // Exercise the main screens at a narrow width with enlarged text as
        // well as their standard size; the same cases can render review PNGs.
        for (final name in [
          'sign-in',
          'discover',
          'community',
          'plans',
          'new-discussion',
          'onboarding',
          'profile',
          'settings',
          'event',
          'discussion',
        ]) {
          screens['$name-compact'] = screens[name]!;
        }
        for (final entry in screens.entries) {
          final compact = entry.key.endsWith('-compact');
          tester.view.physicalSize = compact
              ? const Size(320, 568)
              : const Size(390, 844);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                key: ValueKey(entry.key),
                debugShowCheckedModeBanner: false,
                theme: previewDirectory.isEmpty
                    ? (dark ? AppTheme.dark : AppTheme.light)
                    : previewTheme(dark ? AppTheme.dark : AppTheme.light),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(compact ? 1.4 : 1)),
                  child: child!,
                ),
                home: entry.value,
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (find.byType(AppNavigationBar).evaluate().isNotEmpty) {
            final label = find.descendant(
              of: find.byType(AppNavigationBar),
              matching: find.text('Community'),
            );
            final paragraph = tester.renderObject<RenderParagraph>(label);
            final lines = paragraph
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: 9),
                )
                .map((box) => box.top)
                .toSet();
            expect(
              lines,
              hasLength(1),
              reason: 'Navigation labels stay on one line',
            );
          }
          if (entry.key.startsWith('filters')) {
            await tester.tap(find.byKey(const Key('event-filter-action')));
            await tester.pumpAndSettle();
            expect(find.byKey(const Key('event-time-filter')), findsOneWidget);
            expect(find.byKey(const Key('event-custom-dates')), findsNothing);
            if (entry.key != 'filters') {
              await tester.tap(find.byKey(const Key('app-sheet-drag-handle')));
              await tester.pumpAndSettle();
            }
            if (entry.key == 'filters-dates' ||
                entry.key.startsWith('filters-calendar') ||
                compact) {
              await tester.tap(find.text('Date'));
              await tester.pumpAndSettle();
            }
            expect(
              find.byKey(const Key('apply-event-filters')).hitTestable(),
              findsOneWidget,
            );
          }
          if (entry.key.startsWith('filters-calendar')) {
            await tester.ensureVisible(
              find.byKey(const Key('event-custom-dates')),
            );
            await tester.tap(find.byKey(const Key('event-custom-dates')));
            await tester.pumpAndSettle();
            if (compact) {
              await tester.tap(
                find.byKey(const Key('app-sheet-drag-handle')).last,
              );
              await tester.pumpAndSettle();
            }
            expect(
              find.byKey(const Key('use-calendar-dates')).hitTestable(),
              findsOneWidget,
            );
          }
          if (entry.key.startsWith('create-datetime')) {
            await tester.ensureVisible(
              find.byKey(const Key('event-start-date-time')),
            );
            await tester.tap(find.byKey(const Key('event-start-date-time')));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const Key('use-event-date-time')).hitTestable(),
              findsOneWidget,
            );
          }
          if (entry.key == 'create-options') {
            await Scrollable.ensureVisible(
              tester.element(find.text('Optional details')),
              alignment: 0,
            );
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          if (previewDirectory.isNotEmpty) {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await render.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(previewDirectory).create(recursive: true);
              await File(
                '$previewDirectory/${entry.key}-${dark ? 'dark' : 'light'}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          if ([
            'event',
            'event-compact',
            'discussion',
            'discussion-compact',
            'new-discussion',
            'new-discussion-compact',
            'settings',
            'settings-compact',
            'onboarding',
            'onboarding-compact',
          ].contains(entry.key)) {
            final scrollables = find.byType(Scrollable);
            if (scrollables.evaluate().isNotEmpty) {
              final state = tester.state<ScrollableState>(scrollables.first);
              for (var step = 0; step < 12; step++) {
                final position = state.position;
                if (position.extentAfter <= 0) break;
                position.jumpTo(
                  (position.pixels + 300).clamp(0, position.maxScrollExtent),
                );
                await tester.pumpAndSettle();
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '${entry.key}, scroll $step',
                );
              }
            }
          }
        }
      },
    );
  }
}
