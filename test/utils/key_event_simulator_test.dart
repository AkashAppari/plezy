import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/key_event_simulator.dart';

void main() {
  testWidgets('simulateKeyPress dispatches directional pad key events', (tester) async {
    final events = <KeyEvent>[];
    late BuildContext focusContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            events.add(event);
            return KeyEventResult.handled;
          },
          child: Builder(
            builder: (context) {
              focusContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    Focus.of(focusContext).requestFocus();
    await tester.pump();
    expect(Focus.of(focusContext).hasPrimaryFocus, isTrue);

    scheduleFrameIfIdle();
    simulateKeyPress(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();

    expect(events, hasLength(2));
    expect(events.map((event) => event.deviceType), everyElement(ui.KeyEventDeviceType.directionalPad));
  });
}
