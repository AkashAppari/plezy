import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/platform_detector.dart';
import '../widgets/tv_virtual_keyboard.dart';
import 'dpad_navigator.dart';

bool _usesTvKeyboard(bool enableTvKeyboard) => enableTvKeyboard && PlatformDetector.isAppleTV();

String? _keyboardHint(InputDecoration? decoration) => decoration?.hintText ?? decoration?.labelText;

KeyEventResult _handleInputKey({
  required TextEditingController controller,
  required bool usesTvKeyboard,
  required bool enabled,
  required VoidCallback openKeyboard,
  required KeyEvent event,
  TextInputType? keyboardType,
  TextInputAction? textInputAction,
  List<TextInputFormatter>? inputFormatters,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  VoidCallback? onEditingComplete,
  int? maxLength,
  int? maxLines,
  VoidCallback? onSelect,
  VoidCallback? onBack,
  VoidCallback? onNavigateLeft,
  VoidCallback? onNavigateRight,
  VoidCallback? onNavigateUp,
  VoidCallback? onNavigateDown,
}) {
  final key = event.logicalKey;

  if (usesTvKeyboard && enabled && event.isTvSelectEvent) {
    if (event is KeyDownEvent) openKeyboard();
    return KeyEventResult.handled;
  }

  if (usesTvKeyboard && enabled && event.isPhysicalKeyboardEvent) {
    final result = _handleTvHardwareKeyboardKey(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      maxLength: maxLength,
      maxLines: maxLines,
      event: event,
    );
    if (result != KeyEventResult.ignored) return result;
  }

  if (onBack != null && key.isBackKey) {
    if (event is KeyDownEvent) onBack();
    return KeyEventResult.handled;
  }

  // Enter/numpad enter are left to TextField.onSubmitted. Handle only
  // non-text submit keys that TV remotes/gamepads may send while editing.
  if (!usesTvKeyboard &&
      onSelect != null &&
      (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.gameButtonA)) {
    if (event is KeyDownEvent) onSelect();
    return KeyEventResult.handled;
  }

  if (!event.isActionable) return KeyEventResult.ignored;

  if (key.isUpKey && onNavigateUp != null) {
    onNavigateUp();
    return KeyEventResult.handled;
  }
  if (key.isDownKey && onNavigateDown != null) {
    onNavigateDown();
    return KeyEventResult.handled;
  }

  final sel = controller.selection;
  if (sel.isCollapsed) {
    if (key.isLeftKey && sel.baseOffset == 0 && onNavigateLeft != null) {
      onNavigateLeft();
      return KeyEventResult.handled;
    }
    if (key.isRightKey && sel.baseOffset == controller.text.length && onNavigateRight != null) {
      onNavigateRight();
      return KeyEventResult.handled;
    }
  }

  return KeyEventResult.ignored;
}

KeyEventResult _handleTvHardwareKeyboardKey({
  required TextEditingController controller,
  required KeyEvent event,
  TextInputType? keyboardType,
  TextInputAction? textInputAction,
  List<TextInputFormatter>? inputFormatters,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  VoidCallback? onEditingComplete,
  int? maxLength,
  int? maxLines,
}) {
  final key = event.logicalKey;

  if (event.isPhysicalKeyboardEnter) {
    if (event is KeyDownEvent) {
      if (_isMultilineTextInput(keyboardType: keyboardType, maxLines: maxLines)) {
        _insertText(
          controller: controller,
          text: '\n',
          inputFormatters: inputFormatters,
          maxLength: maxLength,
          onChanged: onChanged,
        );
      } else {
        _submitTextInput(
          controller: controller,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          onEditingComplete: onEditingComplete,
        );
      }
    }
    return KeyEventResult.handled;
  }

  if (!event.isActionable) return KeyEventResult.ignored;

  if (key == LogicalKeyboardKey.backspace) {
    _backspace(controller: controller, inputFormatters: inputFormatters, maxLength: maxLength, onChanged: onChanged);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.delete) {
    _deleteForward(
      controller: controller,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      onChanged: onChanged,
    );
    return KeyEventResult.handled;
  }

  if (key.isLeftKey || key.isRightKey) {
    return _moveCaretHorizontally(controller, key.isLeftKey ? -1 : 1);
  }

  final character = event.character;
  if (character != null && character.isNotEmpty && !key.isNavigationKey && !_isControlCharacter(character)) {
    _insertText(
      controller: controller,
      text: character,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      onChanged: onChanged,
    );
    return KeyEventResult.handled;
  }

  return KeyEventResult.ignored;
}

