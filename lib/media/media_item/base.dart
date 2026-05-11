part of '../media_item.dart';

/// Backend-neutral media item — the central domain type the app's UI,
/// providers, and persistence layer operate on. Each backend's adapter is
/// responsible for mapping its native representation (Plex `Metadata`,
/// Jellyfin `BaseItemDto`) into this shape.
///
/// Sealed root with two concrete subclasses: [PlexMediaItem] (carries
/// Plex-only fields like `trailerKey`, `playQueueItemId`, `audienceRating`)
/// and [JellyfinMediaItem] (only the backend-neutral fields). Read sites
/// that need a Plex-only field type-narrow with
/// `case PlexMediaItem(:final trailerKey?)` or
/// `if (item is PlexMediaItem) item.trailerKey`.
sealed class MediaItem {
  /// Backend-opaque identifier (Plex `ratingKey`, Jellyfin `Id`).
  final String id;
  final MediaBackend backend;
  final MediaKind kind;

  /// Stable cross-backend identifier (Plex `guid`, Jellyfin `Id` URI). Used
  /// for matching across servers and for Trakt-style external lookups.
  final String? guid;

  final String? title;
  final String? titleSort;
  final String? summary;
  final String? tagline;
  final String? originalTitle;
  final String? studio;
  final int? year;

  /// Original release date (`YYYY-MM-DD`).
  final String? originallyAvailableAt;
  final String? contentRating;

  final String? parentId;
  final String? parentTitle;
  final String? parentThumbPath;
  final int? parentIndex;
  final int? index;
  final String? grandparentId;
  final String? grandparentTitle;
  final String? grandparentThumbPath;
  final String? grandparentArtPath;

  final String? thumbPath;
  final String? artPath;
  final String? clearLogoPath;
  final String? backgroundSquarePath;

  final int? durationMs;

  /// Resume position in ms.
  final int? viewOffsetMs;
  final int? viewCount;
  final int? lastViewedAt;

  /// Total leaf items (episodes in a show/season, items in a collection).
  final int? leafCount;

  /// Watched leaf items.
  final int? viewedLeafCount;

  /// Direct children count (e.g. seasons in a show).
  final int? childCount;

  final int? addedAt;
  final int? updatedAt;

  final double? rating;
  final double? userRating;

  final List<String>? genres;
  final List<String>? directors;
  final List<String>? writers;
  final List<String>? producers;
  final List<String>? countries;
  final List<String>? collections;
  final List<String>? labels;
  final List<String>? styles;
  final List<String>? moods;
  final List<MediaRole>? roles;

  final List<MediaVersion>? mediaVersions;

  /// Backend-opaque library/section id this item belongs to.
  final String? libraryId;
  final String? libraryTitle;

  /// Preferred audio language for this item — used by track-selection
  /// fallback (Priority 3) on both backends. Plex persists changes via
  /// [PlexClient.setMetadataPreferences]; Jellyfin populates it from the
  /// per-user `PreferredMetadataLanguage` field but has no per-item write
  /// endpoint, so the value is read-only there.
  final String? audioLanguage;

  final String? serverId;
  final String? serverName;

  /// Untyped fall-through for backend-specific fields not yet mapped onto a
  /// typed accessor. Use sparingly; promote to typed fields when stable.
  final Map<String, Object?>? raw;

  const MediaItem._({
    required this.id,
    required this.backend,
    required this.kind,
    this.guid,
    this.title,
    this.titleSort,
    this.summary,
    this.tagline,
    this.originalTitle,
    this.studio,
    this.year,
    this.originallyAvailableAt,
    this.contentRating,
    this.parentId,
    this.parentTitle,
    this.parentThumbPath,
    this.parentIndex,
    this.index,
    this.grandparentId,
    this.grandparentTitle,
    this.grandparentThumbPath,
    this.grandparentArtPath,
    this.thumbPath,
    this.artPath,
    this.clearLogoPath,
    this.backgroundSquarePath,
    this.durationMs,
    this.viewOffsetMs,
    this.viewCount,
    this.lastViewedAt,
    this.leafCount,
    this.viewedLeafCount,
    this.childCount,
    this.addedAt,
    this.updatedAt,
    this.rating,
    this.userRating,
    this.genres,
    this.directors,
    this.writers,
    this.producers,
    this.countries,
    this.collections,
    this.labels,
    this.styles,
    this.moods,
    this.roles,
    this.mediaVersions,
    this.libraryId,
    this.libraryTitle,
    this.audioLanguage,
    this.serverId,
    this.serverName,
    this.raw,
  });

