import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/apple_tv_remote_touch_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppleTvRemoteTouchService', () {
    test('emits repeated horizontal swipes only after the repeat interval', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 490);
      await harness.send('move', x: 260, y: 490);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft]);

      harness.advance(const Duration(milliseconds: 141));
      await harness.send('move', x: 260, y: 490);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowLeft]);
    });

    test('uses the dominant vertical axis for swipes', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 540, y: 380);

      expect(harness.keys, [LogicalKeyboardKey.arrowUp]);
    });

    test('short touch without a click event does not emit select', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('ended', x: 512, y: 504);

      expect(harness.keys, isEmpty);
    });

    test('short touch around a native directional key does not emit select', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft));
      await harness.send('started', x: 500, y: 500);
      await harness.send('ended', x: 500, y: 500);

      expect(harness.keys, isEmpty);
    });

    test('swipe end does not also emit select', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);
      await harness.send('ended', x: 380, y: 500);

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft]);
    });

    test('deduplicates touch tap and click fallback select events', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('ended', x: 500, y: 500);
      await harness.send('click_e');

      expect(harness.keys, [LogicalKeyboardKey.enter]);

      harness.advance(const Duration(milliseconds: 121));
      await harness.send('click_e');

      expect(harness.keys, [LogicalKeyboardKey.enter, LogicalKeyboardKey.enter]);
    });

    test('native select suppresses click fallback from physical remote path', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.select));
      await harness.send('click_e');

      expect(harness.keys, isEmpty);

      harness.service.handleNativeKeyEvent(_keyUp(LogicalKeyboardKey.select));
      harness.advance(const Duration(milliseconds: 121));
      await harness.send('click_e');

      expect(harness.keys, [LogicalKeyboardKey.enter]);
    });

    test('recent directional input suppresses click fallback', () async {
      final harness = _Harness();

      harness.service.handleNativeKeyEvent(_keyDown(LogicalKeyboardKey.arrowLeft));
      await harness.send('click_e');

      expect(harness.keys, isEmpty);

      harness.advance(const Duration(milliseconds: 221));
      await harness.send('click_e');

      expect(harness.keys, [LogicalKeyboardKey.enter]);
    });

    test('synthetic swipe suppresses click fallback', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('move', x: 380, y: 500);
      await harness.send('click_e');

      expect(harness.keys, [LogicalKeyboardKey.arrowLeft]);
    });

    test('cancelled touch does not emit select on a later ended message', () async {
      final harness = _Harness();

      await harness.send('started', x: 500, y: 500);
      await harness.send('cancelled');
      await harness.send('ended', x: 500, y: 500);
      await harness.send('loc', x: 1, y: 0);

      expect(harness.keys, isEmpty);
    });
  });
}

class _Harness {
  DateTime now = DateTime(2026, 5, 5, 12);
  final List<LogicalKeyboardKey> keys = [];

  late final AppleTvRemoteTouchService service = AppleTvRemoteTouchService(
    simulateKeyPress: keys.add,
    scheduleFrame: () {},
    now: () => now,
    swipeThreshold: 100,
  );

  Future<void> send(String type, {double x = 0, double y = 0}) {
    return service.handleMessage({'type': type, 'x': x, 'y': y});
  }

  void advance(Duration duration) {
    now = now.add(duration);
  }
}

KeyDownEvent _keyDown(LogicalKeyboardKey logicalKey) {
  return KeyDownEvent(physicalKey: PhysicalKeyboardKey.enter, logicalKey: logicalKey, timeStamp: Duration.zero);
}

KeyUpEvent _keyUp(LogicalKeyboardKey logicalKey) {
  return KeyUpEvent(physicalKey: PhysicalKeyboardKey.enter, logicalKey: logicalKey, timeStamp: Duration.zero);
}
