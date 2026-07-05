import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../../media/media_display_criteria.dart';
import '../../utils/app_logger.dart';
import '../models.dart';
import 'player_base.dart';

/// MPV-backed player for platforms where AetherEngine is not the native route.
class PlayerNative extends PlayerBase {
  /// Video player on the default mpv channels/core.
  PlayerNative()
    : methodChannel = const MethodChannel('com.plezy/mpv_player'),
      eventChannel = const EventChannel('com.plezy/mpv_player/events'),
      audioOnly = false;

  /// Audio-only player on the dedicated music channels/core (see
  /// [Player.audio]). Skips every video concern: no render layer
  /// ([setVisible] no-ops via [audioOnly]), no subtitle plumbing, no
  /// display-mode handling.
  PlayerNative.audio()
    : methodChannel = const MethodChannel('com.plezy/mpv_audio_player'),
      eventChannel = const EventChannel('com.plezy/mpv_audio_player/events'),
      audioOnly = true;

  int? _textureIdValue;
  String _dvConversionMode = 'auto';
  String _dvConversionLog = 'no';

  // Gapless-audio arming state (audioOnly). The native playlist is always
  // [current, next?]; these track whether entry 1 exists and what it plays.
  bool _hasArmedNext = false;
  String? _armedNextUri;

  // Set by open() and consumed by that load's file-loaded event, so it is
  // not mistaken for a gapless advance (see _handleAudioFileLoaded).
  bool _expectOpenFileLoad = false;

  @override
  int? get textureId => _textureIdValue;

  /// Whether this instance drives the audio-only core.
  final bool audioOnly;

  @override
  final MethodChannel methodChannel;

  @override
  final EventChannel eventChannel;

  @override
  String get logPrefix => audioOnly ? 'MPV-audio' : 'MPV';

  @override
  String get playerType => 'mpv';

  @override
  bool get providesNativeStats => Platform.isAndroid;

  @override
  bool get attachesExternalSubtitlesAtOpen => true;

  /// Node properties are returned as structured maps on macOS/iOS/Linux,
  /// but as JSON strings on Android/Windows.
  static final String _nodeFormat = (Platform.isAndroid || Platform.isWindows) ? 'string' : 'node';

  static String _normalizeDvConversionMode(String value) {
    return switch (value.toLowerCase()) {
      'disabled' || 'native' => 'disabled',
      'dv81' || 'p8' || 'p7_to_p8' || 'p7-to-p8' => 'dv81',
      'hevc' || 'hevc_strip' || 'p7_to_hevc' || 'p7-to-hevc' => 'hevc_strip',
      _ => 'auto',
    };
  }

  static String _normalizeBoolProperty(String value) {
    return switch (value.toLowerCase()) {
      '1' || 'true' || 'yes' || 'on' => 'yes',
      _ => 'no',
    };
  }

  static String _fixedLengthQuote(String value) {
    return '%${utf8.encode(value).length}%$value';
  }

  /// Query-free tail of [uri] for logs (keeps the part id, drops tokens).
  static String _uriTail(String uri) {
    final path = uri.split('?').first;
    return path.length <= 40 ? path : '…${path.substring(path.length - 40)}';
  }

