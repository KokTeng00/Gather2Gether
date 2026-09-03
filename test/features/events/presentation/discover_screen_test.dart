import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_filters.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/discover_screen.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';

class _UnavailableProfileRepository extends ProfileRepository {
  @override
  Future<UserProfile> fetchOwnProfile() async {
    throw StateError('schema detail hidden from UI');
  }
}

class _AvailableProfileRepository extends ProfileRepository {
  @override
  Future<UserProfile> fetchOwnProfile() async => const UserProfile(
    displayName: 'Alex',
    city: 'Berlin',
    preferredRadiusKm: 10,
    approximateLatitude: 52.52,
    approximateLongitude: 13.405,
    assistantEnabled: true,
  );
}

class _CapturingEventRepository extends EventRepository {
  _CapturingEventRepository({this.failSearchAlerts = false});

  final bool failSearchAlerts;
  EventDiscoveryFilters? filters;
  String? savedSearchName;
  final savedSearchItems = <SavedEventSearch>[];

  @override
  Future<List<EventSummary>> nearbyEvents({
    required double latitude,
    required double longitude,
    required double radiusKm,
    String? interest,
    EventDiscoveryFilters filters = const EventDiscoveryFilters(),
  }) async {
    this.filters = filters;
    return const [];
  }

  @override
  Future<List<SavedEventSearch>> savedSearches() async {
    if (failSearchAlerts) {
      throw const EdgeApiException(
        statusCode: 404,
        code: 'route_not_found',
        message: 'API route was not found.',
      );
    }
    return List.unmodifiable(savedSearchItems);
  }

  @override
  Future<String> saveSearch({
    required String name,
    required String interest,
    required double radiusKm,
    required EventDiscoveryFilters filters,
  }) async {
    savedSearchName = name;
    const id = '88888888-8888-4888-8888-888888888888';
    savedSearchItems
      ..removeWhere((search) => search.name == name)
      ..add(
        SavedEventSearch(
          id: id,
          name: name,
          interest: interest,
          radiusKm: radiusKm,
          filters: filters,
          alertsEnabled: true,
          createdAt: DateTime(2026, 9, 3),
        ),
      );
    return id;
  }
}

void main() {
  testWidgets('saved-area failures use neutral maintenance messaging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DiscoverScreen(
            onCreate: () {},
            profileRepository: _UnavailableProfileRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('discover-maintenance-state')), findsOneWidget);
    expect(find.text('MAINTENANCE'), findsOneWidget);
    expect(find.text('We’ll be back soon'), findsOneWidget);
    expect(find.text('We could not load your saved area.'), findsNothing);
    expect(find.text('schema detail hidden from UI'), findsNothing);
    expect(find.text('Check again'), findsOneWidget);
    expect(find.text('Nearby events'), findsOneWidget);
    expect(find.byTooltip('Use current location'), findsNothing);
    expect(find.byKey(const Key('create-event-action')), findsOneWidget);
    final searchField = tester.widget<TextField>(
      find.byKey(const Key('interest-search-field')),
    );
    expect(searchField.decoration?.hintText, 'Search events');
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick filters include availability and followed hosts', (
    tester,
  ) async {
    final events = _CapturingEventRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DiscoverScreen(
            onCreate: () {},
            profileRepository: _AvailableProfileRepository(),
            eventRepository: events,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('event-filter-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('event-spots-filter')));
    await tester.ensureVisible(find.byKey(const Key('event-following-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('event-following-filter')));
    await tester.ensureVisible(find.byKey(const Key('apply-event-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-event-filters')));
    await tester.pumpAndSettle();

    expect(events.filters?.spotsOnly, isTrue);
    expect(events.filters?.followingOnly, isTrue);
    expect(find.text('Filters on'), findsOneWidget);
  });

  testWidgets('one search alerts flow creates and manages alerts', (
    tester,
  ) async {
    final events = _CapturingEventRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DiscoverScreen(
            onCreate: () {},
            profileRepository: _AvailableProfileRepository(),
            eventRepository: events,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('save-search-action')), findsNothing);
    expect(find.byKey(const Key('saved-searches-action')), findsNothing);
    expect(find.byKey(const Key('search-alerts-action')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('search-alerts-action')));
    await tester.tap(find.byKey(const Key('search-alerts-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('search-alerts-title')), findsOneWidget);
    expect(find.text('Get alerts for this search'), findsOneWidget);
    expect(find.text('Your alerts'), findsOneWidget);
    expect(find.byKey(const Key('saved-search-name')), findsNothing);

    await tester.tap(find.byKey(const Key('create-search-alert')));
    await tester.pumpAndSettle();

    expect(events.savedSearchName, 'Nearby events');
    expect(find.text('Search alert created.'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('saved-search-88888888-8888-4888-8888-888888888888'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('search alert route failures use simple user-facing copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DiscoverScreen(
            onCreate: () {},
            profileRepository: _AvailableProfileRepository(),
            eventRepository: _CapturingEventRepository(failSearchAlerts: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('search-alerts-action')));
    await tester.tap(find.byKey(const Key('search-alerts-action')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Search alerts are unavailable right now. Please try again later.',
      ),
      findsOneWidget,
    );
    expect(find.text('API route was not found.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
