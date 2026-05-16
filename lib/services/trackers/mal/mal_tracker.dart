import 'package:http/http.dart' as http;

import '../../../models/trackers/tracker_context.dart';
import '../../../utils/app_logger.dart';
import '../../settings_service.dart';
import '../tracker.dart';
import '../tracker_constants.dart';
import '../tracker_id_resolver.dart';
import 'mal_client.dart';
import 'mal_session.dart';

/// MyAnimeList scrobble tracker. Marks `num_watched_episodes` on the user's
/// list entry once playback crosses the watched threshold.
///
/// MAL is anime-only: no-op when [TrackerContext.anime] is null.
///
/// For anime episodes, MAL receives watched progress in the mapped anime entry
/// when Fribb can define that scope, otherwise local episode progress.
class MalTracker extends TrackerBase {
  static MalTracker? _instance;
  static MalTracker get instance => _instance ??= MalTracker._();
  MalTracker._();

  @override
  String get name => 'mal';

  @override
  TrackerService get service => TrackerService.mal;

  @override
  bool get needsFribb => true;

  MalClient? _client;
  final Map<int, Future<int?>> _episodeCountLoads = {};

  @override
  bool get hasActiveClient => _client != null;

  @override
  bool readEnabledSetting(SettingsService settings) => settings.read(SettingsService.enableMalScrobble);

  void rebindSession(
    MalSession? session, {
    required void Function() onSessionInvalidated,
    void Function(MalSession)? onSessionUpdated,
    http.Client? httpClient,
  }) {
    _client?.dispose();
    _episodeCountLoads.clear();
    _client = session == null
        ? null
        : MalClient(
            session,
            onSessionInvalidated: onSessionInvalidated,
            onSessionUpdated: onSessionUpdated,
            httpClient: httpClient,
          );
  }

  @override
  Future<void> markWatched(TrackerContext ctx) async {
    final client = _client;
    final malId = ctx.anime?.mal;
    if (client == null || malId == null) return;

    final Map<String, String> fields;
    if (ctx.isMovie) {
      fields = {'status': 'completed', 'num_watched_episodes': '1'};
    } else {
      final progress = ctx.animeProgress ?? ctx.episodeNumber;
      if (progress == null || progress <= 0) return;
      final total = ctx.animeProgress == null ? null : await _episodeCount(client, malId);
      final watched = total != null && progress > total ? total : progress;
      fields = {
        'status': total != null && progress >= total ? 'completed' : 'watching',
        'num_watched_episodes': '$watched',
      };
    }

    await client.updateMyListStatus(malId, fields);
    appLogger.d('MAL: updated list status (mal=$malId, fields=$fields)');
  }

  Future<void> rate(TrackerRatingContext ctx, int score) async {
    final client = _client;
    final malId = ctx.ids.anime?.mal;
    if (client == null || malId == null) throw const TrackerRatingUnavailableException('MAL');

    final clamped = score.clamp(1, 10).toInt();
    await client.updateMyListStatus(malId, {'score': '$clamped'});
    appLogger.d('MAL: updated score (mal=$malId, score=$clamped)');
  }

  Future<void> clearRating(TrackerRatingContext ctx) async {
    final client = _client;
    final malId = ctx.ids.anime?.mal;
    if (client == null || malId == null) throw const TrackerRatingUnavailableException('MAL');

    await client.updateMyListStatus(malId, {'score': '0'});
    appLogger.d('MAL: cleared score (mal=$malId)');
  }

  Future<int?> getRating(TrackerRatingContext ctx) async {
    final client = _client;
    final malId = ctx.ids.anime?.mal;
    if (client == null || malId == null) throw const TrackerRatingUnavailableException('MAL');
    return client.getMyListScore(malId);
  }

  Future<int?> _episodeCount(MalClient client, int malId) {
    final existing = _episodeCountLoads[malId];
    if (existing != null) return existing;

    late final Future<int?> loading;
    loading = client.getAnimeEpisodeCount(malId).catchError((Object e) {
      if (identical(_episodeCountLoads[malId], loading)) {
        final _ = _episodeCountLoads.remove(malId);
      }
      appLogger.d('MAL: failed to fetch anime episode count (mal=$malId)', error: e);
      return null;
    });
    _episodeCountLoads[malId] = loading;
    return loading;
  }
}
