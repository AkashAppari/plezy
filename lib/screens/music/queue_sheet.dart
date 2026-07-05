import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../services/music/music_playback_service.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/media_image_helper.dart';
import '../../utils/platform_detector.dart';
import '../../utils/provider_extensions.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/bottom_sheet_header.dart';
import '../../widgets/music/equalizer_icon.dart';
import '../../widgets/music/repeat_mode.dart';
import '../../widgets/music/track_row.dart';
import '../../widgets/optimized_media_image.dart';
import '../../widgets/overlay_sheet.dart';

/// Open the play-queue sheet. The caller's screen must have an
/// [OverlaySheetHost] ancestor (all now-playing layouts do) so TV back
/// handling stays centralized in the host.
Future<void> showQueueSheet(BuildContext context) {
  return OverlaySheetController.showAdaptive<void>(context, showDragHandle: true, builder: (_) => const QueueSheet());
}

/// Sheet chrome around [QueueList]: header with track count, shuffle/repeat
/// toggles mirroring the service state, and Clear (upcoming) action.
class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final service = context.watch<MusicPlaybackService>();
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: .min,
      children: [
        BottomSheetHeader(
          title: t.music.queue,
          action: Row(
            mainAxisSize: .min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  t.music.trackCount(n: service.queue.length),
                  style: TextStyle(fontSize: 13, color: tk.textMuted),
                ),
              ),
              IconButton(
                icon: AppIcon(
                  Symbols.shuffle_rounded,
                  fill: 1,
                  size: 20,
                  color: service.shuffled ? colorScheme.primary : tk.textMuted,
                ),
                tooltip: t.common.shuffle,
                onPressed: service.toggleShuffle,
              ),
              IconButton(
                icon: AppIcon(
                  repeatModeIcon(service.repeatMode),
                  fill: 1,
                  size: 20,
                  color: service.repeatMode == MusicRepeatMode.off ? tk.textMuted : colorScheme.primary,
                ),
                tooltip: repeatModeLabel(service.repeatMode),
                onPressed: () => service.setRepeatMode(nextRepeatMode(service.repeatMode)),
              ),
              IconButton(
                icon: AppIcon(Symbols.clear_all_rounded, fill: 1, size: 20, color: tk.textMuted),
                tooltip: t.music.clearQueue,
                onPressed: service.clearUpcoming,
              ),
            ],
          ),
        ),
        const Flexible(child: QueueList()),
      ],
    );
  }
}

/// The queue body: pinned current-track row, "Up next" label, and the
/// upcoming tracks as [TrackRow]s. Reused verbatim by the desktop
/// now-playing layout as an inline panel.
///
/// Touch: long-press drag to reorder (delayed drag listener — TrackRow's
/// context menu is disabled here so the gesture arena stays clean), swipe to
/// remove, tap to jump. D-pad: rows are focusable, SELECT jumps, RIGHT
/// reaches a dedicated remove button; reordering is intentionally not
/// offered on TV.
class QueueList extends StatelessWidget {
  const QueueList({super.key});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final service = context.watch<MusicPlaybackService>();
    final queue = service.queue;
    final currentIndex = service.currentIndex;
    final current = service.currentTrack;
    final upcomingStart = currentIndex + 1;
    final upcoming = currentIndex >= 0 && upcomingStart <= queue.length
        ? queue.sublist(upcomingStart)
        : const <MediaItem>[];

    // Stable per-item keys that survive reorders; the same track can appear
    // more than once, so disambiguate repeats by occurrence.
    final seen = <String, int>{};
    final itemKeys = [
      for (final item in upcoming) '${item.globalKey}#${seen.update(item.globalKey, (v) => v + 1, ifAbsent: () => 0)}',
    ];

    final allowTouchEditing = !PlatformDetector.isTV();

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        if (current != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _CurrentTrackRow(track: current),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            t.music.upNext,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(color: tk.textMuted, fontWeight: .w600),
          ),
        ),
        Flexible(
          child: upcoming.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Text(t.messages.noItemsAvailable, style: TextStyle(fontSize: 13, color: tk.textMuted)),
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: upcoming.length,
                  // onReorderItem already adjusts newIndex for the removal.
                  onReorderItem: (oldIndex, newIndex) {
                    if (oldIndex == newIndex) return;
                    service.reorder(upcomingStart + oldIndex, upcomingStart + newIndex);
                  },
                  itemBuilder: (context, index) {
                    final item = upcoming[index];
                    final queueIndex = upcomingStart + index;

                    Widget row = TrackRow(
                      item: item,
                      showArtist: true,
                      isFirst: index == 0,
                      isLast: index == upcoming.length - 1,
                      enableContextMenu: false,
                      trailingIcon: Symbols.close_rounded,
                      onTrailingTap: () => service.removeAt(queueIndex),
                      onTap: () => unawaited(service.jumpTo(queueIndex)),
                    );

                    if (allowTouchEditing) {
                      row = ReorderableDelayedDragStartListener(index: index, child: row);
                      row = Dismissible(
                        key: ValueKey('dismiss:${itemKeys[index]}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: .centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const AppIcon(Symbols.delete_rounded, fill: 1, color: Colors.white, size: 20),
                        ),
                        onDismissed: (_) => service.removeAt(queueIndex),
                        child: row,
                      );
                    }

                    return Padding(
                      key: ValueKey(itemKeys[index]),
                      padding: EdgeInsets.only(top: index == 0 ? 0 : tk.groupGap),
                      child: row,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Pinned "now playing" row at the top of the queue: square art, title +
/// artist, and the shared equalizer indicator.
class _CurrentTrackRow extends StatelessWidget {
  final MediaItem track;

  const _CurrentTrackRow({required this.track});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isPlaying = context.select<MusicPlaybackService, bool>((s) => s.isPlaying);
    final client = context.tryGetMediaClientWithFallback(serverIdOrNull(track.serverId));
    final artist = track.trackArtistTitle;

    return Material(
      color: tk.surface,
      borderRadius: BorderRadius.circular(tk.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(tk.radiusSm),
              child: OptimizedMediaImage(
                client: client,
                imagePath: track.thumbPath,
                imageType: ImageType.square,
                width: 44,
                height: 44,
                fallbackIcon: Symbols.music_note_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: .center,
                crossAxisAlignment: .start,
                children: [
                  Text(
                    track.title ?? '',
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: .w600, color: tk.text),
                  ),
                  if (artist != null && artist.isNotEmpty)
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: TextStyle(fontSize: 12, color: tk.textMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: EqualizerIcon(animate: isPlaying, color: colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}
