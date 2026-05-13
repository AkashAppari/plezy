import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/models/trackers/fribb_mapping_row.dart';
import 'package:plezy/services/trackers/anime_episode_progress_resolver.dart';
import 'package:plezy/services/trackers/fribb_mapping_store.dart';
import 'package:plezy/services/trackers/tracker_id_resolver.dart';
import 'package:plezy/utils/external_ids.dart';

class _FakeMediaServerClient implements MediaServerClient {
  final Map<String, ExternalIds> externalIdsByItem;
  final List<String> externalIdCalls = [];

  _FakeMediaServerClient(this.externalIdsByItem);

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    externalIdCalls.add(itemId);
    return externalIdsByItem[itemId] ?? const ExternalIds();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFribbLookup implements FribbMappingLookup {
  final List<FribbMappingRow> rows;
  int lookups = 0;

  _FakeFribbLookup(this.rows);

  @override
  Future<List<FribbMappingRow>> lookup({int? tvdbId, int? tmdbId, String? imdbId}) async {
    lookups++;
    return rows;
  }
}

class _FakeAnimeProgressLookup implements AnimeEpisodeProgressLookup {
  ResolvedAnimeProgress? result;
  int resolveCalls = 0;
  int clearCalls = 0;
  MediaItem? lastEpisode;
  AnimeProgressScope? lastScope;

  _FakeAnimeProgressLookup(int? progress, {bool isComplete = false})
    : result = progress == null ? null : ResolvedAnimeProgress(progress: progress, isComplete: isComplete);

  @override
  Future<ResolvedAnimeProgress?> resolve(MediaItem episode, {required AnimeProgressScope scope}) async {
    resolveCalls++;
    lastEpisode = episode;
    lastScope = scope;
    return result;
  }

  @override
  void clearCache() {
    clearCalls++;
  }
}

MediaItem _episode({int season = 23, int number = 6}) => MediaItem(
  id: 'episode-$season-$number',
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: 'Episode $number',
  grandparentId: 'show-1',
  parentIndex: season,
  index: number,
);

TrackerIdResolver _resolver({
  required List<FribbMappingRow> rows,
  required _FakeAnimeProgressLookup animeProgress,
  _FakeFribbLookup? lookup,
}) {
  return TrackerIdResolver(
    _FakeMediaServerClient({'show-1': const ExternalIds(tvdb: 81797, tmdb: 37854, imdb: 'tt0388629')}),
    store: lookup ?? _FakeFribbLookup(rows),
    animeProgress: animeProgress,
  );
}

void main() {
  group('TrackerIdResolver anime progress', () {
    test('one unseasoned regular TV row uses show-scope progress', () async {
      final animeProgress = _FakeAnimeProgressLookup(6);
      final resolver = _resolver(
        animeProgress: animeProgress,
        rows: const [
          FribbMappingRow(tvdbId: 81797, tmdbId: 37854, imdbId: 'tt0388629', malId: 21, anilistId: 21, type: 'TV'),
        ],
      );

      final ids = await resolver.resolveShowForEpisode(_episode());

      expect(ids?.anime?.mal, 21);
      expect(ids?.animeProgressScope, AnimeProgressScope.show);
      expect(ids?.animeProgress, 6);
      expect(ids?.animeProgressComplete, isFalse);
      expect(animeProgress.resolveCalls, 1);
      expect(animeProgress.lastEpisode?.id, 'episode-23-6');
      expect(animeProgress.lastScope, AnimeProgressScope.show);
    });

    test('exact season-scoped row uses season-scope progress', () async {
      final animeProgress = _FakeAnimeProgressLookup(18, isComplete: true);
      final resolver = _resolver(
        animeProgress: animeProgress,
        rows: const [
          FribbMappingRow(tvdbId: 81797, malId: 100, tvdbSeason: 1, type: 'TV'),
          FribbMappingRow(tvdbId: 81797, malId: 200, tvdbSeason: 2, type: 'TV'),
        ],
      );

      final ids = await resolver.resolveShowForEpisode(_episode(season: 2));

      expect(ids?.anime?.mal, 200);
      expect(ids?.animeProgressScope, AnimeProgressScope.season);
      expect(ids?.animeProgress, 18);
      expect(ids?.animeProgressComplete, isTrue);
      expect(animeProgress.resolveCalls, 1);
      expect(animeProgress.lastScope, AnimeProgressScope.season);
    });

    test('does not guess when multiple regular rows are unseasoned', () async {
      final animeProgress = _FakeAnimeProgressLookup(1061);
      final resolver = _resolver(
        animeProgress: animeProgress,
        rows: const [
          FribbMappingRow(tvdbId: 81797, malId: 1, type: 'TV'),
          FribbMappingRow(tvdbId: 81797, malId: 2, type: 'ONA'),
        ],
      );

      final ids = await resolver.resolveShowForEpisode(_episode());

      expect(ids?.anime?.mal, 1);
      expect(ids?.animeProgressScope, isNull);
      expect(ids?.animeProgress, isNull);
      expect(animeProgress.resolveCalls, 0);
    });

    test('movie and special rows do not make a regular TV row ambiguous', () async {
      final animeProgress = _FakeAnimeProgressLookup(1061);
      final resolver = _resolver(
        animeProgress: animeProgress,
        rows: const [
          FribbMappingRow(tvdbId: 81797, malId: 21, type: 'TV'),
          FribbMappingRow(tvdbId: 81797, malId: 459, tvdbSeason: 0, type: 'MOVIE'),
          FribbMappingRow(tvdbId: 81797, malId: 466, tvdbSeason: 0, type: 'OVA'),
          FribbMappingRow(tvdbId: 81797, malId: 492, tvdbSeason: 0, type: 'SPECIAL'),
        ],
      );

      final ids = await resolver.resolveShowForEpisode(_episode());

      expect(ids?.anime?.mal, 21);
      expect(ids?.animeProgressScope, AnimeProgressScope.show);
      expect(ids?.animeProgress, 1061);
      expect(animeProgress.resolveCalls, 1);
      expect(animeProgress.lastScope, AnimeProgressScope.show);
    });

    test('clearCache clears ID and anime progress caches', () async {
      final animeProgress = _FakeAnimeProgressLookup(1061);
      final lookup = _FakeFribbLookup(const [FribbMappingRow(tvdbId: 81797, malId: 21, type: 'TV')]);
      final resolver = _resolver(rows: lookup.rows, lookup: lookup, animeProgress: animeProgress);

      await resolver.resolveShowForEpisode(_episode());
      resolver.clearCache();
      await resolver.resolveShowForEpisode(_episode(number: 7));

      expect(lookup.lookups, 2);
      expect(animeProgress.clearCalls, 1);
      expect(animeProgress.resolveCalls, 2);
    });
  });
}
