import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_date_range_sheet.dart';
import 'package:gather2gether/features/places/data/place_repository.dart';
import 'package:gather2gether/features/places/domain/place_suggestion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_filters.dart';
import 'package:gather2gether/features/events/domain/event_operations.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/discover_screen.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/user_profile.dart';

class _OtherCityRepository extends PlaceRepository {
  @override
  Future<List<PlaceSuggestion>> autocomplete({
    required String text,
    double? latitude,
    double? longitude,
    String? language,
  }) async => const [
    PlaceSuggestion(
      id: 'heidelberg',
      name: 'Heidelberg',
      formattedAddress: 'Heidelberg, Germany',
      latitude: 49.4,
      longitude: 8.7,
    ),
  ];
}

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

class _PreferenceProfileRepository extends ProfileRepository {
  @override
  Future<UserProfile> fetchOwnProfile() async => const UserProfile(
    displayName: 'Alex',
    city: 'Berlin',
    preferredRadiusKm: 10,
    approximateLatitude: 52.52,
    approximateLongitude: 13.405,
    assistantEnabled: true,
    interests: ['Photography'],
    accessibilityPreferences: ['wheelchair_accessible'],
  );
}

class _CapturingEventRepository extends EventRepository {
  _CapturingEventRepository({this.failSearchAlerts = false});

