import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

  Future<void> _selectRadius(double value) async {
    setState(() {
      _radiusKm = value;
      _loading = true;
    });
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
    final selected = await showModalBottomSheet<EventDiscoveryFilters>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _EventFilterSheet(initial: _filters),
    );
    if (selected == null) return;
    setState(() {
      _filters = selected;
      _loading = true;
    });
    await _loadEvents();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openSearchAlerts() async {
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
    if (selected == null) return;
    _interestController.text = selected.interest;
    setState(() {
      _interest = selected.interest.trim().isEmpty ? null : selected.interest;
      _radiusKm = selected.radiusKm;
      _filters = selected.filters;
      _loading = true;
    });
    await _loadEvents();
    if (mounted) setState(() => _loading = false);
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
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              sliver: SliverToBoxAdapter(
                child: _ViewControls(
                  showMap: _showMap,
                  radiusKm: _radiusKm,
                  loading: _loading,
                  onViewChanged: _setShowMap,
                  onRadiusChanged: _selectRadius,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              sliver: SliverToBoxAdapter(
                child: AppInterestSearch(
                  key: const Key('event-interest-search'),
                  controller: _interestController,
                  enabled: !_loading && _latitude != null,
                  hintText: 'Search events',
                  onSubmitted: _applyInterest,
                  onClear: _clearInterest,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            key: const Key('event-filter-action'),
                            selected: _filters.isActive,
                            avatar: const Icon(
                              CupertinoIcons.slider_horizontal_3,
                              size: 16,
                            ),
                            label: Text(
                              _filters.isActive ? 'Filters on' : 'Filters',
                            ),
                            onSelected: _loading ? null : (_) => _openFilters(),
                          ),
                          const SizedBox(width: 8),
                          ActionChip(
                            key: const Key('search-alerts-action'),
                            avatar: const Icon(CupertinoIcons.bell, size: 16),
                            label: const Text('Search alerts'),
                            onPressed: _latitude == null
                                ? null
                                : _openSearchAlerts,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _interest == null
                                ? 'Nearby events'
                                : 'Search results',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          key: const Key('create-event-action'),
                          onPressed: widget.onCreate,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 46),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          icon: const Icon(CupertinoIcons.calendar_badge_plus),
                          label: const Text('Create event'),
                        ),
                      ],
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

class _ViewControls extends StatelessWidget {
  const _ViewControls({
    required this.showMap,
    required this.radiusKm,
    required this.loading,
    required this.onViewChanged,
    required this.onRadiusChanged,
  });

  final bool showMap;
  final double radiusKm;
  final bool loading;
  final ValueChanged<bool> onViewChanged;
  final ValueChanged<double> onRadiusChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CupertinoSlidingSegmentedControl<bool>(
            groupValue: showMap,
            padding: const EdgeInsets.all(3),
            backgroundColor: Theme.of(context).colorScheme.surface,
            thumbColor: Theme.of(context).colorScheme.secondaryContainer,
            children: const {
              false: Padding(
                padding: EdgeInsets.symmetric(vertical: 7),
                child: Text('Events'),
              ),
              true: Padding(
                padding: EdgeInsets.symmetric(vertical: 7),
                child: Text('Map'),
              ),
            },
            onValueChanged: (value) {
              if (!loading && value != null) onViewChanged(value);
            },
          ),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<double>(
          enabled: !loading,
          initialValue: radiusKm,
          onSelected: onRadiusChanged,
          itemBuilder: (_) => [5.0, 10.0, 25.0, 50.0]
              .map(
                (value) => PopupMenuItem(
                  value: value,
                  child: Text('Within ${value.toInt()} km'),
                ),
              )
              .toList(),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                const Icon(CupertinoIcons.slider_horizontal_3, size: 17),
                const SizedBox(width: 6),
                Text(
                  '${radiusKm.toInt()} km',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
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

class _EventFilterSheet extends StatefulWidget {
  const _EventFilterSheet({required this.initial});

  final EventDiscoveryFilters initial;

  @override
  State<_EventFilterSheet> createState() => _EventFilterSheetState();
}

class _EventFilterSheetState extends State<_EventFilterSheet> {
  late String? _category = widget.initial.category;
  late String _dateFilter = widget.initial.dateFilter;
  late String _timeFilter = widget.initial.timeFilter;
  late bool _spotsOnly = widget.initial.spotsOnly;
  late bool _followingOnly = widget.initial.followingOnly;

  EventDiscoveryFilters get _value => EventDiscoveryFilters(
    category: _category,
    dateFilter: _dateFilter,
    timeFilter: _timeFilter,
    spotsOnly: _spotsOnly,
    followingOnly: _followingOnly,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      10,
      20,
      MediaQuery.viewPaddingOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filter events',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _category = null;
                  _dateFilter = 'any';
                  _timeFilter = 'any';
                  _spotsOnly = false;
                  _followingOnly = false;
                }),
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            key: const Key('event-category-filter'),
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All categories'),
              ),
              for (final category in eventCategories)
                DropdownMenuItem<String?>(
                  value: category,
                  child: Text(category),
                ),
            ],
            onChanged: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: 20),
          Text('Date', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const ['any', 'today', 'tomorrow', 'weekend'])
                ChoiceChip(
                  label: Text(eventDateFilterLabel(value)),
                  selected: _dateFilter == value,
                  onSelected: (_) => setState(() => _dateFilter = value),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Time', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const [
                'any',
                'morning',
                'afternoon',
                'evening',
              ])
                ChoiceChip(
                  label: Text(eventTimeFilterLabel(value)),
                  selected: _timeFilter == value,
                  onSelected: (_) => setState(() => _timeFilter = value),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            key: const Key('event-spots-filter'),
            contentPadding: EdgeInsets.zero,
            value: _spotsOnly,
            title: const Text('Only events with available spots'),
            onChanged: (value) => setState(() => _spotsOnly = value),
          ),
          SwitchListTile.adaptive(
            key: const Key('event-following-filter'),
            contentPadding: EdgeInsets.zero,
            value: _followingOnly,
            title: const Text('Only hosts I follow'),
            onChanged: (value) => setState(() => _followingOnly = value),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('apply-event-filters'),
            onPressed: () => Navigator.pop(context, _value),
            child: const Text('Show events'),
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
                    ].join(' · ');
                    return ListTile(
                      key: ValueKey('saved-search-${search.id}'),
                      leading: const Icon(CupertinoIcons.bell_fill),
                      title: Text(search.name),
                      subtitle: Text(details),
                      onTap: () => Navigator.pop(context, search),
                      trailing: IconButton(
                        tooltip: 'Delete saved search',
                        onPressed: () => _delete(search),
                        icon: const Icon(CupertinoIcons.delete),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
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
