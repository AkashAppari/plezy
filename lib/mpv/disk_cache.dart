import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Disk-backed forward cache for mpv playback on desktop.
///
/// mpv's stock demuxer cache is memory-only and bounded by
/// `--demuxer-max-bytes` (150 MiB) and `--demuxer-readahead-secs` (20 s), so
/// pausing to wait out a bad connection banks a couple of minutes at best and
/// resuming re-fetches from the server. This keeps pulling the stream down
/// while playback is paused, on disk instead of in RAM.
///
/// Semantics that matter, straight from mpv's manual:
///   * `--cache-on-disk` writes packet *data* to a temporary file and is
///     append-only. It is not bounded by `--demuxer-max-bytes`.
///   * While it is on, `--demuxer-max-bytes` and `--demuxer-max-back-bytes`
///     bound the *metadata* only (roughly 50 MB per hour of media), so the
///     stock values are left alone.
///   * What actually bounds how far ahead mpv reads is
///     `--demuxer-readahead-secs`, which is what this module raises.
///   * The cache file is deleted when the media is closed.
///   * `--cache-on-disk` is ignored unless `--cache` is active.
///
/// Applies to network video-on-demand on desktop; live streams and local files
/// are left on mpv's defaults. Transcodes are included: a server reached over
/// Plex Relay answers with a transcode, and reading ahead still makes the
/// server produce more, which is the case this exists for.
///
/// The values are applied as mpv properties before open() from
/// `_applyNetworkStreamTuning` in `parts/playback_open.dart`. Every key is
/// written on every open — turned on or restored to the default — because the
/// player is reused across items and would otherwise carry a disk cache into a
/// local file or a live stream.

/// mpv's default demuxer readahead, restored for opens that must not cache.
const String kMpvDefaultReadaheadSecs = '20';

/// How far ahead mpv may read while the disk cache is on.
///
/// 30 minutes banks an entire episode for the bad-connection case this exists
/// for, while still bounding the temporary file: a 20 Mbps direct-play stream
/// tops out around 4.5 GB, and the file is deleted when playback closes.
const int kMpvDiskCacheReadaheadSecs = 1800;

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

/// Whether the disk cache applies here: desktop only, where mpv is the player.
/// Android and iOS keep their RAM cache and ExoPlayer buffer tiers.
bool get mpvDiskCacheSupported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// mpv properties that move cached packets to disk in [cacheDir] and let mpv
/// read far enough ahead for a pause to bank real media.
Map<String, String> mpvDiskCacheEnableProperties(String cacheDir) => {
  'cache': 'yes',
  'cache-on-disk': 'yes',
  // The real option name: `cache-dir` does not exist in mpv and throws on set.
  'demuxer-cache-dir': cacheDir,
  'demuxer-readahead-secs': '$kMpvDiskCacheReadaheadSecs',
};

/// Properties that put every key in [mpvDiskCacheEnableProperties] back to
/// mpv's default, for opens that must not inherit the disk cache.
///
/// `cache` is left alone: `cache=auto` is mpv's own default and re-enabling it
/// is not this code's business. `demuxer-cache-dir` is only consulted while
/// `cache-on-disk` is on, so it needs no reset.
Map<String, String> mpvDiskCacheDisableProperties() => {
  'cache-on-disk': 'no',
  'demuxer-readahead-secs': kMpvDefaultReadaheadSecs,
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
