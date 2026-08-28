import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gather2gether/features/events/domain/event_summary.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class EventMap extends StatelessWidget {
  const EventMap({
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
    required this.events,
    required this.onEventSelected,
    super.key,
  });

  final double latitude;
  final double longitude;
  final double radiusKm;
  final List<EventSummary> events;
  final ValueChanged<EventSummary> onEventSelected;

  double get _initialZoom => switch (radiusKm) {
    <= 5 => 12.5,
    <= 10 => 11.5,
    <= 25 => 10,
    _ => 9,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final center = LatLng(latitude, longitude);

    return Semantics(
      label: 'Map of ${events.length} nearby events',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.surfaceContainerHighest),
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: _initialZoom,
              minZoom: 3,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.gather2gether.gather2gether',
                maxNativeZoom: 19,
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: center,
                    radius: radiusKm * 1000,
                    useRadiusInMeter: true,
                    color: colors.primary.withValues(alpha: 0.08),
                    borderColor: colors.primary.withValues(alpha: 0.28),
                    borderStrokeWidth: 1.5,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: center,
                    width: 34,
                    height: 34,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.primary, width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (final event in events)
                    Marker(
                      point: LatLng(event.latitude, event.longitude),
                      width: 52,
                      height: 52,
                      alignment: Alignment.topCenter,
                      child: Tooltip(
                        message: event.title,
                        child: GestureDetector(
                          onTap: () => onEventSelected(event),
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors.tertiary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.onTertiary,
                                width: 3,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x3D000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.event_rounded,
                              color: colors.onTertiary,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SimpleAttributionWidget(
                source: const Text(
                  'OpenStreetMap contributors',
                  style: TextStyle(fontSize: 10),
                ),
                onTap: () async {
                  await launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                    mode: LaunchMode.externalApplication,
                  );
                },
                backgroundColor: colors.surface.withValues(alpha: 0.88),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
