import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_icon.dart';

class MediaSelectorThumbnail extends StatelessWidget {
  final double width;
  final double height;
  final Widget? thumbnail;
  final bool isCurrent;
  final double radius;
  final Color borderColor;
  final Color fallbackBackgroundColor;
  final Color fallbackIconColor;
  final double fallbackIconSize;
  final IconData fallbackIcon;

  const MediaSelectorThumbnail({
    super.key,
    required this.width,
    required this.height,
    required this.thumbnail,
    required this.isCurrent,
    required this.borderColor,
    this.radius = 4,
    this.fallbackBackgroundColor = Colors.white10,
    this.fallbackIconColor = Colors.white38,
    this.fallbackIconSize = 28,
    this.fallbackIcon = Symbols.movie_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.all(Radius.circular(radius));
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: borderRadius,
            child:
                thumbnail ??
                Container(
                  color: fallbackBackgroundColor,
                  child: Center(
                    child: AppIcon(fallbackIcon, fill: 1, color: fallbackIconColor, size: fallbackIconSize),
                  ),
                ),
          ),
          if (isCurrent)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.fromBorderSide(BorderSide(color: borderColor, width: 2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
