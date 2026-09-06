import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/theme/app_sheet.dart';
import 'package:gather2gether/core/location/location_service.dart';
import 'package:gather2gether/core/constants/event_categories.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/domain/event_filters.dart';
import 'package:gather2gether/features/events/presentation/event_detail_screen.dart';
import 'package:gather2gether/features/events/presentation/event_map.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:intl/intl.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    required this.onCreate,
    this.profileRepository,
    this.eventRepository,
    super.key,
  });

  final VoidCallback onCreate;
  final ProfileRepository? profileRepository;
  final EventRepository? eventRepository;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late final EventRepository _events;
  final _location = const LocationService();
  final _interestController = TextEditingController();
  final _scrollController = ScrollController();
  late final ProfileRepository _profiles;

  List<EventSummary> _results = const [];
  double? _latitude;
  double? _longitude;
  double _radiusKm = 10;
  bool _loading = true;
  bool _showMap = false;
  bool _maintenance = false;
  bool _offline = false;
  String? _locationNotice;
  String? _interest;
  EventDiscoveryFilters _filters = const EventDiscoveryFilters();

  @override
  void dispose() {
    _interestController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _profiles = widget.profileRepository ?? ProfileRepository();
    _events = widget.eventRepository ?? EventRepository();
    _loadSavedLocation();
  }

  Future<void> _loadSavedLocation() async {
    setState(() {
      _loading = true;
      _maintenance = false;
      _locationNotice = null;
    });
    try {
      final profile = await _profiles.fetchOwnProfile();
      _radiusKm = profile.preferredRadiusKm;
      _latitude = profile.approximateLatitude;
      _longitude = profile.approximateLongitude;
      _filters = _filters.copyWith(
        beginnerFriendlyOnly:
            _filters.beginnerFriendlyOnly ||
            profile.accessibilityPreferences.contains('beginner_friendly'),
        wheelchairAccessibleOnly:
            _filters.wheelchairAccessibleOnly ||
            profile.accessibilityPreferences.contains('wheelchair_accessible'),
      );
      if (_latitude != null && _longitude != null) await _loadEvents();
    } catch (_) {
      _maintenance = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useCurrentLocation({bool showLoading = true}) async {
    setState(() {
      if (showLoading) _loading = true;
      _maintenance = false;
      _locationNotice = null;
    });
    try {
      final position = await _location.currentPosition();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
      await _loadEvents();
    } on LocationFailure catch (failure) {
      _locationNotice = 'Location access is needed to show nearby events.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Location access is needed to show nearby events.',
            ),
            action: failure.canOpenSettings
                ? SnackBarAction(
                    label: 'Settings',
                    onPressed: _location.openSettings,
                  )
                : null,
          ),
        );
      }
    } catch (_) {
      if (showLoading) {
        _maintenance = true;
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update your location.')),
        );
      }
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  Future<void> _recenterMap() => _useCurrentLocation(showLoading: false);

  Future<void> _loadEvents() async {
    final latitude = _latitude;
    final longitude = _longitude;
    if (latitude == null || longitude == null) return;
    try {
      final results = await _events.nearbyEvents(
        latitude: latitude,
        longitude: longitude,
        radiusKm: _radiusKm,
        interest: _interest,
        filters: _filters,
      );
      if (mounted) {
        setState(() {
          _results = results;
          _maintenance = false;
          _offline = _events.lastReadWasOffline;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _maintenance = true);
      }
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _loadEvents();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _applyInterest(String value) async {
    final normalized = value.trim();
    setState(() {
      _interest = normalized.isEmpty ? null : normalized;
      _loading = true;
    });
    FocusScope.of(context).unfocus();
    await _loadEvents();
    if (mounted) setState(() => _loading = false);
  }

  void _clearInterest() {
    _interestController.clear();
    _applyInterest('');
  }

  Future<void> _openFilters() async {
    final selected = await showAppSheet<_EventFilterSelection>(
      context: context,
      builder: (_) => _EventFilterSheet(
        initial: _filters,
        initialRadiusKm: _radiusKm,
        canUseSearchAlerts: _latitude != null && _longitude != null,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _filters = selected.filters;
      _radiusKm = selected.radiusKm;
    });
    if (selected.openSearchAlerts) {
      final appliedAlert = await _openSearchAlerts();
      if (appliedAlert) return;
    }
    if (!mounted) return;
    setState(() => _loading = true);
    await _loadEvents();
    if (mounted) setState(() => _loading = false);
  }

  Future<bool> _openSearchAlerts() async {
    final selected = await showModalBottomSheet<SavedEventSearch>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _SearchAlertsSheet(
        repository: _events,
        interest: _interest ?? '',
        radiusKm: _radiusKm,
        filters: _filters,
      ),
    );
    if (selected == null || !mounted) return false;
    _interestController.text = selected.interest;
    setState(() {
      _interest = selected.interest.trim().isEmpty ? null : selected.interest;
      _radiusKm = selected.radiusKm;
      _filters = selected.filters;
      _loading = true;
    });
    await _loadEvents();
    if (mounted) setState(() => _loading = false);
    return true;
  }

  void _setShowMap(bool value) {
    setState(() => _showMap = value);
    if (!value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  Future<void> _openEvent(EventSummary event) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final mapVisible =
        _showMap &&
        !_loading &&
        !_maintenance &&
        _latitude != null &&
        _longitude != null;
    return SafeArea(
      child: RefreshIndicator.adaptive(
        onRefresh: _refresh,
        child: CustomScrollView(
          key: const Key('discover-scroll-view'),
          controller: _scrollController,
          physics: mapVisible
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              sliver: SliverToBoxAdapter(
                child: AppPageHeader(
                  title: 'Discover',
                  subtitle: 'Find something worth going out for.',
                  actions: [
                    AppCircleButton(
                      key: const Key('create-event-action'),
                      icon: CupertinoIcons.calendar_badge_plus,
                      tooltip: 'Create event',
                      onPressed: widget.onCreate,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              sliver: SliverToBoxAdapter(
                child: AppInterestSearch(
                  key: const Key('event-interest-search'),
                  controller: _interestController,
                  enabled: !_loading && _latitude != null,
                  hintText: 'What would you like to do?',
                  onSubmitted: _applyInterest,
                  onClear: _clearInterest,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _interest == null
                            ? 'Nearby · ${_radiusKm.toInt()} km'
                            : 'Results · ${_radiusKm.toInt()} km',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    SizedBox.square(
                      dimension: 40,
                      child: IconButton(
                        key: const Key('event-filter-action'),
                        tooltip: 'Filters',
                        style: IconButton.styleFrom(
                          backgroundColor: _filters.isActive
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : Colors.transparent,
                        ),
                        onPressed: _loading ? null : _openFilters,
                        icon: const Icon(
                          CupertinoIcons.slider_horizontal_3,
                          size: 19,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox.square(
                      dimension: 40,
                      child: IconButton(
                        key: const Key('event-view-action'),
                        padding: EdgeInsets.zero,
                        tooltip: _showMap
                            ? 'Show events list'
                            : 'Show event map',
                        style: IconButton.styleFrom(
                          backgroundColor: _showMap
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : Colors.transparent,
                        ),
                        onPressed:
                            _loading || _latitude == null || _longitude == null
                            ? null
                            : () => _setShowMap(!_showMap),
                        icon: Icon(
                          _showMap
                              ? CupertinoIcons.list_bullet
                              : CupertinoIcons.map,
                          size: 19,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_offline)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: MaterialBanner(
                    content: const Text(
                      'Showing your most recent saved events while offline.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CupertinoActivityIndicator(radius: 14)),
              )
            else if (_maintenance)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                  child: AppMaintenanceState(
                    key: const Key('discover-maintenance-state'),
                    onRetry: _latitude == null || _longitude == null
                        ? _loadSavedLocation
                        : _refresh,
                  ),
                ),
              )
            else if (_latitude == null || _longitude == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _LocationPrompt(
                  notice: _locationNotice,
                  onPressed: _useCurrentLocation,
                ),
              )
            else if (_showMap)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverFillRemaining(
                  hasScrollBody: false,
                  child: EventMap(
                    key: ValueKey('$_latitude:$_longitude:$_radiusKm'),
                    latitude: _latitude!,
                    longitude: _longitude!,
                    radiusKm: _radiusKm,
                    events: _results,
                    onEventSelected: _openEvent,
                    onRecenterRequested: _recenterMap,
                  ),
                ),
              )
            else if (_results.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyResults(),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: AppHeroArt(
                    label: _results.first.category,
                    title: _results.first.title,
                    subtitle:
                        '${DateFormat('EEE, d MMM · HH:mm').format(_results.first.startAt)}  ·  ${_results.first.venueName}',
                    height: 236,
                    onTap: () => _openEvent(_results.first),
                  ),
                ),
              ),
              if (_results.length > 1) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      _interest == null ? 'More nearby' : 'More results',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  sliver: SliverList.separated(
                    itemCount: _results.length - 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final event = _results[index + 1];
                      return _EventRow(
                        event: event,
                        onTap: () => _openEvent(event),
                      );
                    },
                  ),
                ),
              ] else
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onTap});

  final EventSummary event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visual = CategoryVisual.resolve(context, event.category);
    final colors = Theme.of(context).colorScheme;
    final distance = event.distanceMeters < 1000
        ? '${event.distanceMeters.round()} m'
        : '${(event.distanceMeters / 1000).toStringAsFixed(1)} km';
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 90,
                height: 96,
                decoration: BoxDecoration(
                  color: visual.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: visual.ink.withValues(alpha: 0.18)),
                ),
                child: Icon(visual.icon, size: 38, color: visual.ink),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEE, d MMM · HH:mm').format(event.startAt),
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${event.venueName} · $distance',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventFilterSelection {
  const _EventFilterSelection({
    required this.filters,
    required this.radiusKm,
    this.openSearchAlerts = false,
  });

  final EventDiscoveryFilters filters;
  final double radiusKm;
  final bool openSearchAlerts;
}

class _EventFilterSheet extends StatefulWidget {
  const _EventFilterSheet({
    required this.initial,
    required this.initialRadiusKm,
    required this.canUseSearchAlerts,
  });

  final EventDiscoveryFilters initial;
  final double initialRadiusKm;
  final bool canUseSearchAlerts;

  @override
  State<_EventFilterSheet> createState() => _EventFilterSheetState();
}

class _EventFilterSheetState extends State<_EventFilterSheet> {
  late String? _category = widget.initial.category;
  late String _dateFilter = widget.initial.dateFilter;
  late String _timeFilter = widget.initial.timeFilter;
  late bool _spotsOnly = widget.initial.spotsOnly;
  late bool _followingOnly = widget.initial.followingOnly;
  late bool _beginnerFriendlyOnly = widget.initial.beginnerFriendlyOnly;
  late bool _wheelchairAccessibleOnly = widget.initial.wheelchairAccessibleOnly;
  late String _eventSetting = widget.initial.eventSetting;
  late String _ageGuidance = widget.initial.ageGuidance;
  late double _radiusKm = widget.initialRadiusKm;
  late final TextEditingController _languageController = TextEditingController(
    text: widget.initial.eventLanguage,
  );

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  EventDiscoveryFilters get _value => EventDiscoveryFilters(
    category: _category,
    dateFilter: _dateFilter,
    timeFilter: _timeFilter,
    spotsOnly: _spotsOnly,
    followingOnly: _followingOnly,
    beginnerFriendlyOnly: _beginnerFriendlyOnly,
    wheelchairAccessibleOnly: _wheelchairAccessibleOnly,
    eventSetting: _eventSetting,
    eventLanguage: _languageController.text.trim(),
    ageGuidance: _ageGuidance,
  );

  _EventFilterSelection _selection({bool openSearchAlerts = false}) =>
      _EventFilterSelection(
        filters: _value,
        radiusKm: _radiusKm,
        openSearchAlerts: openSearchAlerts,
      );

  void _reset() => setState(() {
    _category = null;
    _dateFilter = 'any';
    _timeFilter = 'any';
    _spotsOnly = false;
    _followingOnly = false;
    _beginnerFriendlyOnly = false;
    _wheelchairAccessibleOnly = false;
    _eventSetting = 'any';
    _languageController.clear();
    _ageGuidance = 'any';
    _radiusKm = widget.initialRadiusKm;
  });

  @override
  Widget build(BuildContext context) => AppSheetScaffold(
    title: 'Filters',
    headerAction: TextButton(
      key: const Key('reset-event-filters'),
      onPressed: _reset,
      child: const Text('Reset'),
    ),
    bodyBuilder: (context, scrollController) => SingleChildScrollView(
      key: const Key('event-filters-list'),
      controller: scrollController,
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSurface(
            padding: EdgeInsets.zero,
            borderRadius: 18,
            child: Column(
              children: [
                AppChoiceField(
                  key: const Key('event-category-filter'),
                  label: 'Category',
                  icon: CupertinoIcons.square_grid_2x2,
                  value: _category ?? 'All categories',
                  options: const ['All categories', ...eventCategories],
                  onChanged: (value) => setState(
                    () => _category = value == 'All categories' ? null : value,
                  ),
                ),
                const Divider(height: 1, indent: 50),
                AppChoiceField(
                  key: const Key('event-distance-filter'),
                  label: 'Distance',
                  icon: CupertinoIcons.location,
                  value: '${_radiusKm.toInt()} km',
                  options: const ['5 km', '10 km', '25 km', '50 km'],
                  onChanged: (value) => setState(
                    () => _radiusKm = double.parse(value.split(' ').first),
                  ),
                ),
                const Divider(height: 1, indent: 50),
                AppChoiceField(
                  key: const Key('event-date-filter'),
                  label: 'Date',
                  icon: CupertinoIcons.calendar,
                  value: eventDateFilterLabel(_dateFilter),
                  options: const [
                    'Any date',
                    'Today',
                    'Tomorrow',
                    'This weekend',
                  ],
                  onChanged: (value) => setState(
                    () => _dateFilter = switch (value) {
                      'Today' => 'today',
                      'Tomorrow' => 'tomorrow',
                      'This weekend' => 'weekend',
                      _ => 'any',
                    },
                  ),
                ),
                const Divider(height: 1, indent: 50),
                AppChoiceField(
                  key: const Key('event-time-filter'),
                  label: 'Time',
                  icon: CupertinoIcons.clock,
                  value: eventTimeFilterLabel(_timeFilter),
                  options: const [
                    'Any time',
                    'Morning',
                    'Afternoon',
                    'Evening',
                  ],
                  onChanged: (value) => setState(
                    () => _timeFilter = switch (value) {
                      'Morning' => 'morning',
                      'Afternoon' => 'afternoon',
                      'Evening' => 'evening',
                      _ => 'any',
                    },
                  ),
                ),
                const Divider(height: 1, indent: 50),
                AppChoiceField(
                  key: const Key('event-setting-filter'),
                  label: 'Setting',
                  icon: CupertinoIcons.building_2_fill,
                  value: eventSettingFilterLabel(_eventSetting),
                  options: const ['Any setting', 'Indoor', 'Outdoor', 'Mixed'],
                  onChanged: (value) => setState(
                    () => _eventSetting = switch (value) {
                      'Indoor' => 'indoor',
                      'Outdoor' => 'outdoor',
                      'Mixed' => 'mixed',
                      _ => 'any',
                    },
                  ),
                ),
                const Divider(height: 1, indent: 50),
                AppChoiceField(
                  key: const Key('event-age-filter'),
                  label: 'Age guidance',
                  icon: CupertinoIcons.person_2_fill,
                  value: eventAgeFilterLabel(_ageGuidance),
                  options: const [
                    'Any age guidance',
                    'All ages',
                    'Family friendly',
                    'Teens',
                    'Adults only',
                  ],
                  onChanged: (value) => setState(
                    () => _ageGuidance = switch (value) {
                      'All ages' => 'all_ages',
                      'Family friendly' => 'families',
                      'Teens' => 'teens',
                      'Adults only' => 'adults',
                      _ => 'any',
                    },
                  ),
                ),
                const Divider(height: 1, indent: 50),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    key: const Key('event-language-filter'),
                    controller: _languageController,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Language',
                      hintText: 'Any language',
                      counterText: '',
                      prefixIcon: Icon(CupertinoIcons.globe),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppSurface(
            padding: EdgeInsets.zero,
            borderRadius: 18,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  key: const Key('event-spots-filter'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  value: _spotsOnly,
                  title: const Text('Available spots only'),
                  onChanged: (value) => setState(() => _spotsOnly = value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile.adaptive(
                  key: const Key('event-following-filter'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  value: _followingOnly,
                  title: const Text('Hosts I follow only'),
                  onChanged: (value) => setState(() => _followingOnly = value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile.adaptive(
                  key: const Key('event-beginner-filter'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  value: _beginnerFriendlyOnly,
                  title: const Text('Beginner-friendly only'),
                  onChanged: (value) =>
                      setState(() => _beginnerFriendlyOnly = value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile.adaptive(
                  key: const Key('event-wheelchair-filter'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  value: _wheelchairAccessibleOnly,
                  title: const Text('Wheelchair-accessible only'),
                  onChanged: (value) =>
                      setState(() => _wheelchairAccessibleOnly = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('apply-event-filters'),
            onPressed: () => Navigator.pop(context, _selection()),
            child: const Text('Show events'),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            key: const Key('search-alerts-action'),
            onPressed: widget.canUseSearchAlerts
                ? () =>
                      Navigator.pop(context, _selection(openSearchAlerts: true))
                : null,
            icon: const Icon(CupertinoIcons.bell),
            label: const Text('Search alerts'),
          ),
        ],
      ),
    ),
  );
}

class _SearchAlertsSheet extends StatefulWidget {
  const _SearchAlertsSheet({
    required this.repository,
    required this.interest,
    required this.radiusKm,
    required this.filters,
  });

  final EventRepository repository;
  final String interest;
  final double radiusKm;
  final EventDiscoveryFilters filters;

  String get suggestedName {
    final parts = <String>[
      if (interest.trim().isNotEmpty)
        interest.trim()
      else if (filters.category != null)
        filters.category!
      else
        'Nearby events',
      if (filters.dateFilter != 'any') eventDateFilterLabel(filters.dateFilter),
      if (filters.timeFilter != 'any') eventTimeFilterLabel(filters.timeFilter),
      if (filters.spotsOnly) 'Open spots',
      if (filters.followingOnly) 'Following',
      if (filters.beginnerFriendlyOnly) 'Beginner friendly',
      if (filters.wheelchairAccessibleOnly) 'Wheelchair accessible',
      if (filters.eventSetting != 'any')
        eventSettingFilterLabel(filters.eventSetting),
      if (filters.eventLanguage.trim().isNotEmpty) filters.eventLanguage.trim(),
      if (filters.ageGuidance != 'any')
        eventAgeFilterLabel(filters.ageGuidance),
    ];
    return String.fromCharCodes(parts.join(' · ').runes.take(80));
  }

  String get summary {
    final parts = <String>[suggestedName, '${radiusKm.toInt()} km'];
    return parts.join(' · ');
  }

  @override
  State<_SearchAlertsSheet> createState() => _SearchAlertsSheetState();
}

class _SearchAlertsSheetState extends State<_SearchAlertsSheet> {
  List<SavedEventSearch>? _searches;
  String? _error;
  bool _creating = false;
  final Set<String> _updatingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showProgress = true}) async {
    if (mounted) {
      setState(() {
        _error = null;
        if (showProgress) _searches = null;
      });
    }
    try {
      final searches = await widget.repository.savedSearches();
      if (mounted) setState(() => _searches = searches);
    } on EdgeApiException {
      if (mounted) {
        setState(
          () => _error =
              'Search alerts are unavailable right now. Please try again later.',
        );
      }
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      await widget.repository.saveSearch(
        name: widget.suggestedName,
        interest: widget.interest,
        radiusKm: widget.radiusKm,
        filters: widget.filters,
      );
      await _load(showProgress: false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Search alert created.')));
      }
    } on EdgeApiException {
      if (mounted) {
        setState(
          () => _error =
              'Search alerts are unavailable right now. Please try again later.',
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _delete(SavedEventSearch search) async {
    try {
      await widget.repository.deleteSavedSearch(search.id);
      if (mounted) {
        setState(() {
          _searches = _searches
              ?.where((item) => item.id != search.id)
              .toList(growable: false);
        });
      }
    } on EdgeApiException {
      if (mounted) {
        setState(
          () => _error =
              'Search alerts are unavailable right now. Please try again later.',
        );
      }
    }
  }

  Future<void> _toggle(SavedEventSearch search) async {
    await _update(
      search,
      alertsEnabled: !search.alertsEnabled,
      success: search.alertsEnabled ? 'Alert paused.' : 'Alert resumed.',
    );
  }

  Future<void> _replace(SavedEventSearch search) => _update(
    search,
    interest: widget.interest,
    radiusKm: widget.radiusKm,
    filters: widget.filters,
    success: 'Alert updated with the current search.',
  );

  Future<void> _rename(SavedEventSearch search) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameSearchAlertDialog(initialName: search.name),
    );
    if (name == null || name.isEmpty || name == search.name) return;
    await _update(search, name: name, success: 'Alert renamed.');
  }

  Future<void> _update(
    SavedEventSearch search, {
    String? name,
    String? interest,
    double? radiusKm,
    EventDiscoveryFilters? filters,
    bool? alertsEnabled,
    required String success,
  }) async {
    if (_updatingIds.contains(search.id)) return;
    setState(() {
      _updatingIds.add(search.id);
      _error = null;
    });
    try {
      await widget.repository.updateSavedSearch(
        search: search,
        name: name,
        interest: interest,
        radiusKm: radiusKm,
        filters: filters,
        alertsEnabled: alertsEnabled,
      );
      await _load(showProgress: false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } on EdgeApiException {
      if (mounted) {
        setState(() => _error = 'Could not update this search alert.');
      }
    } finally {
      if (mounted) setState(() => _updatingIds.remove(search.id));
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.78,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Search alerts',
                  key: const Key('search-alerts-title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(CupertinoIcons.xmark),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Get alerts for this search',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  widget.summary,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('create-search-alert'),
                  onPressed: _creating ? null : _create,
                  icon: _creating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.bell_fill),
                  label: Text(_creating ? 'Creating…' : 'Create alert'),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Your alerts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        Expanded(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _searches == null
              ? const Center(child: CupertinoActivityIndicator())
              : _searches!.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No alerts yet.', textAlign: TextAlign.center),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _searches!.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final search = _searches![index];
                    final details = [
                      '${search.radiusKm.toInt()} km',
                      if (search.filters.category != null)
                        search.filters.category!,
                      eventDateFilterLabel(search.filters.dateFilter),
                      if (search.filters.followingOnly) 'Following',
                      if (search.filters.beginnerFriendlyOnly)
                        'Beginner friendly',
                      if (search.filters.wheelchairAccessibleOnly)
                        'Wheelchair accessible',
                      if (search.filters.eventSetting != 'any')
                        eventSettingFilterLabel(search.filters.eventSetting),
                      if (search.filters.eventLanguage.isNotEmpty)
                        search.filters.eventLanguage,
                      if (search.filters.ageGuidance != 'any')
                        eventAgeFilterLabel(search.filters.ageGuidance),
                      if (!search.alertsEnabled) 'Paused',
                    ].join(' · ');
                    return ListTile(
                      key: ValueKey('saved-search-${search.id}'),
                      leading: Icon(
                        search.alertsEnabled
                            ? CupertinoIcons.bell_fill
                            : CupertinoIcons.bell_slash_fill,
                      ),
                      title: Text(search.name),
                      subtitle: Text(details),
                      onTap: () => Navigator.pop(context, search),
                      trailing: _updatingIds.contains(search.id)
                          ? const CupertinoActivityIndicator()
                          : PopupMenuButton<String>(
                              tooltip: 'Manage search alert',
                              onSelected: (action) async {
                                switch (action) {
                                  case 'toggle':
                                    await _toggle(search);
                                    break;
                                  case 'rename':
                                    await _rename(search);
                                    break;
                                  case 'replace':
                                    await _replace(search);
                                    break;
                                  case 'delete':
                                    await _delete(search);
                                    break;
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(
                                    search.alertsEnabled
                                        ? 'Pause alert'
                                        : 'Resume alert',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename'),
                                ),
                                const PopupMenuItem(
                                  value: 'replace',
                                  child: Text('Use current search'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class _RenameSearchAlertDialog extends StatefulWidget {
  const _RenameSearchAlertDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameSearchAlertDialog> createState() =>
      _RenameSearchAlertDialogState();
}

class _RenameSearchAlertDialogState extends State<_RenameSearchAlertDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename alert'),
    content: TextField(
      key: const Key('rename-search-alert-field'),
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(labelText: 'Alert name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}

class _LocationPrompt extends StatelessWidget {
  const _LocationPrompt({required this.notice, required this.onPressed});

  final String? notice;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              CupertinoIcons.location_fill,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'See what is nearby',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Allow location while using the app. We never track you in the background.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
          if (notice != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.secondaryContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                notice!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: 240,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(CupertinoIcons.location),
              label: const Text('Use My Location'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.calendar_badge_plus, size: 54),
          const SizedBox(height: 16),
          Text(
            'Nothing planned nearby—yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 7),
          Text(
            'Start something people around you can join.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
