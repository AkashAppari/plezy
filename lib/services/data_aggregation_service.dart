import 'dart:async';

import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import '../utils/global_key_utils.dart';
import '../utils/search_relevance.dart';
import 'multi_server_manager.dart';

/// Cross-server aggregation: fans calls out to every online client and
/// merges the results. Single-server operations now go through the
/// [MediaServerClient] interface directly (resolved via
/// [ProviderExtensions.tryGetMediaClientForServer] etc.), so this service
/// only owns the genuinely multi-server flows: home/discover hubs, on-deck,
/// search, and the global library list.
class DataAggregationService {
  final MultiServerManager _serverManager;

  DataAggregationService(this._serverManager);

  /// Fetch libraries from all online clients regardless of backend, returning
  /// neutral [MediaLibrary]s.
  Future<List<MediaLibrary>> getMediaLibrariesFromAllServers() async {
    final clients = _serverManager.onlineClients;
    if (clients.isEmpty) {
      appLogger.w('No online servers available for fetching libraries (neutral)');
      return [];
    }
    final futures = clients.entries.map((entry) async {
      try {
        return await entry.value.fetchLibraries();
      } catch (e, stackTrace) {
        appLogger.e('Failed neutral library fetch from ${entry.key}', error: e, stackTrace: stackTrace);
        return <MediaLibrary>[];
      }
    });
    final results = await Future.wait(futures);
    return [for (final list in results) ...list];
  }

  /// Fetch "On Deck" (Continue Watching) from all servers and merge by recency.
  /// Items are tagged with server info by the underlying client. Returns
  /// neutral [MediaItem]s.
  Future<List<MediaItem>> getOnDeckFromAllServers({int? limit, Set<String>? hiddenLibraryKeys}) async {
    final clients = _serverManager.onlineClients;
    if (clients.isEmpty) {
      appLogger.w('No online servers available for fetching on deck');
      return [];
    }
    final futures = clients.entries.map((entry) async {
      final client = entry.value;
      try {
        return await client.fetchContinueWatching(count: limit);
      } catch (e, st) {
        appLogger.e('Failed on-deck fetch from ${entry.key}', error: e, stackTrace: st);
        return <MediaItem>[];
      }
    });
    final allOnDeck = (await Future.wait(futures)).expand((l) => l).toList();

    // Filter out items from hidden libraries
    List<MediaItem> filteredOnDeck = allOnDeck;
    if (hiddenLibraryKeys != null && hiddenLibraryKeys.isNotEmpty) {
      filteredOnDeck = allOnDeck.where((item) {
        if (item.libraryId == null || item.serverId == null) return true;
        final globalKey = buildGlobalKey(item.serverId!, item.libraryId!);
        return !hiddenLibraryKeys.contains(globalKey);
      }).toList();
    }

    // Sort by most recently viewed, falling back to addedAt for unwatched items
    filteredOnDeck.sort((a, b) {
      final aTime = a.lastViewedAt ?? a.addedAt ?? 0;
      final bTime = b.lastViewedAt ?? b.addedAt ?? 0;
      return bTime.compareTo(aTime); // Descending (most recent first)
    });

    // Apply limit if specified
    final result = limit != null && limit < filteredOnDeck.length ? filteredOnDeck.sublist(0, limit) : filteredOnDeck;

    appLogger.i('Fetched ${result.length} on deck items from all servers');

    return result;
  }

