import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/features/events/presentation/event_map.dart';

void main() {
  test('map claims touch and pan-zoom sequences with unique factories', () {
    final recognizers = eventMapGestureRecognizers();
    final recognizerTypes = recognizers.map((factory) => factory.type).toSet();

    expect(recognizerTypes, hasLength(recognizers.length));
    expect(recognizerTypes, contains(EagerGestureRecognizer));
    expect(recognizerTypes, contains(ScaleGestureRecognizer));
  });

  testWidgets('map controls stay compact and trigger each action', (
    tester,
  ) async {
    var recenterCount = 0;
    var zoomInCount = 0;
    var zoomOutCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: EventMapControls(
              onRecenter: () => recenterCount += 1,
              onZoomIn: () => zoomInCount += 1,
              onZoomOut: () => zoomOutCount += 1,
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Recenter to my location'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byTooltip('Zoom out'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('map-recenter-control'))),
      const Size.square(40),
    );
    final controlsSize = tester.getSize(find.byType(EventMapControls));
    expect(controlsSize.height, 40);
    expect(controlsSize.width, lessThan(130));

    await tester.tap(find.byKey(const Key('map-recenter-control')));
    await tester.tap(find.byKey(const Key('map-zoom-in-control')));
    await tester.tap(find.byKey(const Key('map-zoom-out-control')));

    expect(recenterCount, 1);
    expect(zoomInCount, 1);
    expect(zoomOutCount, 1);
  });

  testWidgets('map attribution stays compact and opens on demand', (
    tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MapAttributionButton(onPressed: () => tapCount += 1),
          ),
        ),
      ),
    );

    expect(find.text('©'), findsOneWidget);
    expect(find.textContaining('OpenMapTiles'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('map-attribution-control'))),
      const Size.square(30),
    );

    await tester.tap(find.byKey(const Key('map-attribution-control')));
    expect(tapCount, 1);
  });
}
