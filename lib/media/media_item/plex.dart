part of '../media_item.dart';

/// Backend-tagged concrete subclass for items sourced from a Plex server.
/// Carries the Plex-only fields that have no Jellyfin equivalent
/// (trailerKey, playlistItemId, playQueueItemId, subtype, extraType,
/// ratingImage, audienceRating, audienceRatingImage, editionTitle).
/// Read sites that need these fields type-narrow with
/// `case PlexMediaItem(:final trailerKey?)` or
/// `if (item is PlexMediaItem) item.trailerKey`.
final class PlexMediaItem extends MediaItem {
  /// Plex `editionTitle` — secondary title that distinguishes editions of
  /// the same movie ("Director's Cut", "Theatrical"). Jellyfin has no
  /// equivalent metadata field today.
  @override
  final String? editionTitle;

  /// Plex `audienceRating` (e.g. Rotten Tomatoes audience score). Jellyfin's
  /// `CommunityRating` lives on [rating]; there's no separate audience field.
  final double? audienceRating;

  /// Plex `ratingImage` URI ("rottentomatoes://image.rating.ripe"). Used by
  /// the rating chip to pick an icon. Jellyfin doesn't expose
  /// rating-source attribution.
  final String? ratingImage;

  /// Plex `audienceRatingImage` URI — companion to [ratingImage] for the
  /// audience score icon.
  final String? audienceRatingImage;

  /// Plex per-item subtitle language preference — persisted server-side via
  /// [PlexClient.setMetadataPreferences]. Jellyfin has no equivalent
  /// per-item write endpoint, so the field lives here rather than on the
  /// neutral [MediaItem] base.
  final String? subtitleLanguage;

  /// Plex per-item subtitle mode (`0` = manual, `1` = always on, `2` = match
  /// audio). Jellyfin doesn't expose a comparable knob.
  final int? subtitleMode;

  /// Plex `primaryExtraKey` — points at the main trailer extra. Jellyfin
  /// stores trailers separately via `RemoteTrailers`; not yet wired.
  final String? trailerKey;

  /// Plex playlist item id — only set when the item came out of a
  /// server-side playlist. Jellyfin has no per-playlist-item id.
  final int? playlistItemId;

  /// Plex play-queue item id — set when the item is part of a server-side
  /// `PlayQueue`. Jellyfin uses client-side queues; [PlaybackStateProvider]
  /// tracks synthetic IDs in a parallel map for those.
  final int? playQueueItemId;

  /// Plex clip subtype: `trailer`, `behindTheScenes`, `deleted`, etc.
  final String? subtype;

  /// Plex numeric extra type identifier.
  final int? extraType;

  const PlexMediaItem({
    required super.id,
    required super.kind,
    super.guid,
    super.title,
    super.titleSort,
    super.summary,
    super.tagline,
    super.originalTitle,
    this.editionTitle,
    super.studio,
    super.year,
    super.originallyAvailableAt,
    super.contentRating,
    super.parentId,
    super.parentTitle,
    super.parentThumbPath,
    super.parentIndex,
    super.index,
    super.grandparentId,
    super.grandparentTitle,
    super.grandparentThumbPath,
    super.grandparentArtPath,
    super.thumbPath,
    super.artPath,
    super.clearLogoPath,
    super.backgroundSquarePath,
    super.durationMs,
    super.viewOffsetMs,
    super.viewCount,
    super.lastViewedAt,
    super.leafCount,
    super.viewedLeafCount,
    super.childCount,
    super.addedAt,
    super.updatedAt,
    super.rating,
    this.audienceRating,
    super.userRating,
    this.ratingImage,
    this.audienceRatingImage,
    super.genres,
    super.directors,
    super.writers,
    super.producers,
    super.countries,
    super.collections,
    super.labels,
    super.styles,
    super.moods,
    super.roles,
    super.mediaVersions,
    super.libraryId,
    super.libraryTitle,
    super.audioLanguage,
    this.subtitleLanguage,
    this.subtitleMode,
    this.trailerKey,
    this.playlistItemId,
    this.playQueueItemId,
    this.subtype,
    this.extraType,
    super.serverId,
    super.serverName,
    super.raw,
  }) : super._(backend: MediaBackend.plex);

