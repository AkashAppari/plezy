import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/models/trackers/anime_ids.dart';
import 'package:plezy/models/trackers/tracker_context.dart';
import 'package:plezy/services/trackers/anilist/anilist_session.dart';
import 'package:plezy/services/trackers/anilist/anilist_tracker.dart';
import 'package:plezy/utils/external_ids.dart';

AnilistSession _session() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return AnilistSession(accessToken: 'token', expiresAt: now + 86400, createdAt: now);
}

TrackerContext _episode({int anilistId = 21, int episodeNumber = 12, int? animeProgress = 12}) {
  return TrackerContext.episode(
    external: const ExternalIds(tvdb: 1),
    anime: AnimeIds(anilist: anilistId),
    ratingKey: 'episode-1',
    libraryGlobalKey: null,
    season: 1,
    episodeNumber: episodeNumber,
    animeProgress: animeProgress,
  );
}

void main() {
  group('AnilistTracker', () {
    final tracker = AnilistTracker.instance;

    tearDown(() {
      tracker.rebindSession(null, onSessionInvalidated: () {});
    });

    test('marks completed when scoped progress reaches AniList total', () async {
      final saved = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        final body = json.decode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;
        if (query.contains('Media(id:')) {
          return http.Response(
            json.encode({
              'data': {
                'Media': {'episodes': 12},
              },
            }),
            200,
          );
        }
        if (query.contains('SaveMediaListEntry')) {
          saved.add((body['variables'] as Map).cast<String, dynamic>());
          return http.Response(
            json.encode({
              'data': {
                'SaveMediaListEntry': {'id': 1},
              },
            }),
            200,
          );
        }
        fail('Unexpected AniList query: $query');
      });
      tracker.rebindSession(_session(), onSessionInvalidated: () {}, httpClient: client);

      await tracker.markWatched(_episode(animeProgress: 13));

      expect(saved.single, {'mediaId': 21, 'progress': 12, 'status': 'COMPLETED'});
    });

    test('keeps fallback local progress as current without total lookup', () async {
      final saved = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        final body = json.decode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;
        if (query.contains('SaveMediaListEntry')) {
          saved.add((body['variables'] as Map).cast<String, dynamic>());
          return http.Response(
            json.encode({
              'data': {
                'SaveMediaListEntry': {'id': 1},
              },
            }),
            200,
          );
        }
        fail('Unexpected AniList query: $query');
      });
      tracker.rebindSession(_session(), onSessionInvalidated: () {}, httpClient: client);

      await tracker.markWatched(_episode(animeProgress: null));

      expect(saved.single, {'mediaId': 21, 'progress': 12, 'status': 'CURRENT'});
    });

    test('keeps progress current when AniList total is unknown', () async {
      final saved = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        final body = json.decode(request.body) as Map<String, dynamic>;
        final query = body['query'] as String;
        if (query.contains('Media(id:')) {
          return http.Response(
            json.encode({
              'data': {
                'Media': {'episodes': null},
              },
            }),
            200,
          );
        }
        if (query.contains('SaveMediaListEntry')) {
          saved.add((body['variables'] as Map).cast<String, dynamic>());
          return http.Response(
            json.encode({
              'data': {
                'SaveMediaListEntry': {'id': 1},
              },
            }),
            200,
          );
        }
        fail('Unexpected AniList query: $query');
      });
      tracker.rebindSession(_session(), onSessionInvalidated: () {}, httpClient: client);

      await tracker.markWatched(_episode());

      expect(saved.single, {'mediaId': 21, 'progress': 12, 'status': 'CURRENT'});
    });
  });
}
