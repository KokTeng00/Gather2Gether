import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/events/presentation/event_map.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native map loads annotations and crosses the Pacific both ways',
    (tester) async {
      MapLibreMapController? controller;
      var styleLoads = 0;
      // A local style keeps this independent of tile-server availability.
      const style = '''{"version":8,"sources":{},"layers":[
      {"id":"ocean","type":"background","paint":{"background-color":"#b7d9ed"}}
    ]}''';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapLibreMap(
              styleString: style,
              initialCameraPosition: const CameraPosition(
                target: LatLng(20, -122),
                zoom: 3,
              ),
              gestureRecognizers: eventMapGestureRecognizers(),
              cameraTargetBounds: CameraTargetBounds.unbounded,
              minMaxZoomPreference: const MinMaxZoomPreference(3, 18),
              annotationOrder: const [
                AnnotationType.fill,
                AnnotationType.circle,
              ],
              onMapCreated: (value) => controller = value,
              onStyleLoadedCallback: () => styleLoads++,
            ),
          ),
        ),
      );
      for (var attempt = 0; attempt < 100 && styleLoads == 0; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        styleLoads,
        1,
        reason:
            'controller=$controller, '
            'fill=${controller?.fillManager?.isInitialized}, '
            'circle=${controller?.circleManager?.isInitialized}',
      );
      expect(controller, isNotNull);
      expect(controller!.fillManager?.isInitialized, isTrue);
      expect(controller!.circleManager?.isInitialized, isTrue);

      await controller!.addCircle(
        const CircleOptions(geometry: LatLng(20, -179), circleRadius: 8),
      );
      for (final longitude in [
        -160.0,
        -179.0,
        179.0,
        160.0,
        139.0,
        179.0,
        -179.0,
      ]) {
        await controller!.moveCamera(
          CameraUpdate.newLatLng(LatLng(20, longitude)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final camera = await controller!.queryCameraPosition();
        expect(camera, isNotNull);
        final error = (camera!.target.longitude - longitude + 540) % 360 - 180;
        expect(
          error.abs(),
          lessThan(0.01),
          reason: 'The native camera must not clamp at longitude $longitude.',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
