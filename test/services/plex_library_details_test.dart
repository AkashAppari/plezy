import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/models/plex/plex_config.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/plex_client.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() async {
    await db.close();
  });

  PlexClient makeClient(Future<http.Response> Function(http.Request request) handler) {
    return PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example.com',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Plezy',
        version: '1',
      ),
      serverId: 'server-id',
      httpClient: MockClient(handler),
    );
  }

  test('filters and sorts use dedicated Plex endpoints', () async {
    final requests = <Uri>[];
    final client = makeClient((request) async {
      requests.add(request.url);
      return switch (request.url.path) {
        '/library/sections/1/filters' => http.Response(
          jsonEncode(_filtersPayload()),
          200,
          headers: {'content-type': 'application/json'},
        ),
        '/library/sections/1/sorts' => http.Response(
          jsonEncode(_sortsPayload()),
          200,
          headers: {'content-type': 'application/json'},
        ),
        _ => http.Response('not found', 404),
      };
    });
    addTearDown(client.close);

    final filters = await client.getLibraryFilters('1');
    final sorts = await client.fetchSortOptions('1', libraryType: 'show');

    expect(requests.map((u) => u.path), ['/library/sections/1/filters', '/library/sections/1/sorts']);
    expect(requests.every((u) => u.queryParameters.isEmpty), isTrue);
    expect(filters.map((f) => f.filter), ['genre', 'year', 'unwatched']);
    expect(sorts.map((s) => s.key), [
      'titleSort',
      'rating',
      'audienceRating',
      'addedAt',
      'episode.addedAt',
      'lastViewedAt',
      'random',
    ]);
  });
}

Map<String, dynamic> _filtersPayload() => {
  'MediaContainer': {
    'Directory': [
      {
        'filter': 'genre',
        'filterType': 'string',
        'key': '/library/sections/1/genre',
        'title': 'Genre',
        'type': 'filter',
      },
      {'filter': 'year', 'filterType': 'integer', 'key': '/library/sections/1/year', 'title': 'Year', 'type': 'filter'},
      {
        'filter': 'unwatched',
        'filterType': 'boolean',
        'key': '/library/sections/1/unwatched',
        'title': 'Unwatched',
        'type': 'filter',
      },
    ],
  },
};

Map<String, dynamic> _sortsPayload() => {
  'MediaContainer': {
    'Directory': [
      {'defaultDirection': 'asc', 'descKey': 'titleSort:desc', 'key': 'titleSort', 'title': 'Title'},
      {'defaultDirection': 'desc', 'descKey': 'rating:desc', 'key': 'rating', 'title': 'Critic Rating'},
      {
        'defaultDirection': 'desc',
        'descKey': 'audienceRating:desc',
        'key': 'audienceRating',
        'title': 'Audience Rating',
      },
      {'defaultDirection': 'desc', 'descKey': 'addedAt:desc', 'key': 'addedAt', 'title': 'Date Added'},
      {
        'defaultDirection': 'desc',
        'descKey': 'episode.addedAt:desc',
        'key': 'episode.addedAt',
        'title': 'Last Episode Date Added',
      },
      {'defaultDirection': 'desc', 'descKey': 'lastViewedAt:desc', 'key': 'lastViewedAt', 'title': 'Date Viewed'},
      {'defaultDirection': 'desc', 'descKey': 'random:desc', 'key': 'random', 'title': 'Randomly'},
    ],
  },
};
