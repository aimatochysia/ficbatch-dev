import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

/// "Update available" dialog: shows what's new and opens the platform's
/// installer download (or the release page) in the system browser.
Future<void> showUpdatePrompt(BuildContext context, UpdateInfo info) async {
  final download = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Update available: ${info.tag}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('You have v${info.currentVersion}. '
                '${info.assetName != null ? 'Download ${info.assetName} and open it to update in place — your library and settings are kept.' : 'Open the releases page to get the new build.'}'),
            if (info.notes != null && info.notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text("What's new",
                  style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                info.notes!.length > 1200
                    ? '${info.notes!.substring(0, 1200)}…'
                    : info.notes!,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(info.assetName != null ? 'Download update' : 'Open releases'),
        ),
      ],
    ),
  );
  if (download == true) {
    final url = info.assetUrl ?? info.releaseUrl;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
