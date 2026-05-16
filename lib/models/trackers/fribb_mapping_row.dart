// ignore_for_file: invalid_annotation_target
import 'package:json_annotation/json_annotation.dart';

import '../../utils/json_utils.dart';

part 'fribb_mapping_row.g.dart';

Object? _readTvdbSeason(Map json, String key) {
  final season = json['season'];
  return season is Map ? season['tvdb'] : null;
}

Object? _readTmdbSeason(Map json, String key) {
  final season = json['season'];
  return season is Map ? season['tmdb'] : null;
}

/// One row from `anime-list-mini.json` (Fribb/anime-lists).
@JsonSerializable(createToJson: false)
class FribbMappingRow {
  @JsonKey(name: 'anidb_id', fromJson: flexibleInt)
  final int? anidbId;
  @JsonKey(name: 'anilist_id', fromJson: flexibleInt)
  final int? anilistId;
  @JsonKey(name: 'imdb_id')
  final String? imdbId;
  @JsonKey(name: 'mal_id', fromJson: flexibleInt)
  final int? malId;
  @JsonKey(name: 'simkl_id', fromJson: flexibleInt)
  final int? simklId;
  @JsonKey(name: 'themoviedb_id', fromJson: flexibleInt)
  final int? tmdbId;
  @JsonKey(name: 'tvdb_id', fromJson: flexibleInt)
  final int? tvdbId;

  /// Plex season number this mapping corresponds to. A single show-level
  /// external ID can resolve to multiple rows for split-cour anime; the
  /// resolver picks by matching the episode's `parentIndex` against these.
  @JsonKey(readValue: _readTvdbSeason, fromJson: flexibleInt)
  final int? tvdbSeason;
  @JsonKey(readValue: _readTmdbSeason, fromJson: flexibleInt)
  final int? tmdbSeason;

  /// `TV` / `MOVIE` / `OVA` / `ONA` / `SPECIAL` / `UNKNOWN` / `null`.
  final String? type;

  const FribbMappingRow({
    this.anidbId,
    this.anilistId,
    this.imdbId,
    this.malId,
    this.simklId,
    this.tmdbId,
    this.tvdbId,
    this.tvdbSeason,
    this.tmdbSeason,
    this.type,
  });

  bool get isMovie => type == 'MOVIE';

  factory FribbMappingRow.fromJson(Map<String, dynamic> json) => _$FribbMappingRowFromJson(json);
}