bool _isMultilineTextInput({TextInputType? keyboardType, int? maxLines}) {
  return keyboardType?.index == TextInputType.multiline.index || (maxLines != null && maxLines != 1);
}

bool _isControlCharacter(String text) {
  return text.runes.every((codeUnit) => codeUnit < 0x20 || codeUnit == 0x7f);
}

KeyEventResult _moveCaretHorizontally(TextEditingController controller, int delta) {
  final value = controller.value;
  final selection = value.selection;
  if (!selection.isValid) {
    controller.selection = TextSelection.collapsed(offset: value.text.length);
    return KeyEventResult.handled;
  }

  if (!selection.isCollapsed) {
    final offset = delta < 0
        ? (selection.start < selection.end ? selection.start : selection.end)
        : (selection.start > selection.end ? selection.start : selection.end);
    controller.selection = TextSelection.collapsed(offset: offset);
    return KeyEventResult.handled;
  }

  final nextOffset = selection.extentOffset + delta;
  if (nextOffset < 0 || nextOffset > value.text.length) return KeyEventResult.ignored;
  controller.selection = TextSelection.collapsed(offset: nextOffset);
  return KeyEventResult.handled;
}

void _submitTextInput({
  required TextEditingController controller,
  required TextInputAction? textInputAction,
  ValueChanged<String>? onSubmitted,
  VoidCallback? onEditingComplete,
}) {
  if (onEditingComplete != null) {
    onEditingComplete();
  } else {
    _defaultEditingComplete(textInputAction);
  }
  onSubmitted?.call(controller.text);
}

void _defaultEditingComplete(TextInputAction? textInputAction) {
  final focus = FocusManager.instance.primaryFocus;
  switch (textInputAction) {
    case TextInputAction.next:
      focus?.nextFocus();
    case TextInputAction.previous:
      focus?.previousFocus();
    default:
      focus?.unfocus();
  }
}

void _insertText({
  required TextEditingController controller,
  required String text,
  List<TextInputFormatter>? inputFormatters,
  int? maxLength,
  ValueChanged<String>? onChanged,
}) {
  final value = controller.value;
  final selection = value.selection;
  final start = selection.isValid
      ? (selection.start < selection.end ? selection.start : selection.end)
      : value.text.length;
  final end = selection.isValid
      ? (selection.start > selection.end ? selection.start : selection.end)
      : value.text.length;
  final newText = value.text.replaceRange(start, end, text);
  _replaceTextValue(
    controller: controller,
    nextValue: value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
    ),
    inputFormatters: inputFormatters,
    maxLength: maxLength,
    onChanged: onChanged,
  );
}

void _backspace({
  required TextEditingController controller,
  List<TextInputFormatter>? inputFormatters,
  int? maxLength,
  ValueChanged<String>? onChanged,
}) {
  final value = controller.value;
  final selection = value.selection;
  final start = selection.isValid
      ? (selection.start < selection.end ? selection.start : selection.end)
      : value.text.length;
  final end = selection.isValid
      ? (selection.start > selection.end ? selection.start : selection.end)
      : value.text.length;
  if (start != end) {
    _replaceTextRange(
      controller,
      start,
      end,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      onChanged: onChanged,
    );
    return;
  }
  if (start == 0) return;
  _replaceTextRange(
    controller,
    start - 1,
    start,
    inputFormatters: inputFormatters,
    maxLength: maxLength,
    onChanged: onChanged,
  );
}