  /// Backend-dispatching factory: constructs the right concrete subclass
  /// for the given [backend].
  factory MediaItem({
    required String id,
    required MediaBackend backend,
    required MediaKind kind,
    String? guid,
    String? title,
    String? titleSort,
    String? summary,
    String? tagline,
    String? originalTitle,
    String? studio,
    int? year,
    String? originallyAvailableAt,
    String? contentRating,
    String? parentId,
    String? parentTitle,
    String? parentThumbPath,
    int? parentIndex,
    int? index,
    String? grandparentId,
    String? grandparentTitle,
    String? grandparentThumbPath,
    String? grandparentArtPath,
    String? thumbPath,
    String? artPath,
    String? clearLogoPath,
    String? backgroundSquarePath,
    int? durationMs,
    int? viewOffsetMs,
    int? viewCount,
    int? lastViewedAt,
    int? leafCount,
    int? viewedLeafCount,
    int? childCount,
    int? addedAt,
    int? updatedAt,
    double? rating,
    double? userRating,
    List<String>? genres,
    List<String>? directors,
    List<String>? writers,
    List<String>? producers,
    List<String>? countries,
    List<String>? collections,
    List<String>? labels,
    List<String>? styles,
    List<String>? moods,
    List<MediaRole>? roles,
    List<MediaVersion>? mediaVersions,
    String? libraryId,
    String? libraryTitle,
    String? audioLanguage,

    /// Plex-only — silently ignored when [backend] is Jellyfin (Jellyfin has
    /// no per-item subtitle preference write endpoint). Forwarded to
    /// [PlexMediaItem] only.
    String? subtitleLanguage,
    int? subtitleMode,
    String? serverId,
    String? serverName,
    Map<String, Object?>? raw,
  }) {
    return switch (backend) {
      MediaBackend.plex => PlexMediaItem(
        id: id,
        kind: kind,
        guid: guid,
        title: title,
        titleSort: titleSort,
        summary: summary,
        tagline: tagline,
        originalTitle: originalTitle,
        studio: studio,
        year: year,
        originallyAvailableAt: originallyAvailableAt,
        contentRating: contentRating,
        parentId: parentId,
        parentTitle: parentTitle,
        parentThumbPath: parentThumbPath,
        parentIndex: parentIndex,
        index: index,
        grandparentId: grandparentId,
        grandparentTitle: grandparentTitle,
        grandparentThumbPath: grandparentThumbPath,
        grandparentArtPath: grandparentArtPath,
        thumbPath: thumbPath,
        artPath: artPath,
        clearLogoPath: clearLogoPath,
        backgroundSquarePath: backgroundSquarePath,
        durationMs: durationMs,
        viewOffsetMs: viewOffsetMs,
        viewCount: viewCount,
        lastViewedAt: lastViewedAt,
        leafCount: leafCount,
        viewedLeafCount: viewedLeafCount,
        childCount: childCount,
        addedAt: addedAt,
        updatedAt: updatedAt,
        rating: rating,
        userRating: userRating,
        genres: genres,
        directors: directors,
        writers: writers,
        producers: producers,
        countries: countries,
        collections: collections,
        labels: labels,
        styles: styles,
        moods: moods,
        roles: roles,
        mediaVersions: mediaVersions,
        libraryId: libraryId,
        libraryTitle: libraryTitle,
        audioLanguage: audioLanguage,
        subtitleLanguage: subtitleLanguage,
        subtitleMode: subtitleMode,
        serverId: serverId,
        serverName: serverName,
        raw: raw,
      ),
      MediaBackend.jellyfin => JellyfinMediaItem(
        id: id,
        kind: kind,
        guid: guid,
        title: title,
        titleSort: titleSort,
        summary: summary,
        tagline: tagline,
        originalTitle: originalTitle,
        studio: studio,
        year: year,
        originallyAvailableAt: originallyAvailableAt,
        contentRating: contentRating,
        parentId: parentId,
        parentTitle: parentTitle,
        parentThumbPath: parentThumbPath,
        parentIndex: parentIndex,
        index: index,
        grandparentId: grandparentId,
        grandparentTitle: grandparentTitle,
        grandparentThumbPath: grandparentThumbPath,
        grandparentArtPath: grandparentArtPath,
        thumbPath: thumbPath,
        artPath: artPath,
        clearLogoPath: clearLogoPath,
        backgroundSquarePath: backgroundSquarePath,
        durationMs: durationMs,
        viewOffsetMs: viewOffsetMs,
        viewCount: viewCount,
        lastViewedAt: lastViewedAt,
        leafCount: leafCount,
        viewedLeafCount: viewedLeafCount,
        childCount: childCount,
        addedAt: addedAt,
        updatedAt: updatedAt,
        rating: rating,
        userRating: userRating,
        genres: genres,
        directors: directors,
        writers: writers,
        producers: producers,
        countries: countries,
        collections: collections,
        labels: labels,
        styles: styles,
        moods: moods,
        roles: roles,
        mediaVersions: mediaVersions,
        libraryId: libraryId,
        libraryTitle: libraryTitle,
        audioLanguage: audioLanguage,
        serverId: serverId,
        serverName: serverName,
        raw: raw,
      ),
    };
  }

