part of '../../jellyfin_client.dart';

mixin _JellyfinCollectionMethods on MediaServerCacheMixin {
  JellyfinConnection get connection;
  MediaServerHttpClient get _http;
  Map<String, List<MediaItem>> get _collectionItemsCache;
  List<MediaItem> _mapItems(Iterable<Map<String, dynamic>> items);

  @override
  Future<List<MediaItem>> fetchCollections(String libraryId) async {
    // Jellyfin keeps BoxSets under a dedicated top-level view, not under each
    // movie/show library. Query that root to avoid recursively scanning media.
    final boxSetsViewId = await _fetchBoxSetsViewId();
    final response = await _http.get(
      '/Items',
      queryParameters: {
        'userId': connection.userId,
        'ParentId': ?boxSetsViewId,
        'IncludeItemTypes': 'BoxSet',
        'Recursive': 'true',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Fields': _browseFields,
        ...jellyfinImageQueryParameters,
      },
    );
    throwIfHttpError(response);
    return _mapItems(_itemsArray(response.data));
  }

  Future<String?> _fetchBoxSetsViewId() async {
    final response = await _http.get('/Users/${_segment(connection.userId)}/Views');
    throwIfHttpError(response);
    for (final view in _itemsArray(response.data)) {
      final collectionType = (view['CollectionType'] as String?)?.toLowerCase();
      final id = view['Id'] as String?;
      if (collectionType == 'boxsets' && id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  /// Jellyfin has no pagination knob for collection children, so the first
  /// call materialises the full list via [fetchChildren] and subsequent
  /// paged calls slice from the same in-memory copy ([_collectionItemsCache]).
  /// The [abort] hook is unused on this backend — the slice path is
  /// synchronous and the underlying fetch is short-lived.
  @override
  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String collectionId, {
    int? start,
    int? size,
    AbortController? abort,
    String? libraryId,
    String? libraryTitle,
  }) async {
    final cached = _collectionItemsCache[collectionId] ?? await _loadAndCacheCollectionItems(collectionId);
    final s = start ?? 0;
    final fullSize = cached.length;
    final from = s.clamp(0, fullSize);
    final to = (size == null) ? fullSize : (s + size).clamp(0, fullSize);
    return LibraryPage<MediaItem>(items: cached.sublist(from, to), totalCount: fullSize, offset: s);
  }

  Future<List<MediaItem>> _loadAndCacheCollectionItems(String collectionId) async {
    final items = await fetchChildren(collectionId);
    _collectionItemsCache[collectionId] = items;
    return items;
  }

  @override
  Future<String?> createCollection({
    required String libraryId,
    required String title,
    required List<MediaItem> items,
    MediaKind? itemKind,
  }) async {
    // ParentId is optional on Jellyfin's `/Collections` endpoint — when
    // omitted the server picks a default BoxSet root. We pass libraryId so
    // the new collection lives in the same library as the seeded items.
    final response = await _http.post(
      '/Collections',
      queryParameters: {
        'Name': title,
        if (items.isNotEmpty) 'Ids': items.map((i) => i.id).join(','),
        if (libraryId.isNotEmpty) 'ParentId': libraryId,
      },
    );
    throwIfHttpError(response);
    final data = response.data;
    return data is Map<String, dynamic> ? data['Id'] as String? : null;
  }

  @override
  Future<bool> addToCollection({required String collectionId, required List<MediaItem> items}) async {
    if (items.isEmpty) return true;
    final response = await _http.post(
      '/Collections/${_segment(collectionId)}/Items',
      queryParameters: {'Ids': items.map((i) => i.id).join(',')},
    );
    throwIfHttpError(response);
    return true;
  }

  @override
  Future<bool> removeFromCollection({required String collectionId, required MediaItem item}) async {
    final response = await _http.delete(
      '/Collections/${_segment(collectionId)}/Items',
      queryParameters: {'Ids': item.id},
    );
    throwIfHttpError(response);
    return true;
  }

  @override
  Future<bool> deleteCollection(MediaItem collection) async {
    final response = await _http.delete('/Items/${_segment(collection.id)}');
    throwIfHttpError(response);
    return true;
  }

  @override
  Future<bool> deleteMediaItem(MediaItem item) async {
    final response = await _http.delete('/Items/${_segment(item.id)}');
    throwIfHttpError(response);
    return true;
  }
}