  @override
  PlexMediaItem copyWith({
    String? id,
    MediaBackend? backend,
    MediaKind? kind,
    String? guid,
    String? title,
    String? titleSort,
    String? summary,
    String? tagline,
    String? originalTitle,
    String? editionTitle,
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
    double? audienceRating,
    double? userRating,
    String? ratingImage,
    String? audienceRatingImage,
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
    String? subtitleLanguage,
    int? subtitleMode,
    String? trailerKey,
    int? playlistItemId,
    int? playQueueItemId,
    String? subtype,
    int? extraType,
    String? serverId,
    String? serverName,
    Map<String, Object?>? raw,
  }) {
    return PlexMediaItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      guid: guid ?? this.guid,
      title: title ?? this.title,
      titleSort: titleSort ?? this.titleSort,
      summary: summary ?? this.summary,
      tagline: tagline ?? this.tagline,
      originalTitle: originalTitle ?? this.originalTitle,
      editionTitle: editionTitle ?? this.editionTitle,
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
      audienceRating: audienceRating ?? this.audienceRating,
      userRating: userRating ?? this.userRating,
      ratingImage: ratingImage ?? this.ratingImage,
      audienceRatingImage: audienceRatingImage ?? this.audienceRatingImage,
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
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      subtitleMode: subtitleMode ?? this.subtitleMode,
      trailerKey: trailerKey ?? this.trailerKey,
      playlistItemId: playlistItemId ?? this.playlistItemId,
      playQueueItemId: playQueueItemId ?? this.playQueueItemId,
      subtype: subtype ?? this.subtype,
      extraType: extraType ?? this.extraType,
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      raw: raw ?? this.raw,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      if (editionTitle != null) 'editionTitle': editionTitle,
      if (audienceRating != null) 'audienceRating': audienceRating,
      if (ratingImage != null) 'ratingImage': ratingImage,
      if (audienceRatingImage != null) 'audienceRatingImage': audienceRatingImage,
      if (subtitleLanguage != null) 'subtitleLanguage': subtitleLanguage,
      if (subtitleMode != null) 'subtitleMode': subtitleMode,
      if (trailerKey != null) 'trailerKey': trailerKey,
      if (playlistItemId != null) 'playlistItemId': playlistItemId,
      if (playQueueItemId != null) 'playQueueItemId': playQueueItemId,
      if (subtype != null) 'subtype': subtype,
      if (extraType != null) 'extraType': extraType,
    };
  }

  /// Restore a [PlexMediaItem] from a [toJson] payload. Reads the Plex-only
  /// keys on top of the backend-neutral fields parsed by [_parseBaseFields].
  factory PlexMediaItem.fromJson(Map<String, dynamic> json) {
    final base = _parseBaseFields(json);
    return PlexMediaItem(
      id: base.id,
      kind: base.kind,
      guid: base.guid,
      title: base.title,
      titleSort: base.titleSort,
      summary: base.summary,
      tagline: base.tagline,
      originalTitle: base.originalTitle,
      editionTitle: json['editionTitle'] as String?,
      studio: base.studio,
      year: base.year,
      originallyAvailableAt: base.originallyAvailableAt,
      contentRating: base.contentRating,
      parentId: base.parentId,
      parentTitle: base.parentTitle,
      parentThumbPath: base.parentThumbPath,
      parentIndex: base.parentIndex,
      index: base.index,
      grandparentId: base.grandparentId,
      grandparentTitle: base.grandparentTitle,
      grandparentThumbPath: base.grandparentThumbPath,
      grandparentArtPath: base.grandparentArtPath,
      thumbPath: base.thumbPath,
      artPath: base.artPath,
      clearLogoPath: base.clearLogoPath,
      backgroundSquarePath: base.backgroundSquarePath,
      durationMs: base.durationMs,
      viewOffsetMs: base.viewOffsetMs,
      viewCount: base.viewCount,
      lastViewedAt: base.lastViewedAt,
      leafCount: base.leafCount,
      viewedLeafCount: base.viewedLeafCount,
      childCount: base.childCount,
      addedAt: base.addedAt,
      updatedAt: base.updatedAt,
      rating: base.rating,
      audienceRating: flexibleDouble(json['audienceRating']),
      userRating: base.userRating,
      ratingImage: json['ratingImage'] as String?,
      audienceRatingImage: json['audienceRatingImage'] as String?,
      genres: base.genres,
      directors: base.directors,
      writers: base.writers,
      producers: base.producers,
      countries: base.countries,
      collections: base.collections,
      labels: base.labels,
      styles: base.styles,
      moods: base.moods,
      roles: base.roles,
      mediaVersions: base.mediaVersions,
      libraryId: base.libraryId,
      libraryTitle: base.libraryTitle,
      audioLanguage: base.audioLanguage,
      subtitleLanguage: json['subtitleLanguage'] as String?,
      subtitleMode: flexibleInt(json['subtitleMode']),
      trailerKey: json['trailerKey'] as String?,
      playlistItemId: flexibleInt(json['playlistItemId']),
      playQueueItemId: flexibleInt(json['playQueueItemId']),
      subtype: json['subtype'] as String?,
      extraType: flexibleInt(json['extraType']),
      serverId: base.serverId,
      serverName: base.serverName,
      raw: base.raw,
    );
  }
}
