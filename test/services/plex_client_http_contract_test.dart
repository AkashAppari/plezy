import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/database/app_database.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/plex_client.dart';

import '../test_helpers/backend_client_fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() => db.close());

  PlexClient makeClient(Future<http.Response> Function(http.Request request) handler) =>
      testPlexClient(serverId: ServerId('server-id'), handler: handler);

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

  test('play queue accepts numeric strings from Plex', () async {
    final client = makeClient(
      (_) async => http.Response(
        jsonEncode({
          'MediaContainer': {
            'playQueueID': '42',
            'playQueueSelectedItemID': '7',
            'playQueueSelectedItemOffset': '1',
            'playQueueTotalCount': '3',
            'playQueueVersion': '5',
            'size': '3',
            'Metadata': <dynamic>[],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.close);

    final queue = await client.createPlayQueue(uri: 'server://items', type: 'video');

    expect(queue?.playQueueID, 42);
    expect(queue?.playQueueSelectedItemID, 7);
    expect(queue?.playQueueSelectedItemOffset, 1);
    expect(queue?.playQueueTotalCount, 3);
    expect(queue?.playQueueVersion, 5);
    expect(queue?.size, 3);
  });

  test('activities tolerate scalar drift and skip only malformed rows', () async {
    final client = makeClient(
      (_) async => http.Response(
        jsonEncode({
          'MediaContainer': {
            'Activity': [
              {
                'uuid': 'activity-1',
                'type': 'library.update',
                'title': 'Scanning',
                'subtitle': 'Movies',
                'progress': 25,
                'cancellable': false,
              },
              'not-an-activity',
              {'type': 'library.update', 'title': 'Missing identity'},
              {'uuid': 42, 'type': 7, 'title': true, 'subtitle': 99, 'progress': '75', 'cancellable': '1'},
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.close);

    final activities = await client.getActivities();

    expect(activities, hasLength(2));
    expect(activities.first.uuid, 'activity-1');
    expect(activities.first.progress, 25);
    expect(activities.first.cancellable, isFalse);
    expect(activities.last.uuid, '42');
    expect(activities.last.type, '7');
    expect(activities.last.title, 'true');
    expect(activities.last.subtitle, '99');
    expect(activities.last.progress, 75);
    expect(activities.last.cancellable, isTrue);
  });

  test('metadata edit preserves locked fields and removed tag wire format', () async {
    http.Request? captured;
    final client = makeClient((request) async {
      captured = request;
      return http.Response('', 200);
    });
    addTearDown(client.close);

    final updated = await client.updateMetadata(
      sectionId: 1,
      ratingKey: 'item-id',
      typeNumber: 1,
      title: 'Renamed',
      tagChanges: {
        'genre': (current: ['Drama'], original: ['Drama', 'Science Fiction']),
      },
    );

    expect(updated, isTrue);
    expect(captured?.method, 'PUT');
    expect(captured?.url.path, '/library/sections/1/all');
    expect(captured?.url.queryParameters, containsPair('title.value', 'Renamed'));
    expect(captured?.url.queryParameters, containsPair('title.locked', '1'));
    expect(captured?.url.queryParameters, containsPair('genre[0].tag.tag', 'Drama'));
    expect(captured?.url.queryParameters, containsPair('genre[].tag.tag-', 'Science%20Fiction'));
    expect(captured?.url.queryParameters, containsPair('genre.locked', '1'));
  });
}
