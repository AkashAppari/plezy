import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../utils/app_logger.dart';
import '../utils/key_event_simulator.dart' as key_sim;
import 'gamepad_service.dart';

/// Bridges tvOS touch-surface events from Apple's iOS Remote app into the
/// focus-tree key events Plezy already handles for D-pad navigation.
class AppleTvRemoteTouchService {
  static const String _channelName = 'flutter/gamepadtouchevent';
  static const double defaultSwipeThreshold = 180;
  static const Duration defaultSwipeRepeatInterval = Duration(milliseconds: 140);
  static const Duration defaultClickAfterDirectionSuppression = Duration(milliseconds: 220);

  static final AppleTvRemoteTouchService instance = AppleTvRemoteTouchService();

  final BasicMessageChannel<dynamic> _channel;
  final void Function(LogicalKeyboardKey logicalKey) _simulateKeyPress;
  final VoidCallback _scheduleFrame;
  final DateTime Function() _now;
  final GamepadDuplicateInputGuard _duplicateInputGuard;
  final double swipeThreshold;
  final Duration swipeRepeatInterval;
  final Duration clickAfterDirectionSuppression;

  bool _listening = false;
  bool _nativeKeyHandlerRegistered = false;
  bool _touchActive = false;
  double _anchorX = 0;
  double _anchorY = 0;
  DateTime? _lastSwipeAt;
  DateTime? _lastDirectionalInputAt;
  DateTime? _lastSyntheticSelectAt;

  AppleTvRemoteTouchService({
    BasicMessageChannel<dynamic>? channel,
    void Function(LogicalKeyboardKey logicalKey)? simulateKeyPress,
    VoidCallback? scheduleFrame,
    DateTime Function()? now,
    GamepadDuplicateInputGuard? duplicateInputGuard,
    Duration duplicateSuppressionWindow = GamepadDuplicateInputGuard.defaultSuppressionWindow,
    this.swipeThreshold = defaultSwipeThreshold,
    this.swipeRepeatInterval = defaultSwipeRepeatInterval,
    this.clickAfterDirectionSuppression = defaultClickAfterDirectionSuppression,
  }) : _channel = channel ?? const BasicMessageChannel<dynamic>(_channelName, JSONMessageCodec()),
       _simulateKeyPress = simulateKeyPress ?? key_sim.simulateKeyPress,
       _scheduleFrame = scheduleFrame ?? key_sim.scheduleFrameIfIdle,
       _now = now ?? DateTime.now,
       _duplicateInputGuard =
           duplicateInputGuard ?? GamepadDuplicateInputGuard(now: now, suppressionWindow: duplicateSuppressionWindow);

  void start() {
    if (_listening) return;
    _channel.setMessageHandler(handleMessage);
    _registerNativeKeyHandler();
    _listening = true;
    appLogger.i('AppleTvRemoteTouchService: Listening for tvOS touch remote events');
  }

  void stop() {
    if (!_listening) return;
    _channel.setMessageHandler(null);
    _unregisterNativeKeyHandler();
    _duplicateInputGuard.clear();
    _resetTouch();
    _listening = false;
  }

  bool handleNativeKeyEvent(KeyEvent event) {
    _log('native ${_eventTypeName(event)} logical=${_keyName(event.logicalKey)}');
    if (event is KeyDownEvent && _isDirectionalKey(event.logicalKey)) {
      _lastDirectionalInputAt = _now();
    }
    return _duplicateInputGuard.handleNativeKeyEvent(event);
  }

  Future<void> handleMessage(dynamic arguments) async {
    if (arguments is! Map) {
      _log('ignore message reason=not-map valueType=${arguments.runtimeType}');
      return;
    }

    final type = arguments['type'];
    if (type is! String) {
      _log('ignore message reason=missing-type args=$arguments');
      return;
    }

    _logTouch(type, arguments);

    switch (type) {
      case 'started':
        final position = _positionFrom(arguments);
        if (position == null) return;
        _startTouch(position.$1, position.$2);
      case 'move':
        final position = _positionFrom(arguments);
        if (position == null) return;
        _moveTouch(position.$1, position.$2);
      case 'ended':
        final position = _positionFrom(arguments);
        if (position == null) {
          _resetTouch();
          return;
        }
        _moveTouch(position.$1, position.$2);
        _resetTouch();
      case 'cancelled':
        _resetTouch();
      case 'click_e':
        _emitSelect();
      case 'click_s':
      case 'loc':
        break;
      default:
        break;
    }
  }

  (double, double)? _positionFrom(Map<dynamic, dynamic> arguments) {
    final x = _toDouble(arguments['x']);
    final y = _toDouble(arguments['y']);
    if (x == null || y == null) return null;
    return (x, y);
  }

