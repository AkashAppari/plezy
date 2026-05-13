import '../../../models/trackers/tracker_context.dart';
import '../../../utils/app_logger.dart';
import '../../settings_service.dart';
import '../tracker.dart';
import '../tracker_constants.dart';
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

  @override
  bool get hasActiveClient => _client != null;

  @override
  bool readEnabledSetting(SettingsService settings) => settings.read(SettingsService.enableMalScrobble);

  void rebindSession(
    MalSession? session, {
    required void Function() onSessionInvalidated,
    void Function(MalSession)? onSessionUpdated,
  }) {
    _client?.dispose();
    _client = session == null
        ? null
        : MalClient(session, onSessionInvalidated: onSessionInvalidated, onSessionUpdated: onSessionUpdated);
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
      fields = {'status': ctx.animeProgressComplete ? 'completed' : 'watching', 'num_watched_episodes': '$progress'};
    }

    await client.updateMyListStatus(malId, fields);
    appLogger.d('MAL: updated list status (mal=$malId, fields=$fields)');
  }
}
