import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:gather2gether/features/events/presentation/event_map.dart';
import 'package:intl/intl.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class EventDateBadge extends StatelessWidget {
  const EventDateBadge({required this.date, super.key});
  final DateTime date;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat.MMM().format(date).toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 25,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class EventListCard extends StatelessWidget {
  const EventListCard({
    required this.event,
    required this.onTap,
    this.showDistance = true,
    super.key,
  });
  final EventSummary event;
  final VoidCallback onTap;
  final bool showDistance;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final distance = event.distanceMeters < 1000
        ? '${event.distanceMeters.round()} m'
        : '${(event.distanceMeters / 1000).toStringAsFixed(1)} km';
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EventDateBadge(date: event.startAt),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${DateFormat.EEEE().format(event.startAt)} · ${DateFormat.Hm().format(event.startAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      event.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${event.venueName}${showDistance ? ' · $distance' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      event.spotsLeft == 0
                          ? 'Full · waitlist available'
                          : '${event.joinedCount} going · ${event.spotsLeft} places left',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EventIntroduction extends StatelessWidget {
  const EventIntroduction({required this.event, super.key});
  final EventSummary event;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.category,
            style: TextStyle(
              color: colors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            event.title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(height: 1.15),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EventDateBadge(date: event.startAt),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, d MMMM').format(event.startAt),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${DateFormat.Hm().format(event.startAt)}–${DateFormat.Hm().format(event.endAt)} · Free',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      event.venueName,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The crosshair marks the actual meeting point, independently of the address.
class MeetingPointPicker extends StatefulWidget {
  const MeetingPointPicker({
    required this.initial,
    this.styleUrl = AppConfig.mapStyleUrl,
    this.onMapCreated,
    super.key,
  });
  final LatLng initial;
  final String styleUrl;
  final ValueChanged<MapLibreMapController>? onMapCreated;
  @override
  State<MeetingPointPicker> createState() => _MeetingPointPickerState();
}

class _MeetingPointPickerState extends State<MeetingPointPicker> {
  MapLibreMapController? _controller;
  bool _ready = false;
  bool _saving = false;

  Future<void> _confirmPoint() async {
    if (!_ready || _saving || _controller == null) return;
    setState(() => _saving = true);
    try {
      // Native camera changes do not always emit onCameraMove, especially after
      // programmatic recentering. Read the actual camera at confirmation time.
      final camera = await _controller!.queryCameraPosition().timeout(
        const Duration(seconds: 5),
      );
      if (!mounted) return;
      if (camera == null) throw StateError('Camera unavailable');
      Navigator.pop(context, camera.target);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not read the meeting point. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Meeting point')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Text(
            'Move the map until the pin sits at the entrance or spot where you’ll meet.',
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              MapLibreMap(
                initialCameraPosition: CameraPosition(
                  target: widget.initial,
                  zoom: 17,
                ),
                styleString: widget.styleUrl,
                onMapCreated: (controller) {
                  _controller = controller;
                  widget.onMapCreated?.call(controller);
                },
                onStyleLoadedCallback: () {
                  if (mounted) setState(() => _ready = true);
                },
                gestureRecognizers: eventMapGestureRecognizers(),
                compassEnabled: true,
              ),
              IgnorePointer(
                child: Transform.translate(
                  offset: const Offset(0, -21),
                  child: Icon(
                    CupertinoIcons.map_pin,
                    size: 42,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              if (!_ready)
                const Positioned(
                  top: 16,
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Loading map…'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _ready && !_saving ? _confirmPoint : null,
              child: Text(_saving ? 'Saving point…' : 'Use this meeting point'),
            ),
          ),
        ),
      ],
    ),
  );
}
