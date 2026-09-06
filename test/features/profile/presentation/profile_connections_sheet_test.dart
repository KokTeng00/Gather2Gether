import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/profile_connection.dart';
import 'package:gather2gether/features/profile/presentation/profile_connections_sheet.dart';

class _Repository extends ProfileRepository {
  _Repository(this.respond);
  final Future<ProfileConnectionPage> Function(String, String?) respond;
  final calls =
      <
        ({
          String? owner,
          ProfileConnectionKind kind,
          String query,
          String? cursor,
        })
      >[];
  @override
  Future<ProfileConnectionPage> fetchConnections({
    String? profileId,
    required ProfileConnectionKind kind,
    String query = '',
    String? cursor,
  }) {
    calls.add((owner: profileId, kind: kind, query: query, cursor: cursor));
    return respond(query, cursor);
  }
}

const maya = ProfileConnection(
  id: 'maya',
  displayName: 'Maya Chen',
  username: 'maya_local',
);
const alex = ProfileConnection(
  id: 'alex',
  displayName: 'Alex Morgan',
  username: 'alex_local',
);

Future<void> _pumpList(
  WidgetTester tester,
  _Repository repository, {
  String? owner,
  ThemeData? theme,
  bool settle = true,
  int? initialCount,
  ProfileConnectionKind kind = ProfileConnectionKind.followers,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              const Text('Profile behind sheet'),
              TextButton(
                onPressed: () => showProfileConnectionsSheet(
                  context: context,
                  repository: repository,
                  kind: kind,
                  profileId: owner,
                  initialCount: initialCount,
                ),
                child: const Text('Open followers'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open followers'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  for (final kind in ProfileConnectionKind.values) {
    testWidgets('zero ${kind.name} keeps its empty message if loading fails', (
      tester,
    ) async {
      final pending = Completer<ProfileConnectionPage>();
      await _pumpList(
        tester,
        _Repository((_, _) => pending.future),
        initialCount: 0,
        kind: kind,
      );
      final message = kind == ProfileConnectionKind.followers
          ? 'No followers yet'
          : 'Not following anyone yet';
      expect(find.text(message), findsOneWidget);
      pending.completeError(Exception('unavailable'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a stale zero count still loads newly added connections', (
    tester,
  ) async {
    await _pumpList(
      tester,
      _Repository(
        (_, _) async =>
            const ProfileConnectionPage(members: [maya], canSearch: true),
      ),
      initialCount: 0,
    );
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.text('No followers yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'sheet expands and collapses over the profile in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        final repository = _Repository(
          (_, _) async =>
              const ProfileConnectionPage(members: [], canSearch: false),
        );
        await _pumpList(
          tester,
          repository,
          theme: dark ? AppTheme.dark : AppTheme.light,
        );
        final sheet = find.byKey(const Key('app-sheet'));
        final header = find.byKey(const Key('app-sheet-header'));
        final list = find.byKey(const Key('connections-list'));
        final screenHeight =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        final collapsedTop = tester.getTopLeft(sheet).dy;
        expect(collapsedTop, closeTo(screenHeight * 0.4, 1));
        expect(find.text('Profile behind sheet'), findsOneWidget);
        expect(find.byTooltip('Close'), findsNothing);
        expect(
          tester.widget<Material>(sheet).color,
          (dark ? AppTheme.dark : AppTheme.light).colorScheme.surface,
        );

        // Empty lists must participate in dragging just like populated lists.
        await tester.drag(list, const Offset(0, -350));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(sheet).dy, closeTo(0, 1));
        await tester.drag(header, const Offset(0, 240));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(sheet).dy, closeTo(collapsedTop, 1));
        expect(find.text('No followers yet'), findsOneWidget);

        await tester.tap(find.byKey(const Key('app-sheet-drag-handle')));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(sheet).dy, closeTo(0, 1));
        await tester.drag(list, const Offset(0, 240));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(sheet).dy, closeTo(collapsedTop, 1));
        await tester.drag(dark ? header : list, const Offset(0, 240));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(find.text('Profile behind sheet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('loading and failed lists can expand and collapse', (
    tester,
  ) async {
    final pending = Completer<ProfileConnectionPage>();
    await _pumpList(
      tester,
      _Repository((_, _) => pending.future),
      settle: false,
    );
    final sheet = find.byKey(const Key('app-sheet'));
    await tester.drag(
      find.byKey(const Key('connections-list')),
      const Offset(0, -350),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getTopLeft(sheet).dy, closeTo(0, 1));
    pending.completeError(Exception('unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('app-sheet-header')),
      const Offset(0, 240),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(sheet).dy, greaterThan(100));
    await tester.drag(
      find.byKey(const Key('app-sheet-header')),
      const Offset(0, 240),
    );
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner search expands above the keyboard on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await _pumpList(
      tester,
      _Repository(
        (_, _) async =>
            const ProfileConnectionPage(members: [maya, alex], canSearch: true),
      ),
    );
    await tester.tap(find.byKey(const Key('connections-search')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byKey(const Key('app-sheet')));
    expect(sheet.top, closeTo(0, 1));
    expect(sheet.bottom, closeTo(514, 1));
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owners search by username or display name and clear results', (
    tester,
  ) async {
    final repository = _Repository(
      (query, _) async => ProfileConnectionPage(
        members: query.isEmpty
            ? [maya, alex]
            : query.contains('maya')
            ? [maya]
            : [alex],
        canSearch: true,
      ),
    );
    await _pumpList(tester, repository);
    final search = find.byKey(const Key('connections-search'));
    expect(search, findsOneWidget);
    await tester.enterText(search, '@maya_local');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repository.calls.last.query, '@maya_local');
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.byKey(const ValueKey('connection-alex')), findsNothing);
    await tester.enterText(search, 'Alex Morgan');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repository.calls.last.query, 'Alex Morgan');
    expect(find.byKey(const ValueKey('connection-alex')), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.byKey(const ValueKey('connection-alex')), findsOneWidget);
  });

  testWidgets('visitors scroll through pages without a search field', (
    tester,
  ) async {
    final people = List.generate(
      20,
      (i) => ProfileConnection(
        id: 'member-$i',
        displayName: 'Member $i',
        username: 'member_$i',
      ),
    );
    final repository = _Repository(
      (_, cursor) async => ProfileConnectionPage(
        members: cursor == null ? people : [people.last, alex],
        canSearch: false,
        nextCursor: cursor == null ? 'page-two' : null,
      ),
    );
    await _pumpList(tester, repository, owner: 'another-owner');
    expect(find.byType(TextField), findsNothing);
    await tester.drag(
      find.byKey(const Key('connections-list')),
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('connections-list')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(repository.calls.last.cursor, 'page-two');
    expect(
      repository.calls.every(
        (call) => call.query.isEmpty && call.owner == 'another-owner',
      ),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('connection-alex')),
      300,
    );
    expect(find.byKey(const ValueKey('connection-alex')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    // The handle can collapse the sheet even after scrolling down the list.
    await tester.drag(
      find.byKey(const Key('app-sheet-header')),
      const Offset(0, 240),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('app-sheet'))).dy,
      greaterThan(100),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('late search responses cannot replace newer results', (
    tester,
  ) async {
    final old = Completer<ProfileConnectionPage>();
    final repository = _Repository(
      (query, _) => query == 'old'
          ? old.future
          : Future.value(
              ProfileConnectionPage(
                members: query.isEmpty ? [maya, alex] : [alex],
                canSearch: true,
              ),
            ),
    );
    await _pumpList(tester, repository);
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    old.complete(const ProfileConnectionPage(members: [maya], canSearch: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('connection-alex')), findsOneWidget);
    expect(find.text('Maya Chen'), findsNothing);
  });

  testWidgets(
    'a failed list can retry without losing owner search permission',
    (tester) async {
      var attempts = 0;
      final repository = _Repository((_, _) async {
        if (attempts++ == 0) throw Exception('unavailable');
        return const ProfileConnectionPage(members: [], canSearch: true);
      });
      await _pumpList(tester, repository);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No followers yet'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
