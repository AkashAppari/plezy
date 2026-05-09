import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/media/media_sort.dart';
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

  test('filters and sorts share the includeDetails section request', () async {
    var requestCount = 0;
    final client = makeClient((request) async {
      requestCount++;
      expect(request.url.path, '/library/sections/1');
      expect(request.url.queryParameters['includeDetails'], '1');
      return http.Response(jsonEncode(_sectionDetailsPayload()), 200, headers: {'content-type': 'application/json'});
    });
    addTearDown(client.close);

    final results = await Future.wait<Object>([
      client.getLibraryFilters('1'),
      client.fetchSortOptions('1', libraryType: 'movie'),
    ]);

    final filters = results[0] as List<MediaFilter>;
    final sorts = results[1] as List<MediaSort>;
    expect(requestCount, 1);
    expect(filters.map((f) => f.filter), ['genre', 'year']);
    expect(sorts.map((s) => s.key), ['addedAt', 'titleSort']);
  });
}

Map<String, dynamic> _sectionDetailsPayload() => {
  'MediaContainer': {
    'Directory': [
      {'key': 'all', 'title': 'All Movies'},
      {
        'key': '/library/sections/1/all?type=1',
        'title': 'Movies',
        'type': '1',
        'Filter': [
          {
            'filter': 'genre',
            'filterType': 'string',
            'key': '/library/sections/1/genre',
            'title': 'Genre',
            'type': 'filter',
          },
          {
            'filter': 'year',
            'filterType': 'integer',
            'key': '/library/sections/1/year',
            'title': 'Year',
            'type': 'filter',
          },
        ],
        'Sort': [
          {'defaultDirection': 'desc', 'descKey': 'addedAt:desc', 'key': 'addedAt', 'title': 'Date Added'},
          {'defaultDirection': 'asc', 'descKey': 'titleSort:desc', 'key': 'titleSort', 'title': 'Name'},
        ],
      },
    ],
  },
};
