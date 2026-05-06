import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focusable_text_field.dart';

void main() {
  testWidgets('tab traversal focuses the text form field instead of its key handler wrapper', (tester) async {
    final controller = TextEditingController();
    final fieldFocusNode = FocusNode(debugLabel: 'server_url_field');
    final buttonFocusNode = FocusNode(debugLabel: 'find_server_button');
    addTearDown(controller.dispose);
    addTearDown(fieldFocusNode.dispose);
    addTearDown(buttonFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              FocusableTextFormField(
                controller: controller,
                focusNode: fieldFocusNode,
                decoration: const InputDecoration(labelText: 'Server URL'),
              ),
              FilledButton(focusNode: buttonFocusNode, onPressed: () {}, child: const Text('Find server')),
            ],
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(fieldFocusNode.hasPrimaryFocus, isTrue);
    expect(buttonFocusNode.hasFocus, isFalse);
  });

  testWidgets('focused text form field still receives wrapper select handling', (tester) async {
    final controller = TextEditingController();
    final fieldFocusNode = FocusNode(debugLabel: 'server_url_field');
    var selects = 0;
    addTearDown(controller.dispose);
    addTearDown(fieldFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusableTextFormField(controller: controller, focusNode: fieldFocusNode, onSelect: () => selects++),
        ),
      ),
    );

    fieldFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(selects, 1);
  });
}