  static String _escapePathListEntry(String value, String separator) {
    return value.replaceAll(r'\', r'\\').replaceAll(separator, '\\$separator');
  }

  static String? _externalSubtitlesLoadfileOption(List<SubtitleTrack>? externalSubtitles) {
    final separator = Platform.isWindows ? ';' : ':';
    final escapedUris = externalSubtitles
        ?.map((subtitle) => subtitle.uri)
        .whereType<String>()
        .where((uri) => uri.isNotEmpty)
        .map((uri) => _escapePathListEntry(uri, separator))
        .toList();
    if (escapedUris == null || escapedUris.isEmpty) return null;

    return 'sub-files=${_fixedLengthQuote(escapedUris.join(separator))}';
  }

  /// Per-entry `http-header-fields` for a `loadfile ... append` options arg.
  /// The fixed-length quote shields the whole value from the key=value list
  /// parser; mpv then splits the headers on commas, the same separator the
  /// `setProperty('http-header-fields', ...)` path in [open] relies on.
  static String? _httpHeaderFieldsLoadfileOption(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return null;
    final headerList = headers.entries.map((e) => '${e.key}: ${e.value}').join(',');
    return 'http-header-fields=${_fixedLengthQuote(headerList)}';
  }

  MediaDisplayCriteria? _effectiveDisplayCriteria(MediaDisplayCriteria? criteria) {
    if (criteria == null || (criteria.doviProfile ?? 0) != 7) return criteria;

    final convertToDv81 = _dvConversionMode == 'auto' || _dvConversionMode == 'dv81';
    if (convertToDv81) {
      return MediaDisplayCriteria(
        fps: criteria.fps,
        width: criteria.width,
        height: criteria.height,
        doviProfile: 8,
        doviLevel: criteria.doviLevel,
        doviCompatibilityId: 1,
        transfer: criteria.transfer ?? 'smpte2084',
        primaries: criteria.primaries ?? 'bt2020',
        matrix: criteria.matrix ?? 'bt2020nc',
      );
    }

    return MediaDisplayCriteria(
      fps: criteria.fps,
      width: criteria.width,
      height: criteria.height,
      doviProfile: 0,
      doviCompatibilityId: criteria.doviCompatibilityId ?? 1,
      transfer: criteria.transfer ?? 'smpte2084',
      primaries: criteria.primaries ?? 'bt2020',
      matrix: criteria.matrix ?? 'bt2020nc',
    );
  }

  // Memoizes the in-flight init Future so concurrent callers (e.g. the
  // parallel `requestAudioFocus()` and `setProperty()` paths kicked off in
  // VideoPlayerScreen._initializePlayer) share one `invoke('initialize')`.
  // Two concurrent invokes on Android caused MpvPlayerPlugin.handleInitialize
  // to dispose-and-recreate the in-flight core, hanging playback (#930).
  Future<void>? _initFuture;

  Future<void> _ensureInitialized() async {
    if (initialized) return;
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    try {
      final result = await invoke<Object>('initialize');
      final bool ok;
      if (result is int) {
        // Linux: initialize returns the texture ID
        _textureIdValue = result;
        ok = true;
      } else {
        ok = result == true;
      }
      if (!ok) {
        throw Exception('Failed to initialize player');
      }

      // Subscribe to MPV properties before flipping `initialized` so partial
      // failures don't leave us in a half-initialized state that the memoized
      // future would falsely treat as ready.
      await observeCoreProperties(trackListFormat: _nodeFormat);
      await observeProperty('secondary-sid', 'string');
      await observeProperty('demuxer-cache-state', _nodeFormat);
      await observeProperty('audio-device-list', _nodeFormat);
      await observeProperty('audio-device', 'string');

      if (audioOnly) {
        // Debug aid only: raw playlist positions in the log trail. Gapless
        // advance DETECTION rides the file-loaded event instead — see
        // _handleAudioFileLoaded for why property edges are unreliable.
        await observeProperty('playlist-pos', _nodeFormat);
        // The Apple audio core sets this at context init; set it defensively
        // here so every mpv audio backend behaves identically. Direct invoke —
        // setProperty() would await _ensureInitialized and deadlock on the
        // memoized future of this very _doInitialize call.
        await invoke('setProperty', {'name': 'gapless-audio', 'value': 'weak'});
      }

      initialized = true;
    } catch (e) {
      _initFuture = null;
      errorController.add(PlayerError('Initialization failed: $e'));
      rethrow;
    }
  }

  Future<int?> _openContentFd(String contentUri) async {
    try {
      return await invoke<int>('openContentFd', {'uri': contentUri});
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> open(
    Media media, {
    bool play = true,
    bool isLive = false,
    List<SubtitleTrack>? externalSubtitles,
    Duration timelineOffset = Duration.zero,
    Duration? timelineDuration,
  }) async {
    if (disposed) return;
    await _ensureInitialized();
    // `loadfile replace` (below) clears the native playlist, dropping any
    // gapless entry armed via setNext.
    _hasArmedNext = false;
    _armedNextUri = null;
    final startPosition = media.start ?? Duration.zero;
    configureTimeline(offset: timelineOffset, duration: timelineDuration);
    clearTracks();
    setExternalSubtitleMetadata(externalSubtitles);
    resetPlaybackProgress(startPosition);
    setSeekable(false);

    if (!audioOnly) await setVisible(true);

    if (media.headers != null && media.headers!.isNotEmpty) {
      final headerList = media.headers!.entries.map((e) => '${e.key}: ${e.value}').toList();
      await setProperty('http-header-fields', headerList.join(','));
    }

    // 'start' must be set before loadfile.
    if (startPosition.inSeconds > 0) {
      await setProperty('start', (startPosition.inMilliseconds / 1000.0).toString());
    } else {
      await setProperty('start', 'none');
    }

    // Prevents race condition that can freeze the video decoder on Android (issue #226).
    if (!play) {
      await setProperty('pause', 'yes');
    }

    // Prevent mpv's own default subtitle selection from racing the
    // server-backed TrackManager decision applied after tracks are discovered.
    await setProperty('sid', 'no');
    await setProperty('secondary-sid', 'no');

    // Convert content:// URIs to fdclose:// for MPV on Android (SAF SD card downloads)
    var uri = media.uri;
    if (Platform.isAndroid && uri.startsWith('content://')) {
      final fd = await _openContentFd(uri);
      if (fd != null) {
        uri = 'fdclose://$fd';
      }
    }

    final loadfileArgs = ['loadfile', uri, 'replace'];
    final loadfileOption = _externalSubtitlesLoadfileOption(externalSubtitles);
    if (loadfileOption != null) {
      loadfileArgs.addAll(['-1', loadfileOption]);
    }
    if (audioOnly) _expectOpenFileLoad = true;
    await command(loadfileArgs);

    // mpv's pause property survives loadfile; in-place reloads pause the old
    // file before resolving, so explicitly unpause for the replacement. Set
    // after loadfile so the paused old file never audibly unpauses
    // pre-replace.
    if (play) {
      await setProperty('pause', 'no');
    }
  }

  @override
  Future<void> play() async {
    await setProperty('pause', 'no');
  }

  @override
  Future<void> pause() async {
    await setProperty('pause', 'yes');
  }

  @override
  Future<void> stop() async {
    _hasArmedNext = false;
    _armedNextUri = null;
    await command(['stop']);
    setSeekable(false);
    if (!audioOnly) await invoke('setVisible', {'visible': false});
  }

  @override
  Future<void> seek(Duration position) async {
    final sourcePosition = sourceSeekPosition(position);
    await runSeek(position, () => command(['seek', (sourcePosition.inMilliseconds / 1000.0).toString(), 'absolute']));
  }

  @override
  Future<void> setNext(Media? media) async {
    if (!audioOnly || disposed || !initialized) return;

    if (_hasArmedNext) {
      _hasArmedNext = false;
      _armedNextUri = null;
      appLogger.d('MPV-audio: clearing armed entry (playlist-remove 1)');
      try {
        await command(['playlist-remove', '1']);
      } on PlatformException {
        // Entry 1 can vanish in the arm/advance race (mpv already rolled into
        // it); the append below still lands after the current entry.
      }
    }
    if (media == null) return;

    // Per-entry options are the 4th loadfile argument on mpv >= 0.38
    // (`loadfile <url> append -1 opt=val`), exactly like open() passes
    // sub-files. `gapless-audio=weak` splices the armed entry into the
    // running audio stream when formats match.
    final args = ['loadfile', media.uri, 'append'];
    final headerOption = _httpHeaderFieldsLoadfileOption(media.headers);
    if (headerOption != null) {
      args.addAll(['-1', headerOption]);
    }
    await command(args);
    _hasArmedNext = true;
    _armedNextUri = media.uri;
    appLogger.d('MPV-audio: armed next ${_uriTail(media.uri)}');
  }

  @override
  void handlePropertyChange(String name, dynamic value) {
    if (audioOnly && name == 'playlist-pos') {
      // Debug aid only — see _handleAudioFileLoaded for the real detection.
      appLogger.d('MPV-audio: playlist-pos=$value (armed=$_hasArmedNext)');
      return;
    }
    super.handlePropertyChange(name, value);
  }

  @override
  void handlePlayerEvent(String name, Map? data) {
    if (audioOnly && name == 'file-loaded') _handleAudioFileLoaded();
    super.handlePlayerEvent(name, data);
  }

  /// Gapless auto-advance detection: a `file-loaded` that open() didn't
  /// produce while an entry is armed means mpv rolled into the armed entry.
  /// Surface the transition, then rebase the playlist so the now playing
  /// entry sits at index 0 again ([setNext] always appends at 1). The rebase
  /// only removes the spent entry behind the playing one, so it cannot
  /// disturb position/duration — those refresh with the same file-loaded.
  ///
  /// Detection deliberately rides this EVENT, not `playlist-pos` property
  /// edges: mpv coalesces observed-property notifications per observer
  /// (1→0→1 under delivery lag nets out to nothing) and the Android bridge
  /// additionally drops property changes when its shared 64-slot buffer
  /// overflows (`MutableSharedFlow.tryEmit` from the native event thread),
  /// so an edge can vanish entirely — which stalled playback at the end of
  /// the armed track. `file-loaded` fires exactly once per started file on
  /// the low-volume event flow. Clearing [_hasArmedNext] before emitting
  /// makes a hypothetical duplicate signal a no-op (it cannot double
  /// advance).
  void _handleAudioFileLoaded() {
    if (_expectOpenFileLoad) {
      _expectOpenFileLoad = false;
      appLogger.d('MPV-audio: file-loaded (open)');
      return;
    }
    if (!_hasArmedNext) {
      appLogger.d('MPV-audio: file-loaded (nothing armed, ignored)');
      return;
    }

    final uri = _armedNextUri;
    _hasArmedNext = false;
    _armedNextUri = null;
    appLogger.d('MPV-audio: transition (file-loaded) → playlist-remove 0, ${_uriTail(uri ?? '')}');
    unawaited(command(['playlist-remove', '0']));
    if (uri != null) trackTransitionController.add(uri);
  }

  @override
  Future<void> selectAudioTrack(AudioTrack track) async {
    await setProperty('aid', track.id);
  }

  @override
  Future<void> selectSubtitleTrack(SubtitleTrack track) async {
    await setProperty('sid', track.id);
  }

  @override
  Future<void> selectSecondarySubtitleTrack(SubtitleTrack track) async {
    await setProperty('secondary-sid', track.id);
  }

  @override
  Future<void> addSubtitleTrack({required String uri, String? title, String? language, bool select = false}) async {
    final args = ['sub-add', uri, select ? 'select' : 'auto'];
    if (title != null) args.add('title=$title');
    if (language != null) args.add('lang=$language');
    await command(args);
  }

  @override
  Future<void> setVolume(double volume) async {
    await setProperty('volume', volume.toString());
    if (!disposed) setVolumeState(volume);
  }

  @override
  Future<void> setRate(double rate) async {
    // mpv cannot scaletempo compressed (spdif) audio and silently keeps
    // playing at 1x, so suspend passthrough while the rate is not 1.0.
    _currentRate = rate;
    if (_passthroughActive && rate != 1.0) {
      await _applyPassthrough(false);
    }
    await setProperty('speed', rate.toString());
    if (_passthroughRequested && !_passthroughActive && rate == 1.0 && !_downmixEnabled) {
      await _applyPassthrough(true);
    }
  }

  @override
  Future<void> setAudioDevice(AudioDevice device) async {
    await setProperty('audio-device', device.name);
  }

  @override
  Future<void> setProperty(String name, String value) async {
    if (disposed) return;
    if ((Platform.isIOS || Platform.isMacOS) && name == 'dv-conversion-mode') {
      value = _normalizeDvConversionMode(value);
      _dvConversionMode = value;
    }
    if ((Platform.isIOS || Platform.isMacOS) && name == 'dv-conversion-log') {
      value = _normalizeBoolProperty(value);
      _dvConversionLog = value;
    }
    await _ensureInitialized();
    await invoke('setProperty', {'name': name, 'value': value});
  }

  @override
  Future<String?> getProperty(String name) async {
    if (disposed) return null;
    if ((Platform.isIOS || Platform.isMacOS) && name == 'dv-conversion-mode') {
      return _dvConversionMode;
    }
    if ((Platform.isIOS || Platform.isMacOS) && name == 'dv-conversion-log') {
      return _dvConversionLog;
    }
    await _ensureInitialized();
    return await invoke<String>('getProperty', {'name': name});
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    if (disposed || !Platform.isAndroid) return super.getStats();
    await _ensureInitialized();
    final result = await invoke<Map>('getStats');
    return Map<String, dynamic>.from(result ?? const {});
  }

  @override
  Future<void> command(List<String> args) async {
    if (disposed) return;
    await _ensureInitialized();
    await invoke('command', {'args': args});
  }

  @override
  bool get needsDecoderRefreshAfterDisplaySwitch => Platform.isAndroid;

  @override
  Future<void> setDisplayCriteria(MediaDisplayCriteria? criteria, {int extraDelayMs = 0}) async {
    if (disposed || audioOnly || !Platform.isIOS) return;
    await _ensureInitialized();
    await invoke('setDisplayCriteria', {
      'criteria': _effectiveDisplayCriteria(criteria)?.toJson(),
      'extraDelayMs': extraDelayMs,
    });
  }

  @override
  Future<void> setLogLevel(String level) async {
    if (disposed) return;
    await _ensureInitialized();
    await invoke('setLogLevel', {'level': level});
  }

  bool _passthroughRequested = false;
  bool _passthroughActive = false;
  bool _normalizationRequested = false;
  bool _downmixEnabled = false;
  double _currentRate = 1.0;

  @override
  bool get audioPassthroughActive => _passthroughActive;

  /// Codecs the platform can take as a bitstream. On iOS/tvOS compressed
  /// audio goes through the system renderer, which only handles Dolby
  /// Digital (Plus); desktop does real device passthrough for the full list.
  static final String _passthroughCodecs = Platform.isIOS ? 'ac3,eac3' : 'ac3,eac3,dts,dts-hd,truehd';

  @override
  Future<void> setAudioPassthrough(bool enabled) async {
    _passthroughRequested = enabled;
    // Deferred until the rate returns to 1.0 (see setRate) and the stereo
    // downmix ends (see setAudioDownmix).
    if (enabled && (_currentRate != 1.0 || _downmixEnabled)) return;
    await _applyPassthrough(enabled);
  }

  Future<void> _applyPassthrough(bool enabled) async {
    _passthroughActive = enabled;
    // loudnorm decodes to PCM, which defeats bitstream passthrough; the
    // filter yields while passthrough is active and returns when it ends.
    if (enabled && _normalizationRequested) {
      await super.setAudioNormalization(false);
    }
    await setProperty('audio-spdif', enabled ? _passthroughCodecs : '');
    // audio-exclusive redirects coreaudio to coreaudio_exclusive on macOS
    // (and exclusive WASAPI on Windows); on iOS/tvOS it is set once at
    // playback start and must not be clobbered here.
    if (!Platform.isIOS) {
      await setProperty('audio-exclusive', enabled ? 'yes' : 'no');
    }
    if (!enabled && _normalizationRequested) {
      await super.setAudioNormalization(true);
    }
  }

  @override
  Future<void> setAudioNormalization(bool enabled) async {
    _normalizationRequested = enabled;
    if (enabled && _passthroughActive) return; // deferred until passthrough ends
    await super.setAudioNormalization(enabled);
  }

  @override
  Future<void> setAudioDownmix({required bool enabled, required int centerBoostDb, required bool normalize}) async {
    _downmixEnabled = enabled;
    // spdif bypasses the filter chain entirely; passthrough yields while a
    // stereo downmix is forced and returns when it is disabled.
    if (enabled && _passthroughActive) {
      await _applyPassthrough(false);
    }
    await super.setAudioDownmix(enabled: enabled, centerBoostDb: centerBoostDb, normalize: normalize);
    if (!enabled && _passthroughRequested && !_passthroughActive && _currentRate == 1.0) {
      await _applyPassthrough(true);
    }
  }

  @override
  Future<void> updateFrame() async {
    if (disposed || !initialized) return;
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux) {
      await invoke('updateFrame');
    }
  }

  @override
  Future<bool> setVideoFrameRate(
    double fps,
    int durationMs, {
    int extraDelayMs = 0,
    int videoWidth = 0,
    int videoHeight = 0,
  }) async {
    if (!Platform.isAndroid || disposed || !initialized) return false;
    final result = await invoke<bool>('setVideoFrameRate', {
      'fps': fps,
      'duration': durationMs,
      'extraDelayMs': extraDelayMs,
      'videoWidth': videoWidth,
      'videoHeight': videoHeight,
    });
    return result ?? false;
  }

  @override
  Future<void> clearVideoFrameRate() async {
    if (!Platform.isAndroid || disposed || !initialized) return;
    await invoke('clearVideoFrameRate');
  }

  @override
  Future<bool> requestAudioFocus() async {
    if (disposed) return false;
    if (!Platform.isAndroid) return true;
    await _ensureInitialized();
    return await invoke<bool>('requestAudioFocus') ?? false;
  }

  @override
  Future<void> abandonAudioFocus() async {
    if (!Platform.isAndroid || disposed || !initialized) return;
    await invoke('abandonAudioFocus');
  }
}
