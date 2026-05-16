import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  testWidgets('selects preferred hub when hubs are inserted asynchronously', (tester) async {
    final activeHubIds = <String>[];

    Widget buildRail(List<MediaHub> hubs, {String? initialHubId, String? initialItemId, bool autofocus = false}) {
      final serverManager = MultiServerManager();
      return ChangeNotifierProvider<MultiServerProvider>(
        create: (_) => MultiServerProvider(serverManager, DataAggregationService(serverManager)),
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 720,
              child: TvBrowseRail(
                key: const ValueKey('rail'),
                hubs: hubs,
                initialHubId: initialHubId,
                initialItemId: initialItemId,
                autofocus: autofocus,
                iconForHub: (_, _) => Icons.tv_rounded,
                onActiveHubChanged: (hub, _) => activeHubIds.add(hub.id),
              ),
            ),
          ),
        ),
      );
    }

    const castHub = MediaHub(id: 'detail_actors', title: 'Cast', type: 'person', items: <MediaItem>[]);
    const preferredSeason = MediaHub(id: 'detail_season_1', title: 'Season 2', type: 'episode', items: <MediaItem>[]);

    await tester.pumpWidget(buildRail(const [castHub]));
    await tester.pump();

    await tester.pumpWidget(buildRail(const [preferredSeason, castHub], initialHubId: preferredSeason.id));
    await tester.pump();

    expect(activeHubIds, containsAllInOrder(['detail_actors', 'detail_season_1']));
    expect(activeHubIds.last, 'detail_season_1');
  });

  testWidgets('selects preferred item when active hub items are populated asynchronously', (tester) async {
    final focusedItemIds = <String>[];

    Widget buildRail(List<MediaHub> hubs, {String? initialItemId}) {
      final serverManager = MultiServerManager();
      return ChangeNotifierProvider<MultiServerProvider>(
        create: (_) => MultiServerProvider(serverManager, DataAggregationService(serverManager)),
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 720,
              child: TvBrowseRail(
                key: const ValueKey('rail'),
                hubs: hubs,
                initialItemId: initialItemId,
                iconForHub: (_, _) => Icons.tv_rounded,
                onFocusedItemChanged: (item) => focusedItemIds.add(item.id),
              ),
            ),
          ),
        ),
      );
    }

    final episode1 = MediaItem(
      id: 'episode_1',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      title: 'Episode 1',
    );
    final episode2 = MediaItem(
      id: 'episode_2',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      title: 'Episode 2',
    );
    const emptySeason = MediaHub(id: 'detail_season_0', title: 'Season 1', type: 'episode', items: <MediaItem>[]);
    final loadedSeason = MediaHub(
      id: emptySeason.id,
      title: emptySeason.title,
      type: emptySeason.type,
      items: [episode1, episode2],
      size: 2,
    );

    await tester.pumpWidget(buildRail(const [emptySeason], initialItemId: episode2.id));
    await tester.pump();

    await tester.pumpWidget(buildRail([loadedSeason], initialItemId: episode2.id));
    await tester.pump();

    expect(focusedItemIds.last, episode2.id);
  });

  testWidgets('does not autofocus unless requested', (tester) async {
    FocusManager.instance.primaryFocus?.unfocus();

    Widget buildRail({required bool autofocus}) {
      final serverManager = MultiServerManager();
      final item = MediaItem(id: 'item_1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Movie');
      final hub = MediaHub(id: 'hub_1', title: 'Hub', type: 'movie', items: [item], size: 1);
      return ChangeNotifierProvider<MultiServerProvider>(
        create: (_) => MultiServerProvider(serverManager, DataAggregationService(serverManager)),
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 720,
              child: TvBrowseRail(hubs: [hub], autofocus: autofocus, iconForHub: (_, _) => Icons.tv_rounded),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildRail(autofocus: false));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('tv_browse_rail'));

    await tester.pumpWidget(buildRail(autofocus: true));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_browse_rail');
  });
}
