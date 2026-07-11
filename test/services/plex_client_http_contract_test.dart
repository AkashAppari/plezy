import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/models/plex/plex_config.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/plex_client.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() => db.close());

  PlexClient makeClient(Future<http.Response> Function(http.Request request) handler) {
    return PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example.com',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Plezy',
        version: '1',
      ),
      serverId: ServerId('server-id'),
      httpClient: MockClient(handler),
    );
  }

  test('void mutations surface non-success responses', () async {
    final client = makeClient((_) async => http.Response('rejected', 500));
    addTearDown(client.close);

    for (final mutation in <Future<void> Function()>[
      () => client.cancelActivity('activity-id'),
      () => client.removeFromOnDeck('item-id'),
      () => client.emptyLibraryTrash('library-id'),
    ]) {
      await expectLater(mutation(), throwsA(isA<MediaServerHttpException>()));
    }
  });

  test('nullable creation APIs reject non-success response bodies', () async {
    final client = makeClient((_) async => http.Response('rejected', 500));
    addTearDown(client.close);

    expect(await client.createCollectionFromUri(sectionId: '1', title: 'Collection', uri: 'server://items'), isNull);
    expect(await client.createPlayQueue(uri: 'server://items', type: 'video'), isNull);
  });
}
