import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focusable_slider.dart';

void main() {
  testWidgets('D-pad adjustment reports a complete persisted change', (tester) async {
    final focusNode = FocusNode(debugLabel: 'slider');
    addTearDown(focusNode.dispose);
    final starts = <double>[];
    final changes = <double>[];
    final ends = <double>[];
    var value = 0.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FocusableSlider(
              focusNode: focusNode,
              value: value,
              min: 0,
              max: 10,
              divisions: 10,
              onChangeStart: starts.add,
              onChanged: (next) {
                changes.add(next);
                setState(() => value = next);
              },
              onChangeEnd: ends.add,
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(starts, [0.0]);
    expect(changes, [1.0]);
    expect(ends, [1.0]);
    expect(value, 1.0);
  });

  testWidgets('SELECT invokes the slider action once', (tester) async {
    final focusNode = FocusNode(debugLabel: 'slider');
    addTearDown(focusNode.dispose);
    var selected = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusableSlider(focusNode: focusNode, value: 0, onChanged: (_) {}, onSelect: () => selected++),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(selected, 1);
  });
}
