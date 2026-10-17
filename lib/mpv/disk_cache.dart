import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Disk-backed forward cache for mpv playback on desktop.
///
/// mpv's stock demuxer cache is ~150 MiB in RAM — a couple of minutes at
/// direct-play bitrates. Pausing to wait out a bad connection therefore banks
/// almost nothing and resuming re-fetches from the server, which is the
/// complaint this exists to fix: a pause should be able to pull the rest of
/// the episode down while there is time to spare.
///
/// Only direct play qualifies. A transcode stream is produced by the server on
/// demand, so reading ahead of it buys nothing, and a paused transcode session
/// can be reaped server-side anyway.
///
/// The values are applied as mpv properties before open() from
/// `_applyNetworkStreamTuning` in `parts/playback_open.dart`. Every key is
/// written on every open — turned on or restored to the default — because the
/// player is reused across items and would otherwise carry a disk cache into a
/// local file or a live stream.

/// mpv's documented default forward demuxer cache (150 MiB).
const String kMpvDefaultDemuxerMaxBytes = '157286400';

/// mpv's documented default backward demuxer cache (75 MiB).
const String kMpvDefaultDemuxerMaxBackBytes = '78643200';

/// mpv's default demuxer readahead.
const String kMpvDefaultReadaheadSecs = '20';

/// Forward cache ceiling: enough to bank a full 4K episode at streaming
/// bitrates, bounded so a fast connection cannot fill the disk unbounded.
const int kMpvDiskCacheForwardBytes = 2 * 1024 * 1024 * 1024;

/// Backward cache, so a rewind after a long pause does not re-fetch either.
const int kMpvDiskCacheBackBytes = 512 * 1024 * 1024;

/// Readahead ceiling in seconds. The byte caps above govern in practice; this
/// only stops a time-based default from cutting the cache short.
const int kMpvDiskCacheReadaheadSecs = 3600;

/// Leftover cache files older than this are pruned when the directory is
/// resolved. mpv deletes its own cache file on a clean shutdown; only a crash
/// or a kill leaves one behind.
const Duration kMpvDiskCacheMaxAge = Duration(days: 7);

String? _cacheDir;
bool _warmStarted = false;

/// The resolved cache directory, or null while unresolved or unavailable.
///
/// Read synchronously from the open path on purpose: awaiting path_provider
/// there would put a platform round-trip in front of every open, which the
/// playback screen tests and a mid-session player swap are sensitive to. An
/// open that beats [warmMpvDiskCacheDir] simply keeps mpv's RAM cache.
String? get mpvDiskCacheDirOrNull => _cacheDir;

/// Resolves the cache directory once for the life of the process. Called from
/// app startup, off the critical path.
Future<void> warmMpvDiskCacheDir({Directory? root}) async {
  if (_warmStarted) return;
  _warmStarted = true;
  _cacheDir = await resolveMpvDiskCacheDir(root: root);
}

/// Clears the resolved directory so a test can warm against its own root.
@visibleForTesting
void resetMpvDiskCacheDir() {
  _cacheDir = null;
  _warmStarted = false;
}

/// Whether the disk cache applies here: desktop only, where mpv is the player.
/// Android and iOS keep their RAM cache and ExoPlayer buffer tiers.
bool get mpvDiskCacheSupported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// mpv properties that move the forward cache to disk in [cacheDir].
Map<String, String> mpvDiskCacheEnableProperties(String cacheDir) => {
  'cache': 'yes',
  'cache-on-disk': 'yes',
  'cache-dir': cacheDir,
  'demuxer-max-bytes': '$kMpvDiskCacheForwardBytes',
  'demuxer-max-back-bytes': '$kMpvDiskCacheBackBytes',
  'demuxer-readahead-secs': '$kMpvDiskCacheReadaheadSecs',
  // 0 = let the byte ceiling decide instead of a time limit.
  'cache-secs': '0',
};

/// Properties that put every key in [mpvDiskCacheEnableProperties] back to
/// mpv's default, for opens that must not inherit the disk cache.
///
/// `cache` and `cache-dir` are deliberately left alone: `cache=auto` is mpv's
/// own default and re-enabling it is not this code's business, and
/// `cache-dir` is inert while `cache-on-disk=no`.
Map<String, String> mpvDiskCacheDisableProperties() => {
  'cache-on-disk': 'no',
  'demuxer-max-bytes': kMpvDefaultDemuxerMaxBytes,
  'demuxer-max-back-bytes': kMpvDefaultDemuxerMaxBackBytes,
  'demuxer-readahead-secs': kMpvDefaultReadaheadSecs,
  'cache-secs': '0',
};

/// Resolves the directory mpv should use for the disk cache, creating it on
/// first use and pruning leftovers from a previous crash.
///
/// Returns null when no writable location is available; callers fall back to
/// the default RAM cache rather than failing the open.
Future<String?> resolveMpvDiskCacheDir({Directory? root, DateTime? now, Duration maxAge = kMpvDiskCacheMaxAge}) async {
  try {
    final base = root ?? await getTemporaryDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}plezy_mpv_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await pruneMpvDiskCache(dir, now: now, maxAge: maxAge);
    return dir.path;
  } catch (_) {
    // FileSystemException when the location is unusable, and
    // MissingPluginException/PlatformException when path_provider is absent
    // (widget tests, stripped builds). Both mean "no disk cache here": fall
    // back to the default RAM cache rather than failing the open.
    return null;
  }
}

/// Deletes cache files in [dir] last modified longer than [maxAge] ago.
///
/// mpv writes a single `mpv-cache-*` file per open; anything older than
/// [maxAge] belongs to a run that did not shut down cleanly.
Future<void> pruneMpvDiskCache(Directory dir, {DateTime? now, Duration maxAge = kMpvDiskCacheMaxAge}) async {
  final cutoff = (now ?? DateTime.now()).subtract(maxAge);
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    try {
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        await entity.delete();
      }
    } on FileSystemException {
      // Another instance may be using it; leave it alone.
    }
  }
}
