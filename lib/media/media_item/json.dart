part of '../media_item.dart';

/// Shared parsing of the backend-neutral fields. Returns a typed record
/// consumed by both [JellyfinMediaItem.fromJson] and
/// [PlexMediaItem.fromJson] (which layers the Plex-only fields on top).
typedef _BaseFields = ({
  String id,
  MediaKind kind,
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
  String? serverId,
  String? serverName,
  Map<String, Object?>? raw,
});

_BaseFields _parseBaseFields(Map<String, dynamic> json) {
  final rolesRaw = json['roles'];
  final versionsRaw = json['mediaVersions'];
  return (
    id: (json['id'] ?? '').toString(),
    kind: MediaKind.fromString(json['kind'] as String?),
    guid: json['guid'] as String?,
    title: json['title'] as String?,
    titleSort: json['titleSort'] as String?,
    summary: json['summary'] as String?,
    tagline: json['tagline'] as String?,
    originalTitle: json['originalTitle'] as String?,
    studio: json['studio'] as String?,
    year: flexibleInt(json['year']),
    originallyAvailableAt: json['originallyAvailableAt'] as String?,
    contentRating: json['contentRating'] as String?,
    parentId: json['parentId'] as String?,
    parentTitle: json['parentTitle'] as String?,
    parentThumbPath: json['parentThumbPath'] as String?,
    parentIndex: flexibleInt(json['parentIndex']),
    index: flexibleInt(json['index']),
    grandparentId: json['grandparentId'] as String?,
    grandparentTitle: json['grandparentTitle'] as String?,
    grandparentThumbPath: json['grandparentThumbPath'] as String?,
    grandparentArtPath: json['grandparentArtPath'] as String?,
    thumbPath: json['thumbPath'] as String?,
    artPath: json['artPath'] as String?,
    clearLogoPath: json['clearLogoPath'] as String?,
    backgroundSquarePath: json['backgroundSquarePath'] as String?,
    durationMs: flexibleInt(json['durationMs']),
    viewOffsetMs: flexibleInt(json['viewOffsetMs']),
    viewCount: flexibleInt(json['viewCount']),
    lastViewedAt: flexibleInt(json['lastViewedAt']),
    leafCount: flexibleInt(json['leafCount']),
    viewedLeafCount: flexibleInt(json['viewedLeafCount']),
    childCount: flexibleInt(json['childCount']),
    addedAt: flexibleInt(json['addedAt']),
    updatedAt: flexibleInt(json['updatedAt']),
    rating: flexibleDouble(json['rating']),
    userRating: flexibleDouble(json['userRating']),
    genres: _stringList(json['genres']),
    directors: _stringList(json['directors']),
    writers: _stringList(json['writers']),
    producers: _stringList(json['producers']),
    countries: _stringList(json['countries']),
    collections: _stringList(json['collections']),
    labels: _stringList(json['labels']),
    styles: _stringList(json['styles']),
    moods: _stringList(json['moods']),
    roles: rolesRaw is List
        ? [
            for (final r in rolesRaw)
              if (r is Map<String, dynamic>) _roleFromJson(r),
          ]
        : null,
    mediaVersions: versionsRaw is List
        ? [
            for (final v in versionsRaw)
              if (v is Map<String, dynamic>) _versionFromJson(v),
          ]
        : null,
    libraryId: json['libraryId'] as String?,
    libraryTitle: json['libraryTitle'] as String?,
    audioLanguage: json['audioLanguage'] as String?,
    serverId: json['serverId'] as String?,
    serverName: json['serverName'] as String?,
    raw: json['raw'] is Map ? Map<String, Object?>.from(json['raw'] as Map) : null,
  );
}

List<String>? _stringList(Object? raw) {
  return stringListFromRaw(raw, stringify: true);
}

Map<String, dynamic> _roleToJson(MediaRole role) => {
  if (role.id != null) 'id': role.id,
  'tag': role.tag,
  if (role.role != null) 'role': role.role,
  if (role.thumbPath != null) 'thumbPath': role.thumbPath,
};

MediaRole _roleFromJson(Map<String, dynamic> json) => MediaRole(
  id: json['id'] as String?,
  tag: (json['tag'] ?? '').toString(),
  role: json['role'] as String?,
  thumbPath: json['thumbPath'] as String?,
);

Map<String, dynamic> _versionToJson(MediaVersion v) => {
  'id': v.id,
  if (v.width != null) 'width': v.width,
  if (v.height != null) 'height': v.height,
  if (v.videoResolution != null) 'videoResolution': v.videoResolution,
  if (v.videoCodec != null) 'videoCodec': v.videoCodec,
  if (v.bitrate != null) 'bitrate': v.bitrate,
  if (v.container != null) 'container': v.container,
  if (v.name != null) 'name': v.name,
  'parts': [
    for (final p in v.parts)
      {
        'id': p.id,
        if (p.streamPath != null) 'streamPath': p.streamPath,
        if (p.sizeBytes != null) 'sizeBytes': p.sizeBytes,
        if (p.container != null) 'container': p.container,
        if (p.durationMs != null) 'durationMs': p.durationMs,
        if (p.accessible != null) 'accessible': p.accessible,
        if (p.exists != null) 'exists': p.exists,
      },
  ],
};

MediaVersion _versionFromJson(Map<String, dynamic> json) {
  final partsRaw = json['parts'];
  return MediaVersion(
    id: (json['id'] ?? '').toString(),
    width: flexibleInt(json['width']),
    height: flexibleInt(json['height']),
    videoResolution: json['videoResolution'] as String?,
    videoCodec: json['videoCodec'] as String?,
    bitrate: flexibleInt(json['bitrate']),
    container: json['container'] as String?,
    name: json['name'] as String?,
    parts: partsRaw is List
        ? [
            for (final p in partsRaw)
              if (p is Map<String, dynamic>)
                MediaPart(
                  id: (p['id'] ?? '').toString(),
                  streamPath: p['streamPath'] as String?,
                  sizeBytes: flexibleInt(p['sizeBytes']),
                  container: p['container'] as String?,
                  durationMs: flexibleInt(p['durationMs']),
                  accessible: p['accessible'] as bool?,
                  exists: p['exists'] as bool?,
                ),
          ]
        : const [],
  );
}
