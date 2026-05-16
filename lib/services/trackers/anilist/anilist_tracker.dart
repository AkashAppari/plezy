import 'package:http/http.dart' as http;

import '../../../models/trackers/tracker_context.dart';
import '../../../utils/app_logger.dart';
import '../../settings_service.dart';
import '../tracker.dart';
import '../tracker_constants.dart';
import '../tracker_id_resolver.dart';
import 'anilist_client.dart';
import 'anilist_session.dart';

/// AniList scrobble tracker. Saves `SaveMediaListEntry(progress, status)`
/// once playback crosses the watched threshold.
///
/// AniList is anime-only: no-op when [TrackerContext.anime] is null.
class AnilistTracker extends TrackerBase {
  static AnilistTracker? _instance;
  static AnilistTracker get instance => _instance ??= AnilistTracker._();
  AnilistTracker._();

  @override
  String get name => 'anilist';

  @override
  TrackerService get service => TrackerService.anilist;

  @override
  bool get needsFribb => true;

  AnilistClient? _client;
  final Map<int, Future<int?>> _episodeCountLoads = {};

  @override
  bool get hasActiveClient => _client != null;

  @override
  bool readEnabledSetting(SettingsService settings) => settings.read(SettingsService.enableAnilistScrobble);

  void rebindSession(
    AnilistSession? session, {
    required void Function() onSessionInvalidated,
    http.Client? httpClient,
  }) {
    _client?.dispose();
    _episodeCountLoads.clear();
    _client = session == null
        ? null
        : AnilistClient(session, onSessionInvalidated: onSessionInvalidated, httpClient: httpClient);
  }

  @override
  Future<void> markWatched(TrackerContext ctx) async {
    final client = _client;
    final anilistId = ctx.anime?.anilist;
    if (client == null || anilistId == null) return;

    final progress = ctx.isMovie ? 1 : (ctx.animeProgress ?? ctx.episodeNumber);
    if (progress == null || progress <= 0) return;
    final total = ctx.isMovie || ctx.animeProgress == null ? null : await _episodeCount(client, anilistId);
    final watched = total != null && progress > total ? total : progress;
    final status = ctx.isMovie || (total != null && progress >= total) ? 'COMPLETED' : 'CURRENT';

    await client.saveMediaListEntry(mediaId: anilistId, progress: watched, status: status);
    appLogger.d('AniList: saved entry (anilist=$anilistId, progress=$watched, status=$status)');
  }

  Future<void> rate(TrackerRatingContext ctx, int score) async {
    final client = _client;
    final anilistId = ctx.ids.anime?.anilist;
    if (client == null || anilistId == null) throw const TrackerRatingUnavailableException('AniList');

    final clamped = score.clamp(1, 10).toInt();
    await client.setMediaListScore(mediaId: anilistId, score: clamped);
    appLogger.d('AniList: updated score (anilist=$anilistId, score=$clamped)');
  }

  Future<void> clearRating(TrackerRatingContext ctx) async {
    final client = _client;
    final anilistId = ctx.ids.anime?.anilist;
    if (client == null || anilistId == null) throw const TrackerRatingUnavailableException('AniList');

    await client.setMediaListScore(mediaId: anilistId, score: 0);
    appLogger.d('AniList: cleared score (anilist=$anilistId)');
  }

  Future<int?> getRating(TrackerRatingContext ctx) async {
    final client = _client;
    final anilistId = ctx.ids.anime?.anilist;
    if (client == null || anilistId == null) throw const TrackerRatingUnavailableException('AniList');
    return client.getMediaListScore(anilistId);
  }

  Future<int?> _episodeCount(AnilistClient client, int anilistId) {
    final existing = _episodeCountLoads[anilistId];
    if (existing != null) return existing;

    late final Future<int?> loading;
    loading = client.getAnimeEpisodeCount(anilistId).catchError((Object e) {
      if (identical(_episodeCountLoads[anilistId], loading)) {
        final _ = _episodeCountLoads.remove(anilistId);
      }
      appLogger.d('AniList: failed to fetch anime episode count (anilist=$anilistId)', error: e);
      return null;
    });
    _episodeCountLoads[anilistId] = loading;
    return loading;
  }
}
