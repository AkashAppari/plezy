import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/database/app_database.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/plex_client.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/media_items.dart';

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

  test('lyrics parse Plex structured responses with singleton media shapes', () async {
    final requests = <http.Request>[];
    final client = makeClient((request) async {
      requests.add(request);
      if (request.url.path == '/library/metadata/track-1') {
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'Metadata': [
                {
                  'ratingKey': 'track-1',
                  'type': 'track',
                  'Media': {
                    'Part': {
                      'Stream': {
                        'id': '501',
                        'key': '/library/streams/501',
                        'streamType': '4',
                        'codec': 'lrc',
                        'format': 'lrc',
                      },
                    },
                  },
                },
              ],
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/library/streams/501') {
        return http.Response(
          '''
<?xml version="1.0" encoding="UTF-8"?>
<MediaContainer size="1">
  <Lyrics timed="1">
    <Line startOffset="500">
      <Span text="First line" />
    </Line>
    <Line startOffset="4000">
      <Span text="Second " />
      <Span text="line" />
    </Line>
  </Lyrics>
</MediaContainer>
''',
          200,
          headers: const {'content-type': 'application/xml'},
        );
      }
      return http.Response('not found', 404);
    });
    addTearDown(client.close);

    final lyrics = await client.fetchLyrics(testMediaItem(id: 'track-1', kind: MediaKind.track));

    expect(lyrics, isNotNull);
    expect(lyrics!.synced, isTrue);
    expect(lyrics.lines.map((line) => line.text), ['First line', 'Second line']);
    expect(lyrics.lines.map((line) => line.startMs), [500, 4000]);
    expect(requests.map((request) => request.url.path), ['/library/metadata/track-1', '/library/streams/501']);
    expect(requests.last.url.queryParameters, containsPair('format', 'xml'));
    expect(requests.last.url.queryParameters, isNot(contains('includeInlineAttribution')));
    expect(requests.last.headers['accept'], 'application/xml');
  });

  test('lyrics refresh incomplete cached metadata and prefer LRC streams', () async {
    const metadataEndpoint = '/library/metadata/track-1';
    await PlexApiCache.instance.put(ServerId('server-id'), metadataEndpoint, {
      'MediaContainer': {
        'Metadata': [
          {'ratingKey': 'track-1', 'type': 'track'},
        ],
      },
    });
    final requestedPaths = <String>[];
    final client = makeClient((request) async {
      requestedPaths.add(request.url.path);
      if (request.url.path == metadataEndpoint) {
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'Metadata': [
                {
                  'ratingKey': 'track-1',
                  'type': 'track',
                  'Media': [
                    {
                      'Part': [
                        {
                          'Stream': [
                            {'id': 501, 'key': '/library/streams/501', 'streamType': 4, 'codec': 'txt'},
                            {'id': 502, 'key': '/library/streams/502', 'streamType': 4, 'codec': 'lrc'},
                          ],
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/library/streams/502') {
        return http.Response('[00:01.00]Preferred timed line', 200, headers: const {'content-type': 'text/plain'});
      }
      return http.Response('not found', 404);
    });
    addTearDown(client.close);

    final lyrics = await client.fetchLyrics(testMediaItem(id: 'track-1', kind: MediaKind.track));

    expect(lyrics, isNotNull);
    expect(lyrics!.synced, isTrue);
    expect(lyrics.lines.single.text, 'Preferred timed line');
    expect(requestedPaths, [metadataEndpoint, '/library/streams/502']);
  });

  test('cached child fetch rejects decodable HTTP error responses before caching', () async {
    for (final statusCode in [404, 500]) {
      final parentId = 'parent-$statusCode';
      final endpoint = '/library/metadata/$parentId/children';
      var requestCount = 0;
      final client = makeClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'size': 1,
              'totalSize': 1,
              'Metadata': [
                {'ratingKey': 'error-child', 'type': 'season', 'title': 'Must Not Parse'},
              ],
            },
          }),
          statusCode,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);

      await expectLater(
        client.fetchChildren(parentId),
        throwsA(
          isA<MediaServerHttpException>()
              .having((error) => error.statusCode, 'statusCode', statusCode)
              .having((error) => error.requestUri?.path, 'request path', endpoint),
        ),
      );

      expect(requestCount, 1);
      expect(await PlexApiCache.instance.get(ServerId('server-id'), endpoint), isNull);
    }
  });

  test('HTTP failure falls back to the existing child cache without replacing it', () async {
    const parentId = 'cached-parent';
    const endpoint = '/library/metadata/$parentId/children';
    final cachedResponse = {
      'MediaContainer': {
        'size': 1,
        'totalSize': 1,
        'Metadata': [
          {'ratingKey': 'cached-child', 'type': 'season', 'title': 'Cached Season'},
        ],
      },
    };
    await PlexApiCache.instance.put(ServerId('server-id'), endpoint, cachedResponse);
    var requestCount = 0;
    final client = makeClient((request) async {
      requestCount++;
      return http.Response(
        jsonEncode({
          'MediaContainer': {
            'size': 1,
            'totalSize': 1,
            'Metadata': [
              {'ratingKey': 'error-child', 'type': 'season', 'title': 'Must Not Replace Cache'},
            ],
          },
        }),
        500,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final children = await client.fetchChildren(parentId);

    expect(requestCount, 1);
    expect(children.map((child) => child.id), ['cached-child']);
    expect(children.single.title, 'Cached Season');
    expect(await PlexApiCache.instance.get(ServerId('server-id'), endpoint), cachedResponse);
  });

  test('successful child fetch parses and caches the response', () async {
    const parentId = 'fresh-parent';
    const endpoint = '/library/metadata/$parentId/children';
    final responseData = {
      'MediaContainer': {
        'size': 1,
        'totalSize': 1,
        'Metadata': [
          {'ratingKey': 'fresh-child', 'type': 'season', 'title': 'Fresh Season'},
        ],
      },
    };
    var requestCount = 0;
    final client = makeClient((request) async {
      requestCount++;
      return http.Response(jsonEncode(responseData), 200, headers: {'content-type': 'application/json'});
    });
    addTearDown(client.close);

    final children = await client.fetchChildren(parentId);

    expect(requestCount, 1);
    expect(children.map((child) => child.id), ['fresh-child']);
    expect(children.single.title, 'Fresh Season');
    expect(await PlexApiCache.instance.get(ServerId('server-id'), endpoint), responseData);
  });

  test('child retrieval walks every page and caches the combined result', () async {
    const parentId = 'paged-parent';
    const endpoint = '/library/metadata/$parentId/children';
    final requests = <Uri>[];
    final client = makeClient((request) async {
      requests.add(request.url);
      final start = int.parse(request.url.queryParameters['X-Plex-Container-Start']!);
      final metadata = start == 0
          ? [
              {'ratingKey': 'season-1', 'type': 'season', 'title': 'Season 1'},
              {'ratingKey': 'season-2', 'type': 'season', 'title': 'Season 2'},
            ]
          : [
              {'ratingKey': 'season-3', 'type': 'season', 'title': 'Season 3'},
            ];
      return http.Response(
        jsonEncode({
          'MediaContainer': {'size': metadata.length, 'totalSize': 3, 'Metadata': metadata},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final children = await client.fetchChildren(parentId);
    final cached = await PlexApiCache.instance.get(ServerId('server-id'), endpoint);
    final cachedContainer = cached!['MediaContainer'] as Map<String, dynamic>;
    final cachedMetadata = cachedContainer['Metadata'] as List<dynamic>;

    expect(children.map((child) => child.id), ['season-1', 'season-2', 'season-3']);
    expect(requests.map((uri) => uri.queryParameters['X-Plex-Container-Start']), ['0', '2']);
    expect(requests.every((uri) => uri.queryParameters['X-Plex-Container-Size'] == '200'), isTrue);
    expect(requests.every((uri) => uri.queryParameters['includeStreams'] == '1'), isTrue);
    expect(cachedContainer['size'], 3);
    expect(cachedContainer['totalSize'], 3);
    expect(cachedMetadata.map((item) => (item as Map<String, dynamic>)['ratingKey']), [
      'season-1',
      'season-2',
      'season-3',
    ]);
  });

  test('artist albums include every Plex release bucket and cache all pages', () async {
    const cacheKey = '/library/metadata/artist-1/children';
    final requests = <Uri>[];
    final client = makeClient((request) async {
      requests.add(request.url);
      final start = int.parse(request.url.queryParameters['X-Plex-Container-Start']!);
      final metadata = start == 0
          ? [
              {'ratingKey': 'album-lp', 'type': 'album', 'title': 'LP'},
              {'ratingKey': 'album-ep', 'type': 'album', 'title': 'EP'},
            ]
          : [
              {'ratingKey': 'album-single', 'type': 'album', 'title': 'Single'},
              {'ratingKey': 'album-compilation', 'type': 'album', 'title': 'Compilation'},
            ];
      return http.Response(
        jsonEncode({
          'MediaContainer': {'librarySectionID': 7, 'size': metadata.length, 'totalSize': 4, 'Metadata': metadata},
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);

    final albums = await client.fetchArtistAlbums(
      testMediaItem(id: 'artist-1', kind: MediaKind.artist, libraryId: '7'),
    );
    final cached = await PlexApiCache.instance.get(ServerId('server-id'), cacheKey);
    final cachedContainer = cached!['MediaContainer'] as Map<String, dynamic>;
    final cachedMetadata = cachedContainer['Metadata'] as List<dynamic>;

    expect(albums.map((album) => album.id), ['album-lp', 'album-ep', 'album-single', 'album-compilation']);
    expect(requests, hasLength(2));
    expect(requests.every((uri) => uri.path == '/library/sections/7/all'), isTrue);
    expect(requests.every((uri) => uri.queryParameters['type'] == '9'), isTrue);
    expect(requests.every((uri) => uri.queryParameters['artist.id'] == 'artist-1'), isTrue);
    expect(requests.every((uri) => uri.queryParameters['sort'] == 'album.year:desc'), isTrue);
    expect(requests.map((uri) => uri.queryParameters['X-Plex-Container-Start']), ['0', '2']);
    expect(cachedMetadata.map((item) => (item as Map<String, dynamic>)['ratingKey']), [
      'album-lp',
      'album-ep',
      'album-single',
      'album-compilation',
    ]);
  });

  test('artist albums resolve a missing music section from artist metadata', () async {
    final requestedPaths = <String>[];
    final client = makeClient((request) async {
      requestedPaths.add(request.url.path);
      if (request.url.path == '/library/metadata/artist-1') {
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'librarySectionID': 7,
              'Metadata': [
                {'ratingKey': 'artist-1', 'type': 'artist', 'title': 'Artist'},
              ],
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/library/sections/7/all') {
        return http.Response(
          jsonEncode({
            'MediaContainer': {
              'librarySectionID': 7,
              'size': 1,
              'Metadata': [
                {'ratingKey': 'album-1', 'type': 'album', 'title': 'Album'},
              ],
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });
    addTearDown(client.close);

    final albums = await client.fetchArtistAlbums(testMediaItem(id: 'artist-1', kind: MediaKind.artist));

    expect(requestedPaths, ['/library/metadata/artist-1', '/library/sections/7/all']);
    expect(albums.map((album) => album.id), ['album-1']);
  });
}
