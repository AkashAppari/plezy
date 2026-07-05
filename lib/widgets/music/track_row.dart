import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_tile_mixin.dart';
import '../../focus/input_mode_tracker.dart';
import '../../focus/key_event_utils.dart';
import '../../media/media_item.dart';
import '../../mixins/context_menu_tap_mixin.dart';
import '../../services/device_performance.dart';
import '../../services/music/music_playback_service.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/formatters.dart';
import '../app_icon.dart';
import '../media_context_menu.dart';

/// List row for a music track:
/// `[track # | equalizer] [title + optional artist] [duration] [⋮]`.
///
/// Rows sit inside the M3E grouped-card idiom (see `SettingsGroup`):
/// [isFirst]/[isLast] pick large outer / small inner corner radii, and the
/// hosting list inserts `tokens.groupGap` between adjacent rows.
///
/// D-pad model: one focus node with two columns — column 0 is the row itself
/// (SELECT = [onTap]), RIGHT moves the highlight to the ⋮ button (LEFT
/// returns; SELECT there opens the same context menu as long-press /
/// right-click). Focus is rendered as a background fill, never an outline.
class TrackRow extends StatefulWidget {
  /// Fixed row height, sized for title + optional subtitle.
  static const double height = 56;

  final MediaItem item;
  final VoidCallback? onTap;
  final void Function(String itemId)? onRefresh;

  /// Grouped-card corner shaping (see class doc).
  final bool isFirst;
  final bool isLast;

  /// Always show the performing-artist subtitle — for surfaces outside an
  /// album context. Within an album the subtitle only appears when the track
  /// artist differs from the album artist (compilations).
  final bool showArtist;

  /// Optional external focus node for programmatic focus control.
  final FocusNode? focusNode;

  /// Called on UP from the row (wired by the host on the first row only, so
  /// the list edge escapes to the action bar).
  final VoidCallback? onNavigateUp;

  /// Called on BACK while the row is focused.
  final VoidCallback? onBack;

  final ValueChanged<bool>? onFocusChange;