  final bool failSearchAlerts;
  EventDiscoveryFilters? filters;
  double? radiusKm;
  double? latitude;
  double? longitude;
  String? interest;
  String? naturalQuery;
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
    this.latitude = latitude;
    this.longitude = longitude;
    this.filters = filters;
    this.radiusKm = radiusKm;
    this.interest = interest;
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
  Future<NaturalEventFilters> naturalEventFilters(String query) async {
    naturalQuery = query;
    return const NaturalEventFilters(
      interest: 'Outdoors',
      radiusKm: 10,
      filters: EventDiscoveryFilters(eventSetting: 'outdoor'),
    );
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

Future<void> _expandDates(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Date'));
  await tester.tap(find.text('Date'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'choosing another city searches there without changing the home profile',
    (tester) async {
      final events = _CapturingEventRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: DiscoverScreen(
              onCreate: () {},
              profileRepository: _AvailableProfileRepository(),
              eventRepository: events,
              placeRepository: _OtherCityRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(events.latitude, 52.52);
      await tester.tap(find.byKey(const Key('discover-area-action')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'Heidelberg');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('place-suggestion-heidelberg')),
      );
      await tester.pumpAndSettle();
      expect(events.latitude, 49.4);
      expect(events.longitude, 8.7);
      expect(find.text('Heidelberg'), findsOneWidget);
    },
  );

  testWidgets('custom dates remain editable after applying the filter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    await _expandDates(tester);
    await tester.ensureVisible(find.byKey(const Key('event-custom-dates')));
    await tester.tap(find.byKey(const Key('event-custom-dates')));
    await tester.pumpAndSettle();
    final date = DateTime.now().add(const Duration(days: 14));
    final range = DateTimeRange(
      start: DateTime(date.year, date.month, date.day),
      end: DateTime(date.year, date.month, date.day + 2),
    );
    final calendar = find.byType(AppDateRangeSheet);
    final calendarSheet = find.descendant(
      of: calendar,
      matching: find.byKey(const Key('app-sheet')),
    );
    final calendarHeader = find.descendant(
      of: calendar,
      matching: find.byKey(const Key('app-sheet-header')),
    );
    expect(tester.getTopLeft(calendarSheet).dy, closeTo(844 * 0.4, 1));
    await tester.drag(calendarHeader, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(calendarSheet).dy, closeTo(0, 1));
    for (final day in [range.start, range.end]) {
      final cell = find.byKey(
        ValueKey('calendar-day-${day.year}-${day.month}-${day.day}'),
      );
      await tester.scrollUntilVisible(
        cell,
        250,
        scrollable: find.descendant(
          of: find.byKey(const Key('date-range-calendar')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(cell);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('use-calendar-dates')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('apply-event-filters')));
    await tester.tap(find.byKey(const Key('apply-event-filters')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event-custom-dates')), findsNothing);
    expect(events.filters?.customStart, range.start);
    expect(
      events.filters?.customEnd,
      DateTime(date.year, date.month, date.day + 3),
    );
    await tester.tap(find.byKey(const Key('event-filter-action')));
    await tester.pumpAndSettle();
    await _expandDates(tester);
    await tester.ensureVisible(find.byKey(const Key('event-custom-dates')));
    await tester.tap(find.byKey(const Key('event-custom-dates')));
    await tester.pumpAndSettle();
    expect(calendar, findsOneWidget);
    final picker = tester.widget<AppDateRangeSheet>(calendar);
    expect(picker.initialDateRange, range);
    await tester.tap(find.byKey(const Key('clear-calendar-dates')));
    await tester.drag(calendarHeader, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('event-custom-dates')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('reset-event-filters')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('event-date-summary'))).data,
      'Any date',
    );
    await tester.tap(find.byKey(const Key('apply-event-filters')));
    await tester.pumpAndSettle();
    expect(events.filters?.customStart, isNull);
    expect(events.filters?.customEnd, isNull);
    expect(events.filters?.dateFilter, 'any');
  });

  testWidgets('onboarding choices personalize without repacking discovery', (
    tester,
  ) async {
    final events = _CapturingEventRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: DiscoverScreen(
            onCreate: () {},
            profileRepository: _PreferenceProfileRepository(),
            eventRepository: events,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(events.filters?.wheelchairAccessibleOnly, isTrue);
    expect(find.text('Photography'), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.byKey(const Key('natural-event-filter-action')), findsNothing);
    expect(find.byKey(const Key('event-view-action')), findsOneWidget);
  });

  testWidgets('search submits directly without a sparkle action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

    await tester.enterText(
      find.byKey(const Key('interest-search-field')),
      'An outdoor beginner event this weekend',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(events.naturalQuery, isNull);
    expect(events.interest, 'An outdoor beginner event this weekend');
    expect(find.byKey(const Key('natural-event-filter-action')), findsNothing);
    expect(find.text('Describe what you want'), findsNothing);
    expect(find.byKey(const Key('natural-event-filter-field')), findsNothing);
    expect(find.text('Search refined.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved-area failures offer a retry without claiming maintenance',
    (tester) async {
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

      expect(
        find.byKey(const Key('discover-maintenance-state')),
        findsOneWidget,
      );
      expect(find.text('MAINTENANCE'), findsNothing);
      expect(find.text('Couldn’t load this'), findsOneWidget);
      expect(find.text('We could not load your saved area.'), findsNothing);
      expect(find.text('schema detail hidden from UI'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Within 10 km'), findsOneWidget);
      expect(find.byTooltip('Use current location'), findsNothing);
      expect(find.byKey(const Key('create-event-action')), findsOneWidget);
      final searchField = tester.widget<TextField>(
        find.byKey(const Key('interest-search-field')),
      );
      expect(searchField.decoration?.hintText, 'Search events');
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'filter sheet resizes and discards unapplied changes in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final events = _CapturingEventRepository();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
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
        await _expandDates(tester);
        await tester.tap(find.byKey(const ValueKey('event-date-tomorrow')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('event-date-tomorrow')), findsNothing);
        expect(
          tester.widget<Text>(find.byKey(const Key('event-date-summary'))).data,
          'Tomorrow',
        );
        expect(events.filters?.dateFilter, 'any');
        final sheet = find.byKey(const Key('app-sheet'));
        expect(sheet, findsOneWidget);
        expect(
          find.byKey(const Key('apply-event-filters')).hitTestable(),
          findsOneWidget,
        );
        final header = find.byKey(const Key('app-sheet-header'));
        expect(tester.getTopLeft(sheet).dy, closeTo(844 * 0.4, 1));
        expect(
          tester
              .getCenter(
                find.descendant(of: header, matching: find.text('Filters')),
              )
              .dx,
          closeTo(195, 1),
        );
        expect(find.byTooltip('Close'), findsNothing);
        expect(
          tester.widget<Material>(sheet).color,
          (dark ? AppTheme.dark : AppTheme.light).colorScheme.surface,
        );
        await tester.ensureVisible(
          find.byKey(const Key('event-distance-filter')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('event-distance-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('app-choice-25 km')));
        await tester.pumpAndSettle();
        // Sheet resizing starts when the attached list is at its top.
        tester
            .widget<SingleChildScrollView>(
              find.byKey(const Key('event-filters-list')),
            )
            .controller!
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const Key('event-filters-list')),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(sheet).dy, closeTo(0, 1));
        await tester.ensureVisible(find.byKey(const Key('event-spots-filter')));
        await tester.tap(find.byKey(const Key('event-spots-filter')));
        await tester.pumpAndSettle();
        await tester.drag(header, const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(sheet).dy, closeTo(844 * 0.4, 1));
        expect(find.text('25 km'), findsOneWidget);
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const Key('event-spots-filter')),
              )
              .value,
          isTrue,
        );
        expect(events.radiusKm, 10);
        expect(events.filters?.spotsOnly, isFalse);

        // Reset stays reachable in the header even after scrolling the options.
        await tester.tap(find.byKey(const Key('reset-event-filters')));
        await tester.pumpAndSettle();
        expect(find.text('10 km'), findsOneWidget);
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const Key('event-spots-filter')),
              )
              .value,
          isFalse,
        );
        await tester.ensureVisible(find.byKey(const Key('event-spots-filter')));
        await tester.tap(find.byKey(const Key('event-spots-filter')));
        await tester.pumpAndSettle();
        await tester.drag(header, const Offset(0, 400));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(events.filters?.spotsOnly, isFalse);

        await tester.tap(find.byKey(const Key('event-filter-action')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('event-spots-filter')), findsOneWidget);
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const Key('event-spots-filter')),
              )
              .value,
          isFalse,
        );
        expect(find.text('10 km'), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('event-date-summary'))).data,
          'Any date',
        );
        expect(find.byKey(const ValueKey('event-date-any')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('date choices collapse while other filters stay available', (
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
    expect(find.text('50 km'), findsNothing);
    expect(find.byKey(const ValueKey('event-date-weekend')), findsNothing);
    expect(find.text('More filters'), findsNothing);
    expect(find.byKey(const Key('event-time-filter')), findsOneWidget);
    await _expandDates(tester);
    await tester.tap(find.byKey(const ValueKey('event-date-weekend')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-sheet')), findsOneWidget);
    expect(events.filters?.dateFilter, 'any');
    await tester.ensureVisible(find.byKey(const Key('event-distance-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('event-distance-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-choice-25 km')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('event-spots-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('event-spots-filter')));
    await tester.ensureVisible(find.byKey(const Key('event-following-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('event-following-filter')));
    await tester.ensureVisible(find.byKey(const Key('event-language-filter')));
    await tester.enterText(
      find.byKey(const Key('event-language-filter')),
      'German',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event-spots-filter')), findsOneWidget);
    expect(find.byKey(const Key('event-language-filter')), findsOneWidget);
    expect(find.byKey(const ValueKey('event-date-weekend')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('event-date-summary'))).data,
      'This weekend',
    );
    expect(events.filters?.eventLanguage, isEmpty);
    await tester.ensureVisible(find.byKey(const Key('apply-event-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-event-filters')));
    await tester.pumpAndSettle();

    expect(events.filters?.spotsOnly, isTrue);
    expect(events.filters?.followingOnly, isTrue);
    expect(events.filters?.dateFilter, 'weekend');
    expect(events.radiusKm, 25);
    expect(find.text('Within 25 km'), findsOneWidget);
    expect(events.filters?.eventLanguage, 'German');

    await tester.tap(find.byKey(const Key('event-filter-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event-spots-filter')), findsOneWidget);
    expect(find.byKey(const ValueKey('event-date-weekend')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('event-date-summary'))).data,
      'This weekend',
    );
    await tester.tap(find.byKey(const Key('reset-event-filters')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event-spots-filter')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('event-date-summary'))).data,
      'Any date',
    );
    await tester.tap(find.byKey(const Key('apply-event-filters')));
    await tester.pumpAndSettle();
    expect(events.filters?.spotsOnly, isFalse);
    expect(events.filters?.followingOnly, isFalse);
    expect(events.filters?.eventLanguage, isEmpty);
    expect(events.filters?.dateFilter, 'any');
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
    expect(find.byKey(const Key('search-alerts-action')), findsNothing);

    await tester.tap(find.byKey(const Key('event-filter-action')));
    await tester.pumpAndSettle();
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

    await tester.tap(find.byKey(const Key('event-filter-action')));
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