void _deleteForward({
  required TextEditingController controller,
  List<TextInputFormatter>? inputFormatters,
  int? maxLength,
  ValueChanged<String>? onChanged,
}) {
  final value = controller.value;
  final selection = value.selection;
  final start = selection.isValid
      ? (selection.start < selection.end ? selection.start : selection.end)
      : value.text.length;
  final end = selection.isValid
      ? (selection.start > selection.end ? selection.start : selection.end)
      : value.text.length;
  if (start != end) {
    _replaceTextRange(
      controller,
      start,
      end,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      onChanged: onChanged,
    );
    return;
  }
  if (start >= value.text.length) return;
  _replaceTextRange(
    controller,
    start,
    start + 1,
    inputFormatters: inputFormatters,
    maxLength: maxLength,
    onChanged: onChanged,
  );
}

void _replaceTextRange(
  TextEditingController controller,
  int start,
  int end, {
  List<TextInputFormatter>? inputFormatters,
  int? maxLength,
  ValueChanged<String>? onChanged,
}) {
  final value = controller.value;
  _replaceTextValue(
    controller: controller,
    nextValue: value.copyWith(
      text: value.text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
      composing: TextRange.empty,
    ),
    inputFormatters: inputFormatters,
    maxLength: maxLength,
    onChanged: onChanged,
  );
}

void _replaceTextValue({
  required TextEditingController controller,
  required TextEditingValue nextValue,
  List<TextInputFormatter>? inputFormatters,
  int? maxLength,
  ValueChanged<String>? onChanged,
}) {
  final previousValue = controller.value;
  var formattedValue = nextValue;
  final formatters = [
    ...?inputFormatters,
    if (maxLength != null && maxLength > 0) LengthLimitingTextInputFormatter(maxLength),
  ];
  for (final formatter in formatters) {
    formattedValue = formatter.formatEditUpdate(previousValue, formattedValue);
  }

  controller.value = formattedValue;
  if (formattedValue.text != previousValue.text) {
    onChanged?.call(formattedValue.text);
  }
}

