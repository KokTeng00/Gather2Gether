import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/core/location/location_service.dart';
import 'package:gather2gether/core/theme/app_visuals.dart';
import 'package:gather2gether/features/events/data/event_repository.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/event_detail_screen.dart';
import 'package:gather2gether/features/events/presentation/event_map.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:intl/intl.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    required this.onCreate,
    this.profileRepository,
    super.key,
  });

  final VoidCallback onCreate;
  final ProfileRepository? profileRepository;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _events = EventRepository();
  final _location = const LocationService();
  final _interestController = TextEditingController();
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

  @override
  void dispose() {
    _interestController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _profiles = widget.profileRepository ?? ProfileRepository();
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

  Future<void> _useCurrentLocation() async {
    setState(() {
      _loading = true;
      _maintenance = false;
      _locationNotice = null;
    });
    try {
      final position = await _location.currentPosition();
      _latitude = position.latitude;
      _longitude = position.longitude;
      await _loadEvents();
    } on LocationFailure catch (failure) {
      _locationNotice = 'Location access is needed to show nearby events.';
      if (failure.canOpenSettings && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Location access is needed to show nearby events.',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: _location.openSettings,
            ),
          ),
        );
      }
    } catch (_) {
      _maintenance = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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

  Future<void> _openEvent(EventSummary event) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator.adaptive(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              sliver: SliverToBoxAdapter(
                child: AppPageHeader(
                  title: 'Discover',
                  subtitle: 'Find something worth going out for.',
                  actions: [
                    AppCircleButton(
                      icon: CupertinoIcons.location_fill,
                      tooltip: 'Use current location',
                      onPressed: _loading ? null : _useCurrentLocation,
                    ),
                    AppCircleButton(
                      icon: CupertinoIcons.add,
                      tooltip: 'Create event',
                      filled: true,
                      onPressed: widget.onCreate,
                    ),
                  ],
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
                  onViewChanged: (value) => setState(() => _showMap = value),
                  onRadiusChanged: _selectRadius,
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
                  hintText: 'Try “outdoors with a relaxed pace”',
                  onSubmitted: _applyInterest,
                  onClear: _clearInterest,
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 450,
                        child: EventMap(
                          key: ValueKey('$_latitude:$_longitude:$_radiusKm'),
                          latitude: _latitude!,
                          longitude: _longitude!,
                          radiusKm: _radiusKm,
                          events: _results,
                          onEventSelected: _openEvent,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _MapStatus(count: _results.length, radiusKm: _radiusKm),
                    ],
                  ),
                ),
              )
            else if (_results.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyResults(onCreate: widget.onCreate),
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
                      'More nearby',
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

class _MapStatus extends StatelessWidget {
  const _MapStatus({required this.count, required this.radiusKm});

  final int count;
  final double radiusKm;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(
          CupertinoIcons.location_fill,
          color: Theme.of(context).colorScheme.primary,
          size: 19,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '$count ${count == 1 ? 'event' : 'events'} within ${radiusKm.toInt()} km',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
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
  const _EmptyResults({required this.onCreate});

  final VoidCallback onCreate;

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
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(CupertinoIcons.add),
            label: const Text('Create an Event'),
          ),
        ],
      ),
    ),
  );
}