  /// Global unique identifier across all servers (`serverId:id`). Falls back
  /// to bare [id] if [serverId] is missing.
  String get globalKey => serverId != null ? buildGlobalKey(serverId!, id) : id;

  /// Global unique identifier of this item's library section.
  String? get libraryGlobalKey => serverId != null && libraryId != null ? buildGlobalKey(serverId!, libraryId!) : null;

  /// Parent rating keys for hierarchical invalidation. For an episode:
  /// `[seasonId, showId]`. For a season: `[showId]`. For a movie: `[]`.
  List<String> get parentChain => [?parentId, ?grandparentId];

  /// Whether this item has started but not finished playback.
  bool get hasActiveProgress {
    if (durationMs == null || viewOffsetMs == null) return false;
    return viewOffsetMs! > 0 && viewOffsetMs! < durationMs!;
  }

  /// Whether this container (show/season) has some but not all leaves watched.
  bool get isPartiallyWatched =>
      viewedLeafCount != null && leafCount != null && viewedLeafCount! > 0 && viewedLeafCount! < leafCount!;

  /// Whether the item is fully watched. Series/seasons consult leaf counts;
  /// individual movies/episodes use [viewCount].
  bool get isWatched {
    if (leafCount != null && viewedLeafCount != null) {
      return viewedLeafCount! >= leafCount!;
    }
    return viewCount != null && viewCount! > 0;
  }

  /// Display-friendly title that prefers the show name for episodes/seasons.
  String get displayTitle {
    if ((kind == MediaKind.episode || kind == MediaKind.season) && grandparentTitle != null) {
      return grandparentTitle!;
    }
    if (kind == MediaKind.season && parentTitle != null) {
      return parentTitle!;
    }
    return title ?? '';
  }

  /// Subtitle line shown below [displayTitle] for episodes/seasons.
  String? get displaySubtitle {
    if (kind == MediaKind.episode || kind == MediaKind.season) {
      if (grandparentTitle != null || (kind == MediaKind.season && parentTitle != null)) {
        return title;
      }
    }
    return null;
  }

  /// Plex-only edition label (e.g. "Director's Cut"). Returns null on
  /// backends that don't model editions; lets callers avoid type-narrowing
  /// to [PlexMediaItem] just to read this field.
  String? get editionTitle => null;

