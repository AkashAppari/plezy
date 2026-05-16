import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_server_client.dart';
import '../../models/trackers/anime_ids.dart';
import '../../models/trackers/fribb_mapping_row.dart';
import '../../utils/external_ids.dart';
import 'anime_episode_progress_resolver.dart';
import 'fribb_mapping_store.dart';

/// Paired ID output: always-present Plex external IDs (tvdb/imdb/tmdb) plus
/// optional Fribb-sourced anime IDs (mal/anilist/simkl). Simkl uses [external]
/// directly for non-anime titles; MAL/AniList no-op when [anime] is null.
class TrackerIds {
  final ExternalIds external;
  final AnimeIds? anime;
  final AnimeProgressScope? animeProgressScope;
  final int? animeProgress;

  const TrackerIds({required this.external, required this.anime, this.animeProgressScope, this.animeProgress});

  TrackerIds withAnimeProgress(ResolvedAnimeProgress? animeProgress) {
    return TrackerIds(
      external: external,
      anime: anime,
      animeProgressScope: animeProgressScope,
      animeProgress: animeProgress?.progress,
    );
  }
}

/// Resolved IDs for manually rating a media item on external trackers.
///
/// For TV items, [ids.external] is the show-level ID set. Trakt can then rate
/// the show/season/episode through nested season/episode numbers, while MAL,
/// AniList, and Simkl rate the mapped anime/show entry itself.
class TrackerRatingContext {
  final TrackerIds ids;
  final MediaKind kind;
  final int? season;
  final int? episodeNumber;

  const TrackerRatingContext({required this.ids, required this.kind, this.season, this.episodeNumber});

  bool get isMovie => kind == MediaKind.movie;
}

/// Resolves item ids → tracker external IDs. Returns both backend-native
/// external IDs (used by Trakt and by Simkl for non-anime matches) and Fribb
/// anime IDs (used by MAL/AniList, and by Simkl for anime precision).
/// Episodes resolve against the show's GUIDs because Fribb only maps
/// show-level external IDs; split-cour disambiguation uses the season
/// number.
///
/// The Fribb lookup is skipped when [needsFribb] returns false — set this way
/// for Trakt (which never uses anime IDs) and for a Simkl-only configuration,
/// so those users don't pay the 5.6 MB mapping download they'll never need.
class TrackerIdResolver {
  final MediaServerClient _client;
  final FribbMappingLookup _store;
  final AnimeEpisodeProgressLookup _animeProgress;
  final bool Function() _needsFribb;

  /// Null entries mean "the server had no IDs" — cached so scrubbing on an
  /// un-matched item doesn't re-hit the server every position update.
  final Map<String, TrackerIds?> _cache = {};

  TrackerIdResolver(
    MediaServerClient client, {
    bool Function()? needsFribb,
    FribbMappingLookup? store,
    AnimeEpisodeProgressLookup? animeProgress,
  }) : _client = client,
       _needsFribb = needsFribb ?? _returnTrue,
       _store = store ?? FribbMappingStore.instance,
       _animeProgress = animeProgress ?? AnimeEpisodeProgressResolver(client);

  static bool _returnTrue() => true;

  /// Fetch external IDs for an item via the neutral
  /// [MediaServerClient.fetchExternalIds] surface — Plex hits
  /// `/library/metadata/{id}?includeGuids=1`, Jellyfin reads the inline
  /// `ProviderIds` map.
  Future<ExternalIds> _fetchExternalIds(String itemId) => _client.fetchExternalIds(itemId);

  /// Resolve IDs for a movie.
  Future<TrackerIds?> resolveForMovie(String itemId) async {
    if (_cache.containsKey(itemId)) return _cache[itemId];

    final external = await _fetchExternalIds(itemId);
    final ids = await _build(external, isEpisodeSeason: null, isMovie: true);
    _cache[itemId] = ids;
    return ids;
  }

  /// Resolve IDs for an episode. Looks up the *show's* external IDs (via
  /// `grandparentId`), then disambiguates among candidate Fribb rows using
  /// the episode's season number.
  Future<TrackerIds?> resolveShowForEpisode(MediaItem episode) async {
    final showId = episode.grandparentId;
    if (showId == null || showId.isEmpty) return null;

    final season = episode.parentIndex;
    // Cache under the (showId, season) pair so a show with multiple Fribb
    // rows caches each season separately during a marathon.
    final cacheKey = season != null ? '$showId#s$season' : showId;
    TrackerIds? ids;
    if (_cache.containsKey(cacheKey)) {
      ids = _cache[cacheKey];
    } else {
      final external = await _fetchExternalIds(showId);
      ids = await _build(external, isEpisodeSeason: season, isMovie: false);
      _cache[cacheKey] = ids;
    }

    if (ids == null || ids.animeProgressScope == null) return ids;
    final progress = await _animeProgress.resolve(episode, scope: ids.animeProgressScope!);
    return ids.withAnimeProgress(progress);
  }

