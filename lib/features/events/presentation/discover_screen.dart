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
  const DiscoverScreen({required this.onCreate, super.key});

  final VoidCallback onCreate;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _events = EventRepository();
  final _profiles = ProfileRepository();
  final _location = const LocationService();

  List<EventSummary> _results = const [];
  double? _latitude;
  double? _longitude;
  double _radiusKm = 10;
  bool _loading = true;
  bool _showMap = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedLocation();
  }

  Future<void> _loadSavedLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _profiles.fetchOwnProfile();
      _radiusKm = profile.preferredRadiusKm;
      _latitude = profile.approximateLatitude;
      _longitude = profile.approximateLongitude;
      if (_latitude != null && _longitude != null) await _loadEvents();
    } catch (_) {
      _error = 'We could not load your saved area.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final position = await _location.currentPosition();
      _latitude = position.latitude;
      _longitude = position.longitude;
      await _loadEvents();
    } on LocationFailure catch (failure) {
      _error = failure.message;
      if (failure.canOpenSettings && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.message),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: _location.openSettings,
            ),
          ),
        );
      }
    } catch (_) {
      _error = 'We could not get your location. Please try again.';
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
      );
      if (mounted) {
        setState(() {
          _results = results;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Nearby events are temporarily unavailable.');
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
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CupertinoActivityIndicator(radius: 14)),
              )
            else if (_latitude == null || _longitude == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _LocationPrompt(
                  error: _error,
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
                      _MapStatus(
                        count: _results.length,
                        radiusKm: _radiusKm,
                        error: _error,
                      ),
                    ],
                  ),
                ),
              )
            else if (_results.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyResults(error: _error, onCreate: widget.onCreate),
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
  const _MapStatus({
    required this.count,
    required this.radiusKm,
    required this.error,
  });

  final int count;
  final double radiusKm;
  final String? error;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
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
            error ??
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
    final visual = CategoryVisual.forName(event.category);
    final colors = Theme.of(context).colorScheme;
    final distance = event.distanceMeters < 1000
        ? '${event.distanceMeters.round()} m'
        : '${(event.distanceMeters / 1000).toStringAsFixed(1)} km';
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(20),
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
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [visual.start, visual.end],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  visual.icon,
                  size: 38,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
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
  const _LocationPrompt({required this.error, required this.onPressed});

  final String? error;
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
              shape: BoxShape.circle,
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
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
  const _EmptyResults({required this.error, required this.onCreate});

  final String? error;
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
            error ?? 'Nothing planned nearby—yet.',
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
