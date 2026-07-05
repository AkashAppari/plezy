import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../screens/music/album_detail_screen.dart';
import '../screens/music/artist_detail_screen.dart';
import '../services/music/music_playback_service.dart';
import 'app_logger.dart';
import 'provider_extensions.dart';
import 'snackbar_helper.dart';

/// Push the artist detail screen for [artist] on the nearest navigator.
Future<void> navigateToArtist(BuildContext context, MediaItem artist) async {
  await Navigator.push(context, MaterialPageRoute(builder: (context) => ArtistDetailScreen(artist: artist)));
}

/// Push the album detail screen for [album] on the nearest navigator.
Future<void> navigateToAlbum(BuildContext context, MediaItem album) async {
  await Navigator.push(context, MaterialPageRoute(builder: (context) => AlbumDetailScreen(album: album)));
}

/// True when a real music playback engine is bound. On the stub this shows
/// the standard "not supported yet" notice and returns false — check it
/// BEFORE fetching tracks so the stub never costs a server round-trip.
bool ensureMusicPlaybackAvailable(BuildContext context) {
  if (context.read<MusicPlaybackService>().isAvailable) return true;
  showAppSnackBar(context, t.messages.musicNotSupported);
  return false;
}

/// Start playback of [tracks] via the session [MusicPlaybackService],
/// surfacing the "not supported yet" notice while the stub is bound.
Future<void> playTracks(
  BuildContext context, {
  required List<MediaItem> tracks,
  MediaItem? startTrack,
  required MusicPlayContext playContext,
  bool shuffle = false,
}) async {
  if (!ensureMusicPlaybackAvailable(context)) return;
  await context.read<MusicPlaybackService>().playFromList(
    tracks: tracks,
    startTrack: startTrack,
    playContext: playContext,
    shuffle: shuffle,
  );
}

/// Play [track] within its album queue: fetch the album's tracks and start
/// at [track]. Falls back to single-track playback when the track has no
/// album, isn't found in it, or the album fetch fails.
Future<void> playTrackWithAlbumContext(BuildContext context, MediaItem track) async {
  if (!ensureMusicPlaybackAvailable(context)) return;

  final albumId = track.parentId;
  final client = context.getMediaClientForItemOrNull(track);
  if (albumId != null && client != null) {
    try {
      final tracks = await client.fetchAlbumTracks(albumId);
      final startIndex = tracks.indexWhere((item) => item.id == track.id);
      if (!context.mounted) return;
      if (startIndex != -1) {
        await playTracks(
          context,
          tracks: tracks,
          startTrack: tracks[startIndex],
          playContext: MusicPlayContext(id: albumId, title: track.albumTitle ?? '', kind: MusicPlayContextKind.album),
        );
        return;
      }
    } catch (e) {
      appLogger.w('Failed to fetch album context for track ${track.id}; playing single track', error: e);
      if (!context.mounted) return;
    }
  }

  await playTracks(
    context,
    tracks: [track],
    playContext: MusicPlayContext(title: track.title ?? '', kind: MusicPlayContextKind.tracks),
  );
}

/// Fetch and play an instant mix seeded from [seed] (track/album/artist).
/// Only call when the seed's server advertises
/// `ServerCapabilities.instantMix`.
Future<void> playInstantMix(BuildContext context, MediaItem seed) async {
  if (!ensureMusicPlaybackAvailable(context)) return;
  await context.read<MusicPlaybackService>().playInstantMix(seed);
}
