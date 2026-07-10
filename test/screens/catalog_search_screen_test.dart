import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/screens/catalog_search_screen.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';

import '../test_helpers/prefs.dart';

/// Only the members the search screen touches; everything else throws.
class _FakeSearchSource implements CatalogSource {
  final queries = <String>[];
  bool failNext = false;

  @override
  CatalogSourceId get id => CatalogSourceId.trakt;

  @override
  String get displayName => 'Trakt';

  @override
  Future<List<CatalogItem>> search(String query, {int limit = 30}) async {
    queries.add(query);
    if (failNext) {
      failNext = false;
      throw Exception('boom');
    }
    return [
      CatalogItem(source: id, kind: MediaKind.movie, title: 'result: $query', ids: const CatalogItemIds(tmdb: 1)),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _FakeSearchSource source) async {
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: CatalogSearchScreen(source: source),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  testWidgets('reverting to the last-searched query cancels the pending debounce', (tester) async {
    final source = _FakeSearchSource();
    await _pump(tester, source);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(source.queries, ['abc']);
    expect(_state(tester).searchResults.single.title, 'result: abc');

    // Type ahead, then revert to the shown query before the debounce fires:
    // the armed 'abcd' search must never run.
    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(source.queries, ['abc']);
    expect(_state(tester).searchResults.single.title, 'result: abc');
  });

  testWidgets('failed search shows the failure state and recovers on retry', (tester) async {
    final source = _FakeSearchSource()..failNext = true;
    await _pump(tester, source);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text(t.explore.searchFailed), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(_state(tester).searchResults.single.title, 'result: abcd');
    expect(find.text(t.explore.searchFailed), findsNothing);
  });
}

dynamic _state(WidgetTester tester) => tester.state<State<CatalogSearchScreen>>(find.byType(CatalogSearchScreen));
