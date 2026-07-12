import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';

import 'media_items.dart';

void main() {
  test('default fixture is a minimal Plex movie', () {
    final item = testMediaItem();

    expect(item.id, 'item-1');
    expect(item.backend, MediaBackend.plex);
    expect(item.kind, MediaKind.movie);
    expect(item.serverId, isNull);
    expect(item.parentId, isNull);
    expect(item.viewCount, isNull);
  });

  test('season and episode fixtures preserve canonical hierarchy and scope', () {
    final show = testMediaItem(
      id: 'show-1',
      kind: MediaKind.show,
      backend: MediaBackend.jellyfin,
      title: 'Show',
      serverId: 'server-1',
      serverName: 'Server',
      libraryId: 'library-1',
      libraryTitle: 'Library',
    );
    final season = testSeason(id: 'season-2', show: show, index: 2, title: 'Season 2');
    final episode = testEpisode(id: 'episode-3', show: show, season: season, index: 3, title: 'Episode 3');

    expect(season.backend, show.backend);
    expect(season.parentId, show.id);
    expect(season.parentTitle, show.title);
    expect(episode.parentId, season.id);
    expect(episode.parentTitle, season.title);
    expect(episode.parentIndex, season.index);
    expect(episode.grandparentId, show.id);
    expect(episode.grandparentTitle, show.title);
    expect(episode.serverId, show.serverId);
    expect(episode.libraryId, show.libraryId);
  });
}
