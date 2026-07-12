import 'dart:async' show Completer;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/mpv/models.dart';
import 'package:plezy/mpv/player/player_native.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/mock_player_channels.dart';
import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  test('MPV coalesces concurrent Dart initialization requests', () async {
    final initialize = Completer<bool>();
    final calls = <MethodCall>[];

    await withMockPlayerChannels(
      methodChannelName: 'com.plezy/mpv_player',
      eventChannelName: 'com.plezy/mpv_player/events',
      methodHandler: (call) {
        calls.add(call);
        if (call.method == 'initialize') return initialize.future;
        return Future.value(null);
      },
      testBody: () async {
        final player = PlayerNative();
        try {
          final logLevel = player.setLogLevel('warn');
          final command = player.command(['stop']);
          await Future<void>.delayed(Duration.zero);

          expect(calls.where((call) => call.method == 'initialize'), hasLength(1));

          initialize.complete(true);
          await Future.wait([logLevel, command]);

          expect(calls.where((call) => call.method == 'initialize'), hasLength(1));
          expect(calls.where((call) => call.method == 'setLogLevel'), hasLength(1));
          expect(calls.where((call) => call.method == 'command'), hasLength(1));
        } finally {
          if (!initialize.isCompleted) initialize.complete(true);
          await player.dispose();
        }
      },
    );
  });

  test('Android command failure reaches seek recovery', () async {
    await withMockPlayerChannels(
      methodChannelName: 'com.plezy/mpv_player',
      eventChannelName: 'com.plezy/mpv_player/events',
      methodHandler: (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'command') {
          throw PlatformException(code: 'COMMAND_FAILED', message: 'mpv command failed');
        }
        return null;
      },
      testBody: () async {
        final player = PlayerNative();
        try {
          await player.seek(const Duration(seconds: 12));
          expect(player.state.position, Duration.zero);
        } finally {
          await player.dispose();
        }
      },
    );
  });

  test('Android setLogLevel failure is exposed to Dart', () async {
    await withMockPlayerChannels(
      methodChannelName: 'com.plezy/mpv_player',
      eventChannelName: 'com.plezy/mpv_player/events',
      methodHandler: (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'setLogLevel') {
          throw PlatformException(code: 'UNSUPPORTED');
        }
        return null;
      },
      testBody: () async {
        final player = PlayerNative();
        try {
          await expectLater(
            player.setLogLevel('warn'),
            throwsA(isA<PlatformException>().having((error) => error.code, 'code', 'UNSUPPORTED')),
          );
        } finally {
          await player.dispose();
        }
      },
    );
  });

  test('audio setLogLevel uses the dedicated native channel', () async {
    MethodCall? logLevelCall;
    await withMockPlayerChannels(
      methodChannelName: 'com.plezy/mpv_audio_player',
      eventChannelName: 'com.plezy/mpv_audio_player/events',
      methodHandler: (call) async {
        if (call.method == 'initialize') return true;
        if (call.method == 'setLogLevel') logLevelCall = call;
        return null;
      },
      testBody: () async {
        final player = PlayerNative.audio();
        try {
          await player.setLogLevel('v');
          expect(logLevelCall?.arguments, {'level': 'v'});
        } finally {
          await player.dispose();
        }
      },
    );
  });

  test('Android mpv end-file error preserves native diagnostic message', () async {
    await withMockPlayerChannels(
      methodChannelName: 'com.plezy/mpv_player',
      eventChannelName: 'com.plezy/mpv_player/events',
      testBody: () async {
        final player = PlayerNative();
        final error = player.streams.error.first;
        try {
          player.handlePlayerEvent('end-file', {'reason': 4, 'message': 'Invalid data found when processing input'});

          await expectLater(
            error,
            completion(
              isA<PlayerError>().having(
                (value) => value.message,
                'message',
                'Invalid data found when processing input',
              ),
            ),
          );
        } finally {
          await player.dispose();
        }
      },
    );
  });

  test('Android mpv legacy end-file error keeps playback error fallback', () async {
    await withMockPlayerChannels(
      methodChannelName: 'com.plezy/mpv_player',
      eventChannelName: 'com.plezy/mpv_player/events',
      testBody: () async {
        final player = PlayerNative();
        final error = player.streams.error.first;
        try {
          player.handlePlayerEvent('end-file', {'reason': 4});

          await expectLater(
            error,
            completion(isA<PlayerError>().having((value) => value.message, 'message', 'Playback error')),
          );
        } finally {
          await player.dispose();
        }
      },
    );
  });
}
