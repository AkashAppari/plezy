import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focusable_text_field.dart';
import 'package:plezy/utils/platform_detector.dart';

void main() {
  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

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

  testWidgets('tvOS keyboard enter does not open virtual keyboard', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    final controller = TextEditingController();
    final fieldFocusNode = FocusNode(debugLabel: 'search_field');
    String? submitted;
    addTearDown(controller.dispose);
    addTearDown(fieldFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusableTextField(
            controller: controller,
            focusNode: fieldFocusNode,
            onSubmitted: (value) => submitted = value,
          ),
        ),
      ),
    );

    fieldFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(submitted, isEmpty);
  });

  testWidgets('tvOS remote select opens virtual keyboard', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    await _setTvSurfaceSize(tester);
    final controller = TextEditingController();
    final fieldFocusNode = FocusNode(debugLabel: 'search_field');
    addTearDown(controller.dispose);
    addTearDown(fieldFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusableTextField(controller: controller, focusNode: fieldFocusNode),
        ),
      ),
    );

    fieldFocusNode.requestFocus();
    await tester.pump();
    _dispatchKey(
      const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.select,
        logicalKey: LogicalKeyboardKey.select,
        timeStamp: Duration.zero,
        deviceType: ui.KeyEventDeviceType.directionalPad,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('tvOS keyboard-mapped select submits without opening virtual keyboard', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    final controller = TextEditingController(text: 'query');
    final fieldFocusNode = FocusNode(debugLabel: 'search_field');
    String? submitted;
    addTearDown(controller.dispose);
    addTearDown(fieldFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusableTextField(
            controller: controller,
            focusNode: fieldFocusNode,
            onSubmitted: (value) => submitted = value,
          ),
        ),
      ),
    );

    fieldFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(submitted, 'query');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('tvOS text field handles physical keyboard text editing without opening virtual keyboard', (
    tester,
  ) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    final controller = TextEditingController();
    final fieldFocusNode = FocusNode(debugLabel: 'search_field');
    final changes = <String>[];
    addTearDown(controller.dispose);
    addTearDown(fieldFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusableTextField(
            controller: controller,
            focusNode: fieldFocusNode,
            maxLength: 2,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[ab]'))],
            onChanged: changes.add,
          ),
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);

    fieldFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC, character: 'c');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
    await tester.pumpAndSettle();

    expect(controller.text, 'ab');
    expect(changes, ['a', 'ab']);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(controller.text, 'a');

    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('tvOS keyboard enter inserts newline for multiline text field', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    final controller = TextEditingController(text: 'a');
    final fieldFocusNode = FocusNode(debugLabel: 'notes_field');
    addTearDown(controller.dispose);
    addTearDown(fieldFocusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusableTextField(
            controller: controller,
            focusNode: fieldFocusNode,
            keyboardType: TextInputType.multiline,
            maxLines: 2,
          ),
        ),
      ),
    );

    fieldFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.text, 'a\n');
    expect(find.byType(Dialog), findsNothing);
  });
}

Future<void> _setTvSurfaceSize(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

KeyEventResult _dispatchKey(KeyEvent event) {
  FocusNode? node = FocusManager.instance.primaryFocus;
  while (node != null) {
    final result = node.onKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
    if (result == KeyEventResult.handled) return result;
    node = node.parent;
  }
  return KeyEventResult.ignored;
}
