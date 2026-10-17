import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plezy/mpv/disk_cache.dart';

import '../test_helpers/io_fakes.dart';

void main() {
  group('mpv disk cache properties', () {
    test('enabling moves cached packets to disk and raises the readahead', () {
      final properties = mpvDiskCacheEnableProperties(r'C:\temp\plezy_mpv_cache');

      // cache-on-disk is ignored unless the cache itself is on.
      expect(properties['cache'], 'yes');
      expect(properties['cache-on-disk'], 'yes');
      expect(properties['demuxer-cache-dir'], r'C:\temp\plezy_mpv_cache');
      expect(properties['demuxer-readahead-secs'], '$kMpvDiskCacheReadaheadSecs');
    });

    test('uses the real mpv option name for the cache directory', () {
      // `cache-dir` is not an mpv option; setting it throws, which used to
      // abort the rest of the tuning.
      final properties = mpvDiskCacheEnableProperties('/tmp/cache');

      expect(properties.containsKey('cache-dir'), isFalse);
      expect(properties.containsKey('demuxer-cache-dir'), isTrue);
    });

    test('does not touch the demuxer byte limits', () {
      // With cache-on-disk those bound packet *metadata*, not the cache file,
      // so mpv's stock values are the right ones.
      final properties = mpvDiskCacheEnableProperties('/tmp/cache');

      expect(properties.containsKey('demuxer-max-bytes'), isFalse);
      expect(properties.containsKey('demuxer-max-back-bytes'), isFalse);
      expect(properties.containsKey('cache-secs'), isFalse);
    });

    test('readahead is far above mpv\'s 20 second default', () {
      expect(kMpvDiskCacheReadaheadSecs, greaterThan(600));
      expect(int.parse(kMpvDefaultReadaheadSecs), 20);
    });

    test('disabling restores mpv defaults and turns the disk cache off', () {
      final properties = mpvDiskCacheDisableProperties();

      expect(properties['cache-on-disk'], 'no');
      expect(properties['demuxer-readahead-secs'], kMpvDefaultReadaheadSecs);
    });

    test('every key the enable path writes is also written when it is off', () {
      // The player is reused across items, so anything turned on for network
      // direct play has to be reset for a local file or a live stream.
      final enabled = mpvDiskCacheEnableProperties('/tmp/cache');
      final disabled = mpvDiskCacheDisableProperties();

      expect(
        enabled.keys.where((key) => !disabled.containsKey(key)),
        // `cache` and `demuxer-cache-dir` are intentionally left as-is:
        // `cache=auto` is mpv's own default and the cache directory is only
        // consulted while cache-on-disk is on.
        unorderedEquals(['cache', 'demuxer-cache-dir']),
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
    });

    tearDown(() {
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
