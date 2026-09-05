import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:gather2gether/config/app_config.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

@visibleForTesting
Set<Factory<OneSequenceGestureRecognizer>> eventMapGestureRecognizers() => {
  Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
  // Trackpads and some simulator hosts report pinches as a pan/zoom pointer
  // sequence rather than two touch downs. Claim that sequence explicitly so
  // it reaches MapLibre.
  Factory<ScaleGestureRecognizer>(ScaleGestureRecognizer.new),
};

class EventMap extends StatefulWidget {
  const EventMap({
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.events,
    required this.onEventSelected,
    required this.onRecenterRequested,
    super.key,
  });

  final double latitude;
  final double longitude;
  final double radiusKm;
  final List<EventSummary> events;
  final ValueChanged<EventSummary> onEventSelected;
  final Future<void> Function() onRecenterRequested;

  @override
  State<EventMap> createState() => _EventMapState();
}

class _EventMapState extends State<EventMap> {
  MapLibreMapController? _controller;
  bool _styleLoaded = false;
  int _renderGeneration = 0;

  double get _initialZoom => switch (widget.radiusKm) {
    <= 5 => 12.5,
    <= 10 => 11.5,
    <= 25 => 10,
    _ => 9,
  };

  @override
  void didUpdateWidget(covariant EventMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_styleLoaded) unawaited(_renderAnnotations());
  }

  @override
  void dispose() {
    _renderGeneration += 1;
    final controller = _controller;
    if (controller != null && !controller.isDisposed) {
      controller.onCircleTapped.remove(_onCircleTapped);
    }
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    _styleLoaded = false;
    controller.onCircleTapped.add(_onCircleTapped);
  }

  void _onStyleLoaded() {
    if (!mounted) return;
    _styleLoaded = true;
    unawaited(_renderAnnotations());
  }

  Future<void> _showAttribution() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Map information',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Map data © OpenStreetMap contributors. '
                'Map style © OpenMapTiles. Tiles provided by OpenFreeMap.',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () async {
                  await launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                child: const Text('Copyright details'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recenter() async {
    await widget.onRecenterRequested();
    if (!mounted) return;
    final controller = _controller;
    if (controller == null || controller.isDisposed) return;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLng(LatLng(widget.latitude, widget.longitude)),
        duration: const Duration(milliseconds: 450),
      );
    } catch (_) {
      // The native view can disappear while its camera animation is starting.
    }
  }

  Future<void> _changeZoom(CameraUpdate update) async {
    final controller = _controller;
    if (controller == null || controller.isDisposed) return;
    try {
      await controller.animateCamera(
        update,
        duration: const Duration(milliseconds: 220),
      );
    } catch (_) {
      // Ignore a control tap if the native map is being recreated.
    }
  }

  void _onCircleTapped(Circle circle) {
    final eventId = circle.data?['event_id'];
    if (eventId is! String) return;
    for (final event in widget.events) {
      if (event.id == eventId) {
        widget.onEventSelected(event);
        return;
      }
    }
  }

  Future<void> _renderAnnotations() async {
    final controller = _controller;
    if (controller == null || controller.isDisposed || !_styleLoaded) return;
    final generation = ++_renderGeneration;
    final colors = Theme.of(context).colorScheme;

    try {
      await controller.clearFills();
      if (!_isCurrentRender(controller, generation)) return;
      await controller.clearCircles();
      if (!_isCurrentRender(controller, generation)) return;

      final radiusPolygon = _radiusPolygon(
        widget.latitude,
        widget.longitude,
        widget.radiusKm * 1000,
      );
      if (radiusPolygon != null) {
        await controller.addFill(
          FillOptions(
            geometry: [radiusPolygon],
            fillColor: _hex(colors.primary),
            fillOpacity: 0.08,
            fillOutlineColor: _hex(colors.primary.withValues(alpha: 0.45)),
          ),
        );
      }
      if (!_isCurrentRender(controller, generation)) return;

      final center = LatLng(widget.latitude, widget.longitude);
      final circleOptions = <CircleOptions>[
        CircleOptions(
          geometry: center,
          circleRadius: 9,
          circleColor: _hex(colors.surface),
          circleStrokeWidth: 3,
          circleStrokeColor: _hex(colors.primary),
        ),
        CircleOptions(
          geometry: center,
          circleRadius: 3.5,
          circleColor: _hex(colors.primary),
        ),
        for (final event in widget.events)
          CircleOptions(
            geometry: LatLng(event.latitude, event.longitude),
            circleRadius: 14,
            circleColor: _hex(colors.tertiary),
            circleStrokeWidth: 3,
            circleStrokeColor: _hex(colors.onTertiary),
          ),
      ];
      final circleData = <Map<String, dynamic>>[
        const {},
        const {},
        for (final event in widget.events) {'event_id': event.id},
      ];
      await controller.addCircles(circleOptions, circleData);
    } catch (_) {
      // A style reload or widget disposal can invalidate an in-flight
      // annotation update. The next style/update callback renders fresh data.
    }
  }

  bool _isCurrentRender(MapLibreMapController controller, int generation) =>
      mounted &&
      !controller.isDisposed &&
      identical(controller, _controller) &&
      generation == _renderGeneration;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Map of ${widget.events.length} nearby events',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ColoredBox(
          color: colors.surfaceContainerHighest,
          child: Stack(
            children: [
              Positioned.fill(
                child: MapLibreMap(
                  styleString: AppConfig.mapStyleUrl,
                  // Keep native horizontal wrapping when crossing the Pacific.
                  cameraTargetBounds: CameraTargetBounds.unbounded,
                  annotationOrder: const [
                    AnnotationType.fill,
                    AnnotationType.circle,
                  ],
                  gestureRecognizers: eventMapGestureRecognizers(),
                  initialCameraPosition: CameraPosition(
                    target: LatLng(widget.latitude, widget.longitude),
                    zoom: _initialZoom,
                  ),
                  minMaxZoomPreference: const MinMaxZoomPreference(3, 18),
                  dragEnabled: true,
                  scrollGesturesEnabled: true,
                  zoomGesturesEnabled: true,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  compassEnabled: false,
                  logoEnabled: false,
                  attributionButtonPosition:
                      AttributionButtonPosition.bottomLeft,
                  attributionButtonMargins: const math.Point<double>(8, 8),
                  // A compact app-native attribution control is placed over
                  // MapLibre's platform button below. Keeping the native tint
                  // transparent avoids the large iOS provider action sheet.
                  attributionButtonColor: Colors.transparent,
                  onMapCreated: _onMapCreated,
                  onStyleLoadedCallback: _onStyleLoaded,
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: EventMapControls(
                  onRecenter: _recenter,
                  onZoomIn: () => _changeZoom(CameraUpdate.zoomIn()),
                  onZoomOut: () => _changeZoom(CameraUpdate.zoomOut()),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: MapAttributionButton(onPressed: _showAttribution),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class MapAttributionButton extends StatelessWidget {
  const MapAttributionButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
    elevation: 1,
    shadowColor: Colors.black26,
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onPressed,
      customBorder: const CircleBorder(),
      child: const SizedBox.square(
        key: Key('map-attribution-control'),
        dimension: 30,
        child: Center(
          child: Text(
            '©',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ),
  );
}

@visibleForTesting
class EventMapControls extends StatelessWidget {
  const EventMapControls({
    required this.onRecenter,
    required this.onZoomIn,
    required this.onZoomOut,
    super.key,
  });

  final VoidCallback onRecenter;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface.withValues(alpha: 0.94),
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapControlButton(
            key: const Key('map-recenter-control'),
            tooltip: 'Recenter to my location',
            icon: Icons.my_location_rounded,
            onPressed: onRecenter,
          ),
          const _MapControlDivider(),
          _MapControlButton(
            key: const Key('map-zoom-in-control'),
            tooltip: 'Zoom in',
            icon: Icons.add_rounded,
            onPressed: onZoomIn,
          ),
          const _MapControlDivider(),
          _MapControlButton(
            key: const Key('map-zoom-out-control'),
            tooltip: 'Zoom out',
            icon: Icons.remove_rounded,
            onPressed: onZoomOut,
          ),
        ],
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 40,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        maximumSize: const Size.square(40),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _MapControlDivider extends StatelessWidget {
  const _MapControlDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

List<LatLng>? _radiusPolygon(
  double latitude,
  double longitude,
  double radiusMeters,
) {
  const earthRadiusMeters = 6371008.8;
  const points = 72;
  final latitudeRadians = latitude * math.pi / 180;
  final longitudeRadians = longitude * math.pi / 180;
  final angularDistance = radiusMeters / earthRadiusMeters;
  final result = <LatLng>[];

  for (var index = 0; index <= points; index += 1) {
    final bearing = 2 * math.pi * index / points;
    final targetLatitude = math.asin(
      math.sin(latitudeRadians) * math.cos(angularDistance) +
          math.cos(latitudeRadians) *
              math.sin(angularDistance) *
              math.cos(bearing),
    );
    final targetLongitude =
        longitudeRadians +
        math.atan2(
          math.sin(bearing) *
              math.sin(angularDistance) *
              math.cos(latitudeRadians),
          math.cos(angularDistance) -
              math.sin(latitudeRadians) * math.sin(targetLatitude),
        );
    final targetLongitudeDegrees = targetLongitude * 180 / math.pi;
    final normalizedLongitude = (targetLongitudeDegrees + 540) % 360 - 180;
    result.add(LatLng(targetLatitude * 180 / math.pi, normalizedLongitude));
  }

  final crossesDateLine = result.any(
    (point) => (point.longitude - longitude).abs() > 180,
  );
  return crossesDateLine ? null : result;
}

String _hex(Color color) {
  final red = (color.r * 255).round().clamp(0, 255);
  final green = (color.g * 255).round().clamp(0, 255);
  final blue = (color.b * 255).round().clamp(0, 255);
  return '#${red.toRadixString(16).padLeft(2, '0')}'
      '${green.toRadixString(16).padLeft(2, '0')}'
      '${blue.toRadixString(16).padLeft(2, '0')}';
}