  /// Returns the appropriate poster path based on episode poster mode.
  ///
  /// For episodes:
  /// - `seriesPoster`: grandparentThumb (series poster)
  /// - `seasonPoster`: parentThumb (season poster)
  /// - `episodeThumbnail`: thumb (16:9 episode still)
  ///
  /// For seasons: returns grandparentThumb (series poster), or art/thumb in
  /// mixed hub context.
  /// For movies/shows in mixed hub context with episode-thumbnail mode:
  /// returns art (16:9 background).
  /// For other types: returns thumb.
  String? posterThumb({EpisodePosterMode mode = EpisodePosterMode.seriesPoster, bool mixedHubContext = false}) {
    if (kind == MediaKind.episode) {
      switch (mode) {
        case EpisodePosterMode.episodeThumbnail:
          return thumbPath;
        case EpisodePosterMode.seasonPoster:
          return parentThumbPath ?? grandparentThumbPath ?? thumbPath;
        case EpisodePosterMode.seriesPoster:
          return grandparentThumbPath ?? thumbPath;
      }
    } else if (kind == MediaKind.season) {
      if (mixedHubContext && mode == EpisodePosterMode.episodeThumbnail) {
        return artPath ?? thumbPath;
      }
      if (grandparentThumbPath != null) {
        return grandparentThumbPath;
      }
    }

    if (mixedHubContext &&
        mode == EpisodePosterMode.episodeThumbnail &&
        (kind == MediaKind.movie || kind == MediaKind.show)) {
      return artPath ?? thumbPath;
    }

    return thumbPath;
  }

  /// Secondary poster path to try when [posterThumb] returns an image URL that
  /// exists syntactically but the server cannot serve it.
  String? posterThumbFallback({EpisodePosterMode mode = EpisodePosterMode.seriesPoster, bool mixedHubContext = false}) {
    if (kind != MediaKind.episode || mode != EpisodePosterMode.seasonPoster) return null;
    final fallback = grandparentThumbPath ?? thumbPath;
    return fallback != null && fallback != posterThumb(mode: mode, mixedHubContext: mixedHubContext) ? fallback : null;
  }

  /// True when the item should render in 16:9.
  /// - Clips are always 16:9.
  /// - Episodes are 16:9 in `episodeThumbnail` mode.
  /// - Movies/shows/seasons are 16:9 in mixed-hub `episodeThumbnail` context.
  bool usesWideAspectRatio(EpisodePosterMode mode, {bool mixedHubContext = false}) {
    if (kind == MediaKind.clip) return true;
    if (kind == MediaKind.episode && mode == EpisodePosterMode.episodeThumbnail) {
      return true;
    }
    if (mixedHubContext &&
        mode == EpisodePosterMode.episodeThumbnail &&
        (kind == MediaKind.movie || kind == MediaKind.show || kind == MediaKind.season)) {
      return true;
    }
    return false;
  }