  /// Resolve IDs for manual tracker ratings. Ratings can be attached to a
  /// movie, show, season, or episode from the detail screen/context menu.
  Future<TrackerRatingContext?> resolveForRating(MediaItem item) async {
    switch (item.kind) {
      case MediaKind.movie:
        final ids = await resolveForMovie(item.id);
        return ids == null ? null : TrackerRatingContext(ids: ids, kind: MediaKind.movie);
      case MediaKind.show:
        final ids = await _resolveShow(item.id);
        return ids == null ? null : TrackerRatingContext(ids: ids, kind: MediaKind.show);
      case MediaKind.season:
        final showId = item.parentId;
        final season = item.index ?? item.parentIndex;
        if (showId == null || showId.isEmpty || season == null) return null;
        final ids = await _resolveShow(showId, season: season);
        return ids == null ? null : TrackerRatingContext(ids: ids, kind: MediaKind.season, season: season);
      case MediaKind.episode:
        final season = item.parentIndex;
        final number = item.index;
        if (season == null || number == null) return null;
        final ids = await resolveShowForEpisode(item);
        return ids == null
            ? null
            : TrackerRatingContext(ids: ids, kind: MediaKind.episode, season: season, episodeNumber: number);
      default:
        return null;
    }
  }

  Future<TrackerIds?> _resolveShow(String showId, {int? season}) async {
    if (showId.isEmpty) return null;
    final cacheKey = season != null ? '$showId#s$season' : showId;
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    final external = await _fetchExternalIds(showId);
    final ids = await _build(external, isEpisodeSeason: season, isMovie: false);
    _cache[cacheKey] = ids;
    return ids;
  }

  void clearCache() {
    _cache.clear();
    _animeProgress.clearCache();
  }

  Future<TrackerIds?> _build(ExternalIds external, {int? isEpisodeSeason, required bool isMovie}) async {
    if (!external.hasAny) return null;
    if (!_needsFribb()) return TrackerIds(external: external, anime: null);
    final rows = await _store.lookup(tvdbId: external.tvdb, tmdbId: external.tmdb, imdbId: external.imdb);
    final row = isMovie ? _pickMovieRow(rows) : _pickShowRow(rows, season: isEpisodeSeason);
    final anime = row == null ? null : AnimeIds.fromFribb(row);
    return TrackerIds(
      external: external,
      anime: anime,
      animeProgressScope: _animeProgressScope(selected: row, rows: rows, season: isEpisodeSeason, isMovie: isMovie),
    );
  }

  /// Pick the best row for a movie lookup — prefer rows marked `type: MOVIE`.
  FribbMappingRow? _pickMovieRow(List<FribbMappingRow> rows) {
    if (rows.isEmpty) return null;
    final movies = rows.where((r) => r.isMovie);
    if (movies.isNotEmpty) return movies.first;
    // Fall back to any row if no explicit MOVIE row matches — some rows have
    // no type field.
    return rows.first;
  }

  /// Pick the best row for a show lookup. When Fribb has multiple rows
  /// sharing the same show-level external ID (split-cour anime), prefer the
  /// one whose `season.tvdb` or `season.tmdb` matches the Plex episode's
  /// season; otherwise prefer regular TV/ONA rows.
  FribbMappingRow? _pickShowRow(List<FribbMappingRow> rows, {int? season}) {
    if (rows.isEmpty) return null;

    if (season != null) {
      for (final row in rows) {
        if (row.tvdbSeason == season || row.tmdbSeason == season) return row;
      }
    }

    // No season match — prefer regular TV/ONA rows over movies/OVAs/specials.
    for (final row in rows) {
      if (_isRegularSeriesRow(row)) return row;
    }

    // Fall back to the first non-MOVIE row (prefer series-like entries).
    for (final row in rows) {
      if (!row.isMovie) return row;
    }
    return rows.first;
  }

  AnimeProgressScope? _animeProgressScope({
    required FribbMappingRow? selected,
    required List<FribbMappingRow> rows,
    required int? season,
    required bool isMovie,
  }) {
    if (isMovie) return null;
    if (season == null || season <= 0) return null;
    if (selected == null) return null;
    if (_hasSeasonMapping(selected)) {
      final exactSeason = selected.tvdbSeason == season || selected.tmdbSeason == season;
      return exactSeason && _isRegularSeriesRow(selected) ? AnimeProgressScope.season : null;
    }

    final regularRows = rows.where(_isRegularSeriesRow).toList(growable: false);
    if (regularRows.length == 1 && identical(regularRows.single, selected)) {
      return AnimeProgressScope.show;
    }
    return null;
  }

  bool _hasSeasonMapping(FribbMappingRow row) => row.tvdbSeason != null || row.tmdbSeason != null;

  bool _isRegularSeriesRow(FribbMappingRow row) {
    if (row.isMovie) return false;
    if (row.tvdbSeason == 0 || row.tmdbSeason == 0) return false;

    return switch (row.type?.toUpperCase()) {
      null || 'TV' || 'ONA' || 'UNKNOWN' => true,
      _ => false,
    };
  }
}
