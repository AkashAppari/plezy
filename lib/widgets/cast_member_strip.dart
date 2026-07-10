import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/card_focus_scope.dart';
import '../media/media_server_client.dart';
import '../services/settings_service.dart';
import '../theme/mono_tokens.dart';
import '../utils/grid_size_calculator.dart';
import '../utils/media_image_helper.dart';
import 'focus_builders.dart';
import 'horizontal_scroll_with_arrows.dart';
import 'optimized_media_image.dart';

/// One person in a [CastMemberStrip]: display name, secondary line
/// (character/role), and an image path — server-relative (resolved through
/// [CastMemberStrip.imageClient]) or an absolute URL.
typedef CastStripMember = ({String name, String? secondary, String? imagePath});

/// Horizontal cast/character strip shared by the media detail screen (server
/// items, actor navigation, dpad locked-focus) and the catalog detail screen
/// (provider items, display-only).
class CastMemberStrip extends StatelessWidget {
  static const double _innerPadding = 3;

  final List<CastStripMember> members;

  /// Resolves server-relative image paths; null when [members] carry
  /// absolute URLs.
  final MediaServerClient? imageClient;
  final ScrollController? controller;

  /// Index highlighted by the owner's locked-focus dpad model; null when no
  /// member is focused (or the owner has no focus model).
  final int? focusedIndex;
  final void Function(int index)? onMemberTap;

  const CastMemberStrip({
    super.key,
    required this.members,
    this.imageClient,
    this.controller,
    this.focusedIndex,
    this.onMemberTap,
  });

  /// Card width matching the poster grids' cell width for the user's
  /// density setting.
  static double responsiveCardWidth(BuildContext context) {
    final density = SettingsService.instance.read(SettingsService.libraryDensity);
    final availableWidth = MediaQuery.sizeOf(context).width;
    return GridSizeCalculator.getCellWidth(availableWidth, context, density);
  }

  /// The strip's fixed height for a given card width:
  /// image + inner padding + text area + list padding + focus scale headroom.
  static double heightForCardWidth(double cardWidth) => cardWidth + _innerPadding * 2 + 58 + 10;

  /// One item's horizontal extent (card + inner padding + trailing gap) for
  /// owners doing their own ensure-visible scroll math (media detail dpad).
  static double itemExtentForCardWidth(double cardWidth) => cardWidth + _innerPadding * 2 + 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final cardWidth = responsiveCardWidth(context);
    final imageSize = cardWidth;

    return SizedBox(
      height: heightForCardWidth(cardWidth),
      child: HorizontalScrollWithArrows(
        controller: controller,
        builder: (scrollController) => ListView.builder(
          addAutomaticKeepAlives: false,
          addSemanticIndexes: false,
          controller: scrollController,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(vertical: 5),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final member = members[index];

            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FocusBuilders.buildLockedFocusWrapper(
                context: context,
                isFocused: index == focusedIndex,
                borderRadius: tokens(context).radiusSm,
                onTap: onMemberTap == null ? null : () => onMemberTap!(index),
                delegateFocusBorder: true,
                child: Padding(
                  padding: const EdgeInsets.all(_innerPadding),
                  child: SizedBox(
                    width: cardWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CardFocusBorder(
                          borderRadius: tokens(context).radiusSm,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                            child: OptimizedMediaImage(
                              client: imageClient,
                              imagePath: member.imagePath,
                              width: imageSize,
                              height: imageSize,
                              fit: BoxFit.cover,
                              imageType: ImageType.avatar,
                              fallbackIcon: Symbols.person_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(member.name, style: nameStyle, maxLines: 2, overflow: TextOverflow.ellipsis),
                              if (member.secondary != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  member.secondary!,
                                  style: secondaryStyle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
