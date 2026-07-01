import 'package:flutter/widgets.dart';

import '../focus/focus_theme.dart';

/// Dims the content beneath it by drawing a translucent [color] quad on top,
/// as a saveLayer-free replacement for wrapping the content in
/// [AnimatedOpacity]. Widget opacity below 1.0 forces an offscreen render
/// pass every frame — a permanent GPU cost on the weak GLES devices most
/// Android TVs are — while a color-blended quad is free. Over a
/// [color]-colored underlay the result is mathematically identical to
/// `Opacity(opacity: 1 - alpha)`; over artwork it darkens toward [color]
/// instead of turning translucent.
///
/// Stack this above the content (with `IgnorePointer` built in so taps pass
/// through). Animates with [FocusTheme.getAnimationDuration], so the full
/// tier fades and the reduced tier snaps, matching the [AnimatedOpacity]
/// behavior it replaces.
class AnimatedDimScrim extends StatelessWidget {
  const AnimatedDimScrim({super.key, required this.dimmed, required this.color, required this.alpha});

  final bool dimmed;
  final Color color;

  /// Scrim strength while [dimmed]; visually equivalent to
  /// `Opacity(opacity: 1 - alpha)` over a [color] underlay.
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: dimmed ? alpha : 0.0),
        duration: FocusTheme.getAnimationDuration(context),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) =>
            value == 0 ? const SizedBox.shrink() : ColoredBox(color: color.withValues(alpha: value)),
      ),
    );
  }
}
