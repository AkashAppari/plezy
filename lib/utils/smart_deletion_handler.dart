import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../i18n/strings.g.dart';
import '../providers/download_provider.dart';
import '../widgets/deletion_progress_dialog.dart';
import 'dialogs.dart';

class SmartDeletionHandler {
  /// Execute deletion with smart progress dialog
  /// Only shows dialog if deletion takes longer than delayMs
  static Future<void> deleteWithProgress({
    required BuildContext context,
    required DownloadProvider provider,
    required String globalKey,
    int delayMs = 500,
  }) async {
    bool deletionComplete = false;
    final dialogKey = GlobalKey();

    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!deletionComplete && context.mounted) {
        _showProgressDialog(context, provider, globalKey, dialogKey);
      }
    });

    try {
      await provider.deleteDownload(globalKey);
    } finally {
      deletionComplete = true;
      final dialogContext = dialogKey.currentContext;
      if (dialogContext != null && dialogContext.mounted) {
        final route = ModalRoute.of(dialogContext);
        if (route != null && route.isActive) {
          Navigator.of(dialogContext).removeRoute(route);
        }
      }
    }
  }

  static void _showProgressDialog(BuildContext context, DownloadProvider _, String globalKey, GlobalKey dialogKey) {
    showScopedDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => KeyedSubtree(
        key: dialogKey,
        child: Consumer<DownloadProvider>(
          builder: (context, provider, child) {
            final progress = provider.getDeletionProgress(globalKey);

            if (progress == null) {
              return AlertDialog(
                content: Row(
                  mainAxisSize: .min,
                  children: [const CircularProgressIndicator(), const SizedBox(width: 20), Text(t.downloads.deleting)],
                ),
              );
            }

            return DeletionProgressDialog(progress: progress);
          },
        ),
      ),
    );
  }
}
