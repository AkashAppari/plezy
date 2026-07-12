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