  /// Returns the best hero art path based on the container's aspect ratio.
  /// Uses backgroundSquare when the container is closer to 1:1 than 16:9.
  String? heroArt({required double containerAspectRatio}) {
    final candidates = heroArtCandidates(containerAspectRatio: containerAspectRatio);
    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  /// Returns hero art candidates in display-preference order.
  /// Near-square containers prefer square art, then fall back to wide cover art.
  List<String> heroArtCandidates({required double containerAspectRatio}) {
    // Threshold = midpoint of 1:1 (1.0) and 16:9 (~1.78) ≈ 1.39
    final preferred = containerAspectRatio < 1.39 ? [backgroundSquarePath, artPath] : [artPath, backgroundSquarePath];

    final candidates = <String>[];
    for (final path in preferred) {
      if (path == null || path.isEmpty || candidates.contains(path)) continue;
      candidates.add(path);
    }
    return candidates;
  }

  MediaItem copyWith({
    String? id,
    MediaBackend? backend,
    MediaKind? kind,
    String? guid,
    String? title,
    String? titleSort,
    String? summary,
    String? tagline,
    String? originalTitle,
    String? studio,
    int? year,
    String? originallyAvailableAt,
    String? contentRating,
    String? parentId,
    String? parentTitle,
    String? parentThumbPath,
    int? parentIndex,
    int? index,
    String? grandparentId,
    String? grandparentTitle,
    String? grandparentThumbPath,
    String? grandparentArtPath,
    String? thumbPath,
    String? artPath,
    String? clearLogoPath,
    String? backgroundSquarePath,
    int? durationMs,
    int? viewOffsetMs,
    int? viewCount,
    int? lastViewedAt,
    int? leafCount,
    int? viewedLeafCount,
    int? childCount,
    int? addedAt,
    int? updatedAt,
    double? rating,
    double? userRating,
    List<String>? genres,
    List<String>? directors,
    List<String>? writers,
    List<String>? producers,
    List<String>? countries,
    List<String>? collections,
    List<String>? labels,
    List<String>? styles,
    List<String>? moods,
    List<MediaRole>? roles,
    List<MediaVersion>? mediaVersions,
    String? libraryId,
    String? libraryTitle,
    String? audioLanguage,

    /// Plex-only — forwarded only when this item is a [PlexMediaItem].
    String? subtitleLanguage,
    int? subtitleMode,
    String? serverId,
    String? serverName,
    Map<String, Object?>? raw,
  }) {
    return MediaItem(
      id: id ?? this.id,
      backend: backend ?? this.backend,
      kind: kind ?? this.kind,
      guid: guid ?? this.guid,
      title: title ?? this.title,
      titleSort: titleSort ?? this.titleSort,
      summary: summary ?? this.summary,
      tagline: tagline ?? this.tagline,
      originalTitle: originalTitle ?? this.originalTitle,
      studio: studio ?? this.studio,
      year: year ?? this.year,
      originallyAvailableAt: originallyAvailableAt ?? this.originallyAvailableAt,
      contentRating: contentRating ?? this.contentRating,
      parentId: parentId ?? this.parentId,
      parentTitle: parentTitle ?? this.parentTitle,
      parentThumbPath: parentThumbPath ?? this.parentThumbPath,
      parentIndex: parentIndex ?? this.parentIndex,
      index: index ?? this.index,
      grandparentId: grandparentId ?? this.grandparentId,
      grandparentTitle: grandparentTitle ?? this.grandparentTitle,
      grandparentThumbPath: grandparentThumbPath ?? this.grandparentThumbPath,
      grandparentArtPath: grandparentArtPath ?? this.grandparentArtPath,
      thumbPath: thumbPath ?? this.thumbPath,
      artPath: artPath ?? this.artPath,
      clearLogoPath: clearLogoPath ?? this.clearLogoPath,
      backgroundSquarePath: backgroundSquarePath ?? this.backgroundSquarePath,
      durationMs: durationMs ?? this.durationMs,
      viewOffsetMs: viewOffsetMs ?? this.viewOffsetMs,
      viewCount: viewCount ?? this.viewCount,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
      leafCount: leafCount ?? this.leafCount,
      viewedLeafCount: viewedLeafCount ?? this.viewedLeafCount,
      childCount: childCount ?? this.childCount,
      addedAt: addedAt ?? this.addedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rating: rating ?? this.rating,
      userRating: userRating ?? this.userRating,
      genres: genres ?? this.genres,
      directors: directors ?? this.directors,
      writers: writers ?? this.writers,
      producers: producers ?? this.producers,
      countries: countries ?? this.countries,
      collections: collections ?? this.collections,
      labels: labels ?? this.labels,
      styles: styles ?? this.styles,
      moods: moods ?? this.moods,
      roles: roles ?? this.roles,
      mediaVersions: mediaVersions ?? this.mediaVersions,
      libraryId: libraryId ?? this.libraryId,
      libraryTitle: libraryTitle ?? this.libraryTitle,
      audioLanguage: audioLanguage ?? this.audioLanguage,
      // [subtitleLanguage] / [subtitleMode] are Plex-only fields. Base
      // [MediaItem] doesn't carry them; [PlexMediaItem.copyWith] overrides
      // this method and forwards its own copies. For Jellyfin items the
      // params are silently dropped.
      subtitleLanguage: subtitleLanguage,
      subtitleMode: subtitleMode,
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      raw: raw ?? this.raw,
    );
  }

  /// Serialize to a backend-neutral JSON map. Used by the offline cache so
  /// downloads retain their metadata without round-tripping through a
  /// backend-specific shape.
  ///
  /// Subclasses extend this with their own backend-specific keys
  /// ([PlexMediaItem.toJson] adds the Plex-only fields).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'backend': backend.id,
      'kind': kind.id,
      if (guid != null) 'guid': guid,
      if (title != null) 'title': title,
      if (titleSort != null) 'titleSort': titleSort,
      if (summary != null) 'summary': summary,
      if (tagline != null) 'tagline': tagline,
      if (originalTitle != null) 'originalTitle': originalTitle,
      if (studio != null) 'studio': studio,
      if (year != null) 'year': year,
      if (originallyAvailableAt != null) 'originallyAvailableAt': originallyAvailableAt,
      if (contentRating != null) 'contentRating': contentRating,
      if (parentId != null) 'parentId': parentId,
      if (parentTitle != null) 'parentTitle': parentTitle,
      if (parentThumbPath != null) 'parentThumbPath': parentThumbPath,
      if (parentIndex != null) 'parentIndex': parentIndex,
      if (index != null) 'index': index,
      if (grandparentId != null) 'grandparentId': grandparentId,
      if (grandparentTitle != null) 'grandparentTitle': grandparentTitle,
      if (grandparentThumbPath != null) 'grandparentThumbPath': grandparentThumbPath,
      if (grandparentArtPath != null) 'grandparentArtPath': grandparentArtPath,
      if (thumbPath != null) 'thumbPath': thumbPath,
      if (artPath != null) 'artPath': artPath,
      if (clearLogoPath != null) 'clearLogoPath': clearLogoPath,
      if (backgroundSquarePath != null) 'backgroundSquarePath': backgroundSquarePath,
      if (durationMs != null) 'durationMs': durationMs,
      if (viewOffsetMs != null) 'viewOffsetMs': viewOffsetMs,
      if (viewCount != null) 'viewCount': viewCount,
      if (lastViewedAt != null) 'lastViewedAt': lastViewedAt,
      if (leafCount != null) 'leafCount': leafCount,
      if (viewedLeafCount != null) 'viewedLeafCount': viewedLeafCount,
      if (childCount != null) 'childCount': childCount,
      if (addedAt != null) 'addedAt': addedAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (rating != null) 'rating': rating,
      if (userRating != null) 'userRating': userRating,
      if (genres != null) 'genres': genres,
      if (directors != null) 'directors': directors,
      if (writers != null) 'writers': writers,
      if (producers != null) 'producers': producers,
      if (countries != null) 'countries': countries,
      if (collections != null) 'collections': collections,
      if (labels != null) 'labels': labels,
      if (styles != null) 'styles': styles,
      if (moods != null) 'moods': moods,
      if (roles != null) 'roles': [for (final r in roles!) _roleToJson(r)],
      if (mediaVersions != null) 'mediaVersions': [for (final v in mediaVersions!) _versionToJson(v)],
      if (libraryId != null) 'libraryId': libraryId,
      if (libraryTitle != null) 'libraryTitle': libraryTitle,
      if (audioLanguage != null) 'audioLanguage': audioLanguage,
      if (serverId != null) 'serverId': serverId,
      if (serverName != null) 'serverName': serverName,
      if (raw != null) 'raw': raw,
    };
  }

  /// Restore a [MediaItem] from a [toJson] payload. Dispatches to
  /// [PlexMediaItem.fromJson] when the payload's `backend` tag is Plex so
  /// the Plex-only fields round-trip correctly. Unknown shapes degrade to a
  /// minimal item carrying just `id` so cache misses don't crash.
  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final backend = MediaBackend.fromString(json['backend'] as String?);
    if (backend == MediaBackend.plex) return PlexMediaItem.fromJson(json);
    return JellyfinMediaItem.fromJson(json);
  }
}
