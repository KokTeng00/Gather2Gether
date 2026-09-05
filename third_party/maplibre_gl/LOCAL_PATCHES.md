# Gather2Gether MapLibre fixes

Runtime sources vendored from the published `maplibre_gl` 0.27.0 package
([upstream](https://github.com/maplibre/flutter-maplibre-gl)), retaining its LICENSE.
The platform interface and web implementation still use the published 0.27.x
packages. Examples, screenshots and upstream tests are omitted; `resolution:
workspace` is removed so this package can resolve inside the app.

Local changes:

- iOS leaves a newly created, unbounded map's native camera constraints alone.
  Setting `maximumScreenBounds` to ±180 degrees enables the native Screen
  constraint mode, stopping horizontal panning at the date line. Gather2Gether
  always uses unbounded maps. Dynamically clearing previously applied explicit
  bounds is not supported by this patch; recreate the map for that transition.
- iOS records the initial style and skips identical style assignments from the
  creation options. Genuine style changes reset the style-ready flag.
  Inline JSON that finishes before the delegate is attached is adopted directly.
- Dart serializes annotation initialization, ignores superseded style callbacks,
  and stops initialization after disposal. A transient `styleNotFound` during a
  reload waits for the next successful style callback instead of escaping as an
  unhandled exception. Other active-controller platform errors still propagate.

Regression tests live in the app's `test/features/events/presentation/` and
`integration_test/event_map_native_test.dart`. The latter exercises the real
native map across both sides of the date line and checks annotation startup.

Run `flutter pub get` and fully rebuild iOS after changes here; hot reload cannot
replace the native plugin. Remove this path dependency when an upstream release
includes equivalent fixes and passes these regressions.