  const TrackRow({
    super.key,
    required this.item,
    this.onTap,
    this.onRefresh,
    this.isFirst = false,
    this.isLast = false,
    this.showArtist = false,
    this.focusNode,
    this.onNavigateUp,
    this.onBack,
    this.onFocusChange,
  });

  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> with ContextMenuTapMixin<TrackRow>, FocusableTileStateMixin<TrackRow> {
  /// 0 = row (SELECT plays), 1 = ⋮ button (SELECT opens the context menu).
  int _focusedColumn = 0;
  bool _hasFocus = false;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  void initState() {
    super.initState();
    initFocusNode();
  }

  @override
  void didUpdateWidget(TrackRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateFocusNode(oldWidget.focusNode);
  }

  @override
  void dispose() {
    disposeFocusNode();
    super.dispose();
  }

  void _handleFocusChange(bool hasFocus) {
    setState(() {
      _hasFocus = hasFocus;
      if (!hasFocus) _focusedColumn = 0;
    });
    widget.onFocusChange?.call(hasFocus);
  }

  void _activateFocusedColumn() {
    if (_focusedColumn == 0) {
      widget.onTap?.call();
    } else {
      // Keyboard/gamepad activation — the menu centers on the row.
      showContextMenu();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onBack != null) {
      final backResult = handleBackKeyAction(event, widget.onBack!);
      if (backResult != KeyEventResult.ignored) return backResult;
    }
    return dpadKeyHandler(
      onSelect: _activateFocusedColumn,
      onUp: widget.onNavigateUp,
      onLeft: _focusedColumn == 1 ? () => setState(() => _focusedColumn = 0) : null,
      onRight: _focusedColumn == 0 ? () => setState(() => _focusedColumn = 1) : null,
      // Detail screens have nothing beside the list — keep focus on the row.
      trapHorizontalEdges: true,
    )(node, event);
  }

  void _showMenuAt(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject() as RenderBox?;
    Offset? position;
    if (box != null) position = box.localToGlobal(box.size.center(Offset.zero));
    contextMenuKey.currentState?.showContextMenu(context, position: position);
  }

  String? get _subtitle {
    final trackArtist = widget.item.trackArtistTitle;
    if (trackArtist == null || trackArtist.isEmpty) return null;
    if (widget.showArtist) return trackArtist;
    return trackArtist != widget.item.albumArtistTitle ? trackArtist : null;
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final colorScheme = Theme.of(context).colorScheme;

    // Both selects run unconditionally every build (provider contract).
    final isCurrent = context.select<MusicPlaybackService, bool>((s) => s.currentTrack?.id == widget.item.id);
    final serviceIsPlaying = context.select<MusicPlaybackService, bool>((s) => s.isPlaying);

    final showFocus = _hasFocus && InputModeTracker.isKeyboardMode(context);
    final radii = BorderRadius.vertical(
      top: Radius.circular(widget.isFirst ? tk.radiusLg : tk.radiusXs),
      bottom: Radius.circular(widget.isLast ? tk.radiusLg : tk.radiusXs),
    );

    final subtitle = _subtitle;
    final durationMs = widget.item.durationMs;

    return MediaContextMenu(
      key: contextMenuKey,
      item: widget.item,
      onRefresh: widget.onRefresh,
      onTap: widget.onTap,
      child: Focus(
        focusNode: effectiveFocusNode,
        descendantsAreFocusable: false,
        onKeyEvent: _handleKeyEvent,
        onFocusChange: _handleFocusChange,
        child: Material(
          color: tk.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: radii),
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: widget.onTap,
            onTapDown: storeTapPosition,
            onLongPress: showContextMenuFromTap,
            onSecondaryTapDown: storeTapPosition,
            onSecondaryTap: showContextMenuFromTap,
            child: Container(
              height: TrackRow.height,
              // Text-based fill (mono theme focusColor convention) — the
              // white-based FocusTheme fill is invisible on the light row
              // surface.
              decoration: BoxDecoration(
                borderRadius: radii,
                color: showFocus && _focusedColumn == 0 ? tk.text.withValues(alpha: 0.12) : Colors.transparent,
              ),
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: isCurrent
                          ? _EqualizerIcon(animate: serviceIsPlaying, color: colorScheme.primary)
                          : Text(
                              '${widget.item.trackNumber ?? ''}',
                              style: TextStyle(fontSize: 13, color: tk.textMuted),
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: .center,
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          widget.item.title ?? '',
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                            color: isCurrent ? tk.text : null,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: TextStyle(fontSize: 12, color: tk.textMuted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (durationMs != null)
                    Text(
                      formatDurationTimestamp(Duration(milliseconds: durationMs)),
                      style: TextStyle(fontSize: 13, color: tk.textMuted),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: showFocus && _focusedColumn == 1 ? tk.text.withValues(alpha: 0.12) : Colors.transparent,
                    ),
                    child: Builder(
                      builder: (buttonContext) => IconButton(
                        icon: AppIcon(Symbols.more_vert_rounded, fill: 1, size: 20, color: tk.textMuted),
                        onPressed: () => _showMenuAt(buttonContext),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small 3-bar "now playing" indicator. Bars animate while [animate] is true;
/// on the reduced visual-effects tier they render static regardless (each
/// animation frame re-rasterizes the row on weak TV GPUs).
class _EqualizerIcon extends StatefulWidget {
  final bool animate;
  final Color color;

  const _EqualizerIcon({required this.animate, required this.color});

  @override
  State<_EqualizerIcon> createState() => _EqualizerIconState();
}

class _EqualizerIconState extends State<_EqualizerIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  bool get _shouldAnimate => widget.animate && !DevicePerformance.isReduced;

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_EqualizerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_shouldAnimate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _EqualizerPainter(t: _controller.value, color: widget.color, animate: _shouldAnimate),
        ),
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  final double t;
  final Color color;
  final bool animate;

  /// Static bar heights (fraction of full height) for the paused/reduced look.
  static const List<double> _staticHeights = [0.55, 0.9, 0.4];

  /// Per-bar phase offsets so the animated bars move out of step.
  static const List<double> _phases = [0.0, 0.35, 0.7];

  const _EqualizerPainter({required this.t, required this.color, required this.animate});

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 3;
    const gap = 2.5;
    final barWidth = (size.width - gap * (barCount - 1)) / barCount;
    final paint = Paint()..color = color;

    for (var i = 0; i < barCount; i++) {
      final fraction = animate ? 0.3 + 0.7 * (0.5 + 0.5 * math.sin(2 * math.pi * (t + _phases[i]))) : _staticHeights[i];
      final barHeight = size.height * fraction;
      final left = i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - barHeight, barWidth, barHeight),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EqualizerPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color || oldDelegate.animate != animate;
}
