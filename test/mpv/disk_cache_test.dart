import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plezy/mpv/disk_cache.dart';

import '../test_helpers/io_fakes.dart';

void main() {
  group('mpv disk cache properties', () {
    test('enabling moves the cache to disk and raises the ceilings', () {
      final properties = mpvDiskCacheEnableProperties(r'C:\temp\plezy_mpv_cache');

      expect(properties['cache-on-disk'], 'yes');
      expect(properties['cache-dir'], r'C:\temp\plezy_mpv_cache');
      expect(properties['demuxer-max-bytes'], '$kMpvDiskCacheForwardBytes');
      expect(properties['demuxer-max-back-bytes'], '$kMpvDiskCacheBackBytes');
      expect(properties['demuxer-readahead-secs'], '$kMpvDiskCacheReadaheadSecs');
      // Byte ceilings govern the size, not a time limit.
      expect(properties['cache-secs'], '0');
    });

    test('the forward ceiling is far above mpv\'s 150 MiB default', () {
      expect(kMpvDiskCacheForwardBytes, greaterThan(1024 * 1024 * 1024));
      expect(kMpvDiskCacheForwardBytes, greaterThan(int.parse(kMpvDefaultDemuxerMaxBytes)));
    });

    test('disabling restores mpv defaults and turns the disk cache off', () {
      final properties = mpvDiskCacheDisableProperties();

      expect(properties['cache-on-disk'], 'no');
      expect(properties['demuxer-max-bytes'], kMpvDefaultDemuxerMaxBytes);
      expect(properties['demuxer-max-back-bytes'], kMpvDefaultDemuxerMaxBackBytes);
      expect(properties['demuxer-readahead-secs'], kMpvDefaultReadaheadSecs);
    });

    test('every key the enable path writes is also written when it is off', () {
      // The player is reused across items, so anything turned on for network
      // direct play has to be reset for a local file or a live stream.
      final enabled = mpvDiskCacheEnableProperties('/tmp/cache');
      final disabled = mpvDiskCacheDisableProperties();

      expect(
        enabled.keys.where((key) => !disabled.containsKey(key)),
        // `cache` and `cache-dir` are intentionally left as-is: `cache=auto` is
        // mpv's own default and `cache-dir` is inert with cache-on-disk=no.
        unorderedEquals(['cache', 'cache-dir']),
      );
    });
  });

  group('cache directory', () {
    late Directory root;
    late PathProviderPlatform originalPathProvider;

    setUp(() {
      root = Directory.systemTemp.createTempSync('plezy_disk_cache_test');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = FakePathProvider(root);
      resetMpvDiskCacheDir();
    });

    tearDown(() {
      resetMpvDiskCacheDir();
      PathProviderPlatform.instance = originalPathProvider;
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('resolves, creates and reuses one directory', () async {
      final first = await resolveMpvDiskCacheDir(root: root);

      expect(first, isNotNull);
      expect(Directory(first!).existsSync(), isTrue);
      expect(first, startsWith(root.path));

      final second = await resolveMpvDiskCacheDir(root: root);
      expect(second, first);
    });

    test('warming resolves once and the open path reads it synchronously', () async {
      // Unresolved means the open path must fall back to the RAM cache rather
      // than awaiting a platform round-trip.
      expect(mpvDiskCacheDirOrNull, isNull);

      await warmMpvDiskCacheDir(root: root);
      final resolved = mpvDiskCacheDirOrNull;

      expect(resolved, isNotNull);
      expect(resolved, startsWith(root.path));

      // A second warm is a no-op even when pointed somewhere else.
      await warmMpvDiskCacheDir(root: Directory.systemTemp);
      expect(mpvDiskCacheDirOrNull, resolved);
    });

    test('prunes leftovers from an unclean shutdown, keeps live ones', () async {
      final dir = Directory('${root.path}${Platform.pathSeparator}plezy_mpv_cache')..createSync(recursive: true);
      final stale = File('${dir.path}${Platform.pathSeparator}mpv-cache-stale')..writeAsStringSync('x');
      final live = File('${dir.path}${Platform.pathSeparator}mpv-cache-live')..writeAsStringSync('x');

      final now = DateTime.now();
      stale.setLastModifiedSync(now.subtract(const Duration(days: 30)));
      live.setLastModifiedSync(now.subtract(const Duration(days: 1)));

      await pruneMpvDiskCache(dir, now: now);

      expect(stale.existsSync(), isFalse);
      expect(live.existsSync(), isTrue);
    });

    test('returns null when the location cannot be created', () async {
      // A file sitting where the cache directory belongs makes creation fail.
      final blocked = File('${root.path}${Platform.pathSeparator}plezy_mpv_cache')
        ..writeAsStringSync('not a directory');

      expect(await resolveMpvDiskCacheDir(root: root), isNull);
      expect(blocked.existsSync(), isTrue);
    });
  });
}
