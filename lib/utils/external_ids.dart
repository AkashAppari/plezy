/// External IDs (IMDb / TMDB / TVDB) extracted from a media server's
/// metadata. Shared by the Trakt and tracker resolvers.
///
/// - **Plex** stores them in a `Guid` array (`imdb://tt123`,
///   `tmdb://456`, `tvdb://789`) — fetched via
///   [PlexClient.fetchExternalGuids]. Use [ExternalIds.fromGuids].
/// - **Jellyfin** stores them inline as a `ProviderIds` map on every
///   `BaseItemDto`. Use [ExternalIds.fromJellyfinProviderIds].
class ExternalIds {
  final String? imdb;
  final int? tmdb;
  final int? tvdb;

  const ExternalIds({this.imdb, this.tmdb, this.tvdb});

  bool get hasAny => imdb != null || tmdb != null || tvdb != null;

  /// True when any id form matches [other]. Used to verify reverse-lookup
  /// candidates (never yields false positives; the two sides may carry
  /// different id subsets).
  bool intersects(ExternalIds other) =>
      (imdb != null && imdb == other.imdb) ||
      (tmdb != null && tmdb == other.tmdb) ||
      (tvdb != null && tvdb == other.tvdb);

  factory ExternalIds.fromGuids(List<dynamic> guids) {
    String? imdb;
    int? tmdb;
    int? tvdb;
    for (final g in guids) {
      if (g is! Map) continue;
      final id = g['id'];
      if (id is! String) continue;
      if (id.startsWith('imdb://')) {
        imdb = id.substring(7);
      } else if (id.startsWith('tmdb://')) {
        tmdb = int.tryParse(id.substring(7));
      } else if (id.startsWith('tvdb://')) {
        tvdb = int.tryParse(id.substring(7));
      }
    }
    return ExternalIds(imdb: imdb, tmdb: tmdb, tvdb: tvdb);
  }

  /// Pick the first raw Jellyfin item whose inline `ProviderIds` intersect
  /// [ids]. Pure helper so the reverse-lookup verification stays
  /// unit-testable (its call site lives in a part file).
  static Map<String, dynamic>? jellyfinCandidateMatching(List<Map<String, dynamic>> candidates, ExternalIds ids) {
    for (final item in candidates) {
      final providerIds = item['ProviderIds'];
      if (providerIds is! Map) continue;
      final candidate = ExternalIds.fromJellyfinProviderIds(providerIds.cast<String, Object?>());
      if (ids.intersects(candidate)) return item;
    }
    return null;
  }

  /// Build from a Jellyfin `ProviderIds` map. Jellyfin stores external IDs
  /// directly on every `BaseItemDto` so no extra fetch is needed.
  /// Keys are case-insensitive in practice (`Tmdb`, `Imdb`, `Tvdb`).
  factory ExternalIds.fromJellyfinProviderIds(Map<String, Object?> providerIds) {
    String? imdb;
    int? tmdb;
    int? tvdb;
    providerIds.forEach((key, value) {
      if (value is! String || value.isEmpty) return;
      switch (key.toLowerCase()) {
        case 'imdb':
          imdb = value;
          break;
        case 'tmdb':
          tmdb = int.tryParse(value);
          break;
        case 'tvdb':
          tvdb = int.tryParse(value);
          break;
      }
    });
    return ExternalIds(imdb: imdb, tmdb: tmdb, tvdb: tvdb);
  }
}