  /// Fetch recommendation hubs from all servers as neutral [MediaHub]s.
  /// When useGlobalHubs is true (default), rich-hub backends use their true
  /// home page hubs (Plex's promoted/global hub endpoint).
  /// Backends without rich home hubs fall back to per-library hubs so one
  /// capped "Latest" response cannot hide whole library types.
  Future<List<MediaHub>> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
  }) async {
    final clients = _serverManager.onlineClients;
    if (clients.isEmpty) {
      appLogger.w('No online servers available for fetching hubs');
      return [];
    }

    // Only fallback clients need a library prefetch when home layout is on;
    // rich-hub backends return the intended home rows directly.
    final needsLibraryPrefetch = useGlobalHubs && clients.values.any((client) => !client.capabilities.richHubs);
    final libraries = needsLibraryPrefetch ? _groupLibrariesByServer(await getMediaLibrariesFromAllServers()) : null;

    final futures = clients.entries.map((entry) async {
      final serverId = entry.key;
      final client = entry.value;
      try {
        final serverLibraries = libraries?[serverId];
        final shouldUseGlobalHubs = useGlobalHubs && client.capabilities.richHubs;
        final hubs = shouldUseGlobalHubs
            ? await client.fetchGlobalHubs(limit: limit ?? 10, includePlaybackHubs: includePlaybackHubs)
            : await _fetchLibraryHubsForClient(
                client,
                limit: limit ?? 10,
                hiddenLibraryKeys: hiddenLibraryKeys,
                includePlaybackHubs: includePlaybackHubs,
                libraries: useGlobalHubs ? serverLibraries : null,
              );
        return _postProcessHubs(hubs, serverId: serverId, hiddenLibraryKeys: hiddenLibraryKeys);
      } catch (e, stackTrace) {
        appLogger.e('Failed to fetch hubs from server $serverId', error: e, stackTrace: stackTrace);
        return <MediaHub>[];
      }
    });

    final results = await Future.wait(futures);
    final all = <MediaHub>[];
    for (final list in results) {
      all.addAll(list);
    }
    return limit != null && limit < all.length ? all.sublist(0, limit) : all;
  }

  /// Per-library hub fetch for a single client. Filters to visible
  /// movie/show libraries (Plex hides music libraries from this surface) and
  /// concatenates the results.
  Future<List<MediaHub>> _fetchLibraryHubsForClient(
    MediaServerClient client, {
    required int limit,
    Set<String>? hiddenLibraryKeys,
    required bool includePlaybackHubs,
    List<MediaLibrary>? libraries,
  }) async {
    final libs = libraries ?? await client.fetchLibraries();
    final visible = libs.where((l) {
      if (l.kind != MediaKind.movie && l.kind != MediaKind.show) return false;
      if (l.hidden) return false;
      if (hiddenLibraryKeys != null && hiddenLibraryKeys.contains(l.globalKey)) return false;
      return true;
    }).toList();

    const concurrency = 3;
    final all = <MediaHub>[];
    for (var start = 0; start < visible.length; start += concurrency) {
      final batch = visible.skip(start).take(concurrency);
      final results = await Future.wait(
        batch.map((l) async {
          try {
            return await client.fetchLibraryHubs(
              l.id,
              libraryName: l.title,
              limit: limit,
              includePlaybackHubs: includePlaybackHubs,
              libraryKind: l.kind,
            );
          } catch (e, st) {
            appLogger.e('Failed to fetch library hubs for ${l.globalKey}', error: e, stackTrace: st);
            return <MediaHub>[];
          }
        }),
      );
      for (final list in results) {
        all.addAll(list);
      }
    }
    return all;
  }

  /// Filter hidden-library items and drop empty hubs.
  List<MediaHub> _postProcessHubs(List<MediaHub> hubs, {required String serverId, Set<String>? hiddenLibraryKeys}) {
    var filtered = hubs;
    if (hiddenLibraryKeys != null && hiddenLibraryKeys.isNotEmpty) {
      filtered = filtered
          .map((hub) {
            final filteredItems = hub.items.where((item) {
              final libraryId = item.libraryId;
              if (libraryId == null) return true;
              final globalKey = buildGlobalKey(serverId, libraryId);
              return !hiddenLibraryKeys.contains(globalKey);
            }).toList();
            if (filteredItems.isEmpty) return null;
            return hub.copyWith(items: filteredItems, size: filteredItems.length);
          })
          .whereType<MediaHub>()
          .toList();
    }
    return filtered;
  }

  /// Search across all online servers (Plex + Jellyfin). Returns neutral
  /// [MediaItem]s.
  Future<List<MediaItem>> searchAcrossServers(String query, {int? limit}) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final clients = _serverManager.onlineClients;
    if (clients.isEmpty) return [];

    final resultLimit = limit ?? defaultMediaSearchLimit;
    final fetchLimit = resultLimit < defaultMediaSearchLimit ? defaultMediaSearchLimit : resultLimit;

    final futures = clients.entries.map((entry) async {
      final client = entry.value;
      try {
        return await client.searchItems(query, limit: fetchLimit);
      } catch (e, st) {
        appLogger.e('Search failed on ${entry.key}', error: e, stackTrace: st);
        return <MediaItem>[];
      }
    });

    final allResults = (await Future.wait(futures)).expand((l) => l).toList();
    final result = rankMediaSearchResults(allResults, query, limit: resultLimit);

    appLogger.i('Found ${result.length} search results across all servers');

    return result;
  }

  /// Group libraries by server (internal aggregation helper).
  Map<String, List<MediaLibrary>> _groupLibrariesByServer(List<MediaLibrary> libraries) {
    final grouped = <String, List<MediaLibrary>>{};

    for (final library in libraries) {
      final serverId = library.serverId;
      if (serverId != null) {
        grouped.putIfAbsent(serverId, () => []).add(library);
      }
    }

    return grouped;
  }
}