abstract class _FocusableTextInputBase extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final VoidCallback? onSelect;
  final VoidCallback? onBack;
  final bool autofocus;
  final bool enabled;
  final bool enableTvKeyboard;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool? enableInteractiveSelection;
  final int? maxLength;
  final int? maxLines;
  final int? minLines;
  final TextAlign textAlign;
  final TextCapitalization textCapitalization;
  final TextStyle? style;

  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;

  const _FocusableTextInputBase({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onSelect,
    this.onBack,
    this.autofocus = false,
    this.enabled = true,
    this.enableTvKeyboard = true,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.enableInteractiveSelection,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.textAlign = TextAlign.start,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  bool get _hasTvKeyboard => _usesTvKeyboard(enableTvKeyboard);

  void _showTvKeyboard(BuildContext context) {
    if (!enabled) return;
    showTvVirtualKeyboard(
      context: context,
      controller: controller,
      hintText: _keyboardHint(decoration),
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      maxLength: maxLength,
      maxLines: maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onAction: onEditingComplete ?? onSelect,
    );
  }

  KeyEventResult _handleKey(BuildContext context, FocusNode _, KeyEvent event) {
    return _handleInputKey(
      controller: controller,
      usesTvKeyboard: _hasTvKeyboard,
      enabled: enabled,
      openKeyboard: () => _showTvKeyboard(context),
      event: event,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      maxLength: maxLength,
      maxLines: maxLines,
      onSelect: onSelect,
      onBack: onBack,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
    );
  }

  Widget buildFocusableInput(BuildContext context, Widget Function(bool usesTvKeyboard) builder) {
    final usesTvKeyboard = _hasTvKeyboard;
    return Focus(
      // This wrapper only intercepts key events bubbling from the input; the
      // real TextField/TextFormField must remain the traversable focus target.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) => _handleKey(context, node, event),
      child: builder(usesTvKeyboard),
    );
  }
}

/// A [TextField] wrapper that exposes D-pad navigation callbacks with
/// caret-aware edge escapes — so LEFT at the start of the field and RIGHT
/// at the end escape to neighbouring focus targets instead of bouncing
/// against the caret boundary, while UP/DOWN always escape.
///
/// Collapsed selection only: if text is selected, LEFT/RIGHT fall through
/// to the TextField's default caret movement.
class FocusableTextField extends _FocusableTextInputBase {
  const FocusableTextField({
    super.key,
    required super.controller,
    super.focusNode,
    super.decoration,
    super.keyboardType,
    super.textInputAction,
    super.inputFormatters,
    super.onChanged,
    super.onSubmitted,
    super.onEditingComplete,
    super.onSelect,
    super.onBack,
    super.autofocus,
    super.enabled,
    super.enableTvKeyboard,
    super.obscureText,
    super.autocorrect,
    super.enableSuggestions,
    super.enableInteractiveSelection,
    super.maxLength,
    super.maxLines,
    super.minLines,
    super.textAlign,
    super.textCapitalization,
    super.style,
    super.onNavigateLeft,
    super.onNavigateRight,
    super.onNavigateUp,
    super.onNavigateDown,
  });

  @override
  Widget build(BuildContext context) {
    return buildFocusableInput(
      context,
      (usesTvKeyboard) => TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        decoration: decoration,
        keyboardType: usesTvKeyboard ? TextInputType.none : keyboardType,
        textInputAction: textInputAction,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onEditingComplete: onEditingComplete,
        autofocus: autofocus,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        obscureText: obscureText,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: minLines,
        textAlign: textAlign,
        textCapitalization: textCapitalization,
        style: style,
        readOnly: usesTvKeyboard,
        showCursor: usesTvKeyboard ? true : null,
        enableInteractiveSelection: usesTvKeyboard ? false : enableInteractiveSelection,
        onTap: usesTvKeyboard ? () => _showTvKeyboard(context) : null,
      ),
    );
  }
}

class FocusableTextFormField extends _FocusableTextInputBase {
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;
  final FormFieldSetter<String>? onSaved;

  const FocusableTextFormField({
    super.key,
    required super.controller,
    super.focusNode,
    super.decoration,
    super.keyboardType,
    super.textInputAction,
    super.inputFormatters,
    super.onChanged,
    this.onFieldSubmitted,
    super.onEditingComplete,
    super.onSelect,
    super.onBack,
    this.validator,
    this.autovalidateMode,
    this.onSaved,
    super.autofocus,
    super.enabled,
    super.enableTvKeyboard,
    super.obscureText,
    super.autocorrect,
    super.enableSuggestions,
    super.enableInteractiveSelection,
    super.maxLength,
    super.maxLines,
    super.minLines,
    super.textAlign,
    super.textCapitalization,
    super.style,
    super.onNavigateLeft,
    super.onNavigateRight,
    super.onNavigateUp,
    super.onNavigateDown,
  }) : super(onSubmitted: onFieldSubmitted);

  @override
  Widget build(BuildContext context) {
    return buildFocusableInput(
      context,
      (usesTvKeyboard) => TextFormField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        decoration: decoration,
        keyboardType: usesTvKeyboard ? TextInputType.none : keyboardType,
        textInputAction: textInputAction,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onFieldSubmitted: onFieldSubmitted,
        onEditingComplete: onEditingComplete,
        validator: validator,
        autovalidateMode: autovalidateMode,
        onSaved: onSaved,
        autofocus: autofocus,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        obscureText: obscureText,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: minLines,
        textAlign: textAlign,
        textCapitalization: textCapitalization,
        style: style,
        readOnly: usesTvKeyboard,
        showCursor: usesTvKeyboard ? true : null,
        enableInteractiveSelection: usesTvKeyboard ? false : enableInteractiveSelection,
        onTap: usesTvKeyboard ? () => _showTvKeyboard(context) : null,
      ),
    );
  }
}