  double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return null;
  }

  void _startTouch(double x, double y) {
    _touchActive = true;
    _anchorX = x;
    _anchorY = y;
    _lastSwipeAt = null;
  }

  void _moveTouch(double x, double y) {
    if (!_touchActive) {
      _log('ignore touch-move reason=no-active-touch x=${_formatDouble(x)} y=${_formatDouble(y)}');
      return;
    }

    final deltaX = _anchorX - x;
    final deltaY = _anchorY - y;
    if (deltaX.abs() < swipeThreshold && deltaY.abs() < swipeThreshold) return;

    final now = _now();
    final lastSwipeAt = _lastSwipeAt;
    if (lastSwipeAt != null && now.difference(lastSwipeAt) < swipeRepeatInterval) {
      final age = now.difference(lastSwipeAt).inMilliseconds;
      _log(
        'suppress swipe reason=repeat-cooldown age=${age}ms dx=${_formatDouble(deltaX)} dy=${_formatDouble(deltaY)}',
      );
      return;
    }

    final logicalKey = deltaX.abs() >= deltaY.abs()
        ? (deltaX >= 0 ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)
        : (deltaY >= 0 ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown);

    _emitKey(logicalKey, source: 'swipe', detail: 'dx=${_formatDouble(deltaX)} dy=${_formatDouble(deltaY)}');
    _anchorX = x;
    _anchorY = y;
    _lastSwipeAt = now;
  }

  void _emitSelect() {
    final now = _now();
    final lastDirectionalInputAt = _lastDirectionalInputAt;
    if (lastDirectionalInputAt != null && now.difference(lastDirectionalInputAt) <= clickAfterDirectionSuppression) {
      final age = now.difference(lastDirectionalInputAt).inMilliseconds;
      _log('suppress key=${_keyName(LogicalKeyboardKey.enter)} source=click_e reason=recent-direction age=${age}ms');
      return;
    }

    final lastSyntheticSelectAt = _lastSyntheticSelectAt;
    if (lastSyntheticSelectAt != null && now.difference(lastSyntheticSelectAt).abs() <= duplicateSuppressionWindow) {
      final age = now.difference(lastSyntheticSelectAt).abs().inMilliseconds;
      _log(
        'suppress key=${_keyName(LogicalKeyboardKey.enter)} source=click_e reason=recent-synthetic-select age=${age}ms',
      );
      return;
    }

    if (_emitKey(LogicalKeyboardKey.enter, source: 'click_e')) {
      _lastSyntheticSelectAt = now;
    }
  }

  bool _emitKey(LogicalKeyboardKey logicalKey, {required String source, String? detail}) {
    if (_duplicateInputGuard.shouldSuppressSyntheticKey(logicalKey)) {
      _log('suppress key=${_keyName(logicalKey)} source=$source reason=recent-native');
      return false;
    }

    _setTraditionalFocusHighlight();
    _scheduleFrame();
    _log('emit key=${_keyName(logicalKey)} source=$source${detail == null ? '' : ' $detail'}');
    if (_isDirectionalKey(logicalKey)) {
      _lastDirectionalInputAt = _now();
    }
    _simulateKeyPress(logicalKey);
    return true;
  }

  Duration get duplicateSuppressionWindow => _duplicateInputGuard.suppressionWindow;

  void _resetTouch() {
    _touchActive = false;
    _lastSwipeAt = null;
  }

  void _registerNativeKeyHandler() {
    if (_nativeKeyHandlerRegistered) return;
    HardwareKeyboard.instance.addHandler(handleNativeKeyEvent);
    _nativeKeyHandlerRegistered = true;
  }

  void _unregisterNativeKeyHandler() {
    if (!_nativeKeyHandlerRegistered) return;
    HardwareKeyboard.instance.removeHandler(handleNativeKeyEvent);
    _nativeKeyHandlerRegistered = false;
  }

  void _setTraditionalFocusHighlight() {
    if (FocusManager.instance.highlightStrategy != FocusHighlightStrategy.alwaysTraditional) {
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    }
  }

  void _logTouch(String type, Map<dynamic, dynamic> arguments) {
    final x = _toDouble(arguments['x']);
    final y = _toDouble(arguments['y']);
    _log('touch type=$type x=${_formatDouble(x)} y=${_formatDouble(y)} active=$_touchActive');
  }

  void _log(String message) {
    appLogger.d('AppleTvRemoteTouchService: $message');
  }

  String _eventTypeName(KeyEvent event) {
    if (event is KeyDownEvent) return 'keydown';
    if (event is KeyRepeatEvent) return 'keyrepeat';
    if (event is KeyUpEvent) return 'keyup';
    return event.runtimeType.toString();
  }

  String _keyName(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) return 'arrowUp';
    if (key == LogicalKeyboardKey.arrowDown) return 'arrowDown';
    if (key == LogicalKeyboardKey.arrowLeft) return 'arrowLeft';
    if (key == LogicalKeyboardKey.arrowRight) return 'arrowRight';
    if (key == LogicalKeyboardKey.enter) return 'enter';
    if (key == LogicalKeyboardKey.select) return 'select';
    if (key == LogicalKeyboardKey.gameButtonA) return 'gameButtonA';
    if (key == LogicalKeyboardKey.escape) return 'escape';
    return '0x${key.keyId.toRadixString(16)}';
  }

  bool _isDirectionalKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }

  String _formatDouble(double? value) {
    if (value == null) return 'n/a';
    return value.toStringAsFixed(1);
  }
}
