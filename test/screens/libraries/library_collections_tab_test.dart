import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/models/plex/plex_config.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/libraries/tabs/library_collections_tab.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/plex_client.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/card_inflation_budget.dart';
import 'package:plezy/widgets/focusable_media_card.dart';
import 'package:plezy/widgets/media_card_sliver_layout.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

final _serverId = ServerId('collection-server');
final _musicLibrary = MediaLibrary(
  id: 'music',
  backend: MediaBackend.plex,
  title: 'Music',
  kind: MediaKind.artist,
  serverId: _serverId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    CardInflationBudget.reset();
    await SettingsService.getInstance();
  });

  testWidgets('music library collections use square grid geometry and square cards', (tester) async {
    final harness = _CollectionHarness();
    addTearDown(harness.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: harness.provider,
        child: InputModeTracker(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: MainScreenFocusScope(
              focusSidebar: () {},
              focusContent: () {},
              isSidebarFocused: false,
              sideNavigationWidth: 0,
              child: Scaffold(
                body: NestedScrollView(
                  headerSliverBuilder: (context, _) => [
                    SliverOverlapAbsorber(
                      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                      sliver: const SliverToBoxAdapter(child: SizedBox(height: 1)),
                    ),
                  ],
                  body: LibraryCollectionsTab(library: _musicLibrary, suppressAutoFocus: true, onBack: () {}),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final layout = tester.widget<MediaCardSliverLayout>(find.byType(MediaCardSliverLayout));
    expect(layout.shape, CardShape.square);
    expect(layout.fullBleedImage, isFalse);
    expect(tester.widget<FocusableMediaCard>(find.byType(FocusableMediaCard)).cardShapeOverride, CardShape.square);
  });
}

class _CollectionHarness {
  late final AppDatabase database;
  late final MultiServerManager manager;
  late final MultiServerProvider provider;

  _CollectionHarness() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(database);
    final client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example.com',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Plezy',
        version: 'test',
      ),
      serverId: _serverId,
      httpClient: MockClient((request) async {
        if (request.url.path != '/library/sections/music/collections') {
          return http.Response('not found', 404);
        }
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'size': 1,
              'totalSize': 1,
              'Metadata': [
                {'ratingKey': 'collection-1', 'type': 'collection', 'title': 'Music Collection', 'childCount': 4},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    provider = MultiServerProvider(manager, DataAggregationService(manager));
  }

  Future<void> dispose() async {
    provider.dispose();
    manager.dispose();
    await database.close();
  }
}
