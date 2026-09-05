import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class _StylePlatform extends MapLibrePlatform {
  int sourceCalls = 0;
  int layerCalls = 0;
  bool failNextSource = false;
  Completer<void>? pendingSource;

  @override
  Future<void> addGeoJsonSource(
    String sourceId,
    Map<String, dynamic> geojson, {
    String? promoteId,
  }) async {
    sourceCalls++;
    if (failNextSource) {
      failNextSource = false;
      throw PlatformException(code: 'styleNotFound');
    }
    await pendingSource?.future;
  }

  @override
  Future<void> addCircleLayer(
    String sourceId,
    String layerId,
    Map<String, dynamic> properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    bool enableInteraction = true,
  }) async {
    layerCalls++;
  }

  @override
  Future<void> setGeoJsonSource(
    String id,
    Map<String, dynamic> geojson,
  ) async {}

  @override
  Future<void> removeLayer(String id) async {}

  @override
  Future<void> removeSource(String id) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StylePlatform platform;
  late MapLibreMapController controller;
  late int loaded;

  setUp(() {
    loaded = 0;
    platform = _StylePlatform();
    controller = MapLibreMapController(
      maplibrePlatform: platform,
      annotationOrder: const [AnnotationType.circle],
      annotationConsumeTapEvents: const [AnnotationType.circle],
      onStyleLoadedCallback: () => loaded++,
    );
  });

  tearDown(() {
    if (!controller.isDisposed) controller.dispose();
  });

  test(
    'styleNotFound during startup recovers on the next loaded style',
    () async {
      platform.failNextSource = true;
      platform.onMapStyleLoadedPlatform.call(null);
      await Future<void>.delayed(Duration.zero);
      expect(loaded, 0);
      expect(controller.circleManager?.isInitialized, isFalse);

      platform.onMapStyleLoadedPlatform.call(null);
      await Future<void>.delayed(Duration.zero);
      expect(loaded, 1);
      expect(controller.circleManager?.isInitialized, isTrue);
    },
  );

  test(
    'overlapping style callbacks initialize only the latest style',
    () async {
      final pending = Completer<void>();
      platform.pendingSource = pending;
      platform.onMapStyleLoadedPlatform.call(null);
      await Future<void>.delayed(Duration.zero);
      platform.onMapStyleLoadedPlatform.call(null);
      platform.onMapStyleLoadedPlatform.call(null);
      await Future<void>.delayed(Duration.zero);
      expect(platform.sourceCalls, 1);

      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(platform.sourceCalls, 2);
      expect(loaded, 1);
      expect(controller.circleManager?.isInitialized, isTrue);
    },
  );

  test('disposal while adding a source prevents further layer calls', () async {
    final pending = Completer<void>();
    platform.pendingSource = pending;
    platform.onMapStyleLoadedPlatform.call(null);
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(platform.layerCalls, 0);
    expect(loaded, 0);
  });
}
