import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/theme/app_theme.dart';
import 'package:gather2gether/features/profile/data/profile_repository.dart';
import 'package:gather2gether/features/profile/domain/profile_connection.dart';
import 'package:gather2gether/features/profile/presentation/profile_connections_screen.dart';

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
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: ProfileConnectionsScreen(
        repository: repository,
        kind: ProfileConnectionKind.followers,
        profileId: owner,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
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
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
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
