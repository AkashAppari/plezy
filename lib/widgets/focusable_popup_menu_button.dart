import 'package:flutter/material.dart';

import '../focus/focusable_wrapper.dart';

/// A [PopupMenuButton] that can be focused and opened with D-pad select.
class FocusablePopupMenuButton<T> extends StatefulWidget {
  final Widget? icon;
  final String? tooltip;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final GlobalKey<PopupMenuButtonState<T>>? menuKey;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final String? semanticLabel;
  final double borderRadius;
  final bool useBackgroundFocus;
  final bool enableLongPress;

  const FocusablePopupMenuButton({
    super.key,
    this.icon,
    this.tooltip,
    required this.itemBuilder,
    this.onSelected,
    this.menuKey,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.semanticLabel,
    this.borderRadius = 100,
    this.useBackgroundFocus = true,
    this.enableLongPress = true,
  });

  @override
  State<FocusablePopupMenuButton<T>> createState() => _FocusablePopupMenuButtonState<T>();
}

class _FocusablePopupMenuButtonState<T> extends State<FocusablePopupMenuButton<T>> {
  final _ownedMenuKey = GlobalKey<PopupMenuButtonState<T>>();

  GlobalKey<PopupMenuButtonState<T>> get _menuKey => widget.menuKey ?? _ownedMenuKey;

  void _showMenu() => _menuKey.currentState?.showButtonMenu();

  @override
  Widget build(BuildContext context) {
    return FocusableWrapper(
      focusNode: widget.focusNode,
      disableScale: true,
      borderRadius: widget.borderRadius,
      useBackgroundFocus: widget.useBackgroundFocus,
      descendantsAreFocusable: false,
      semanticLabel: widget.semanticLabel ?? widget.tooltip,
      enableLongPress: widget.enableLongPress,
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onNavigateLeft: widget.onNavigateLeft,
      onNavigateRight: widget.onNavigateRight,
      onSelect: _showMenu,
      onLongPress: widget.enableLongPress ? _showMenu : null,
      child: PopupMenuButton<T>(
        key: _menuKey,
        icon: widget.icon,
        tooltip: widget.tooltip,
        requestFocus: true,
        onSelected: widget.onSelected,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }
}
